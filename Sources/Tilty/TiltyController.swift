import AppKit
import TiltyCore

/// Keeps a toolbar on each visible window and runs the window moves.
@MainActor
final class TiltyController {

    let tracker = WindowTracker()
    private let preferences: Preferences
    private var windowsByKey: [WindowKey: TrackedWindow] = [:]
    private var panels: [WindowKey: ToolbarPanel] = [:]

    // Layout grid from the chevron, and the window picker that follows it.
    private var grid: LayoutGridPanel?
    private var gridTarget: TrackedWindow?
    private var gridPanelKey: WindowKey?
    private var gridMonitor: DismissMonitor?
    private var assist: SnapAssistSession?

    private var history = TileHistory<WindowKey>()
    private var pollTimer: Timer?
    private var pacer = PollPacer()
    /// What the last poll saw, to tell a quiet poll from a busy one.
    private var lastPolled: [WindowKey: CGRect] = [:]
    private var lastFrames: [WindowKey: CGRect] = [:]
    private var movingWindows = Set<WindowKey>()
    private var settleWork: DispatchWorkItem?
    private var settleDeadline: TimeInterval = 0
    private var refreshQueued = false
    private(set) var isRunning = false

    /// Tracking and polling only happen while this is true.
    /// Off while paused, while the screens sleep and while another user is logged in.
    private var isWatching = false
    private var screensAsleep = false
    private var sessionInactive = false
    private var systemTokens: [NSObjectProtocol] = []
    private var pointerMonitors: [Any] = []

    /// How long a window must hold still before the toolbar comes back after a move.
    private let settleDelay: TimeInterval = 0.15

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// The app whose windows the menu offers settings for.
    var currentApp: NSRunningApplication? {
        if isWatching { return tracker.currentApp }
        let frontmost = NSWorkspace.shared.frontmostApplication
        return frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        tracker.onChange = { [weak self] event in self?.trackerChanged(event) }
        observeSystem()
        updateWatching()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        let center = NSWorkspace.shared.notificationCenter
        systemTokens.forEach(center.removeObserver)
        systemTokens.removeAll()
        updateWatching()
    }

    /// Call after the pause setting changes.
    func pauseChanged() {
        updateWatching()
    }

    // MARK: - Watching

    /// Starts or stops the tracker and the poll so nothing runs when it cannot matter.
    private func updateWatching() {
        let shouldWatch = isRunning && !preferences.isPaused && !screensAsleep && !sessionInactive
        guard shouldWatch != isWatching else { return }
        isWatching = shouldWatch

        if shouldWatch {
            tracker.start()
            startPointerMonitoring()
            pacer.reset()
            lastPolled = [:]
            schedulePoll()
            refresh()
        } else {
            stopPointerMonitoring()
            pollTimer?.invalidate()
            pollTimer = nil
            tracker.stop()
            endAssist()
            hide()
        }
    }

    private func observeSystem() {
        let center = NSWorkspace.shared.notificationCenter
        func on(_ name: Notification.Name, _ body: @escaping @MainActor (TiltyController) -> Void) {
            systemTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    body(self)
                    self.updateWatching()
                }
            })
        }
        on(NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        on(NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        on(NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        on(NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
    }

    // MARK: - Following the window

    private func trackerChanged(_ event: TrackerEvent) {
        if event == .geometry {
            // Tilty is sliding a window. Its own steps echo back here, and the move's completion refreshes.
            if WindowMover.isSliding { return }
            // Already waiting for a drag to settle. Push the wait back without asking the app for anything.
            if settleWork != nil {
                scheduleSettle()
                return
            }
        }
        setNeedsRefresh()
    }

    /// Folds a burst of notifications into one refresh.
    /// Focus and main window changes, for example, usually arrive together.
    private func setNeedsRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshQueued = false
                self.refresh()
            }
        }
    }

    /// Re-reads the relevant window and shows, hides or moves the toolbar.
    func refresh() {
        apply(isWatching ? tracker.visibleWindows() : [])
    }

    private func apply(_ windows: [TrackedWindow]) {
        guard isWatching else {
            hide()
            return
        }

        let currentKeys = Set(windows.map(\.key))
        if let gridTarget, !currentKeys.contains(gridTarget.key) {
            closeLayouts()
        }
        for key in Array(panels.keys) where !currentKeys.contains(key) {
            panels.removeValue(forKey: key)?.close()
            lastFrames[key] = nil
            movingWindows.remove(key)
        }
        windowsByKey = Dictionary(uniqueKeysWithValues: windows.map { ($0.key, $0) })

        if WindowMover.isSliding {
            panels.values.forEach { $0.hide() }
            return
        }
        guard let primaryHeight = NSScreen.screens.first?.frame.height else {
            panels.values.forEach { $0.hide() }
            return
        }

        var foregroundFrames: [CGRect] = []
        for target in windows {
            let key = target.key
            let panel = panel(for: target)
            let windowFrame = Geometry.flip(target.frame, primaryScreenHeight: primaryHeight)
            let toolbarFrame = toolbarFrame(for: target)
            let toolbarIsOccluded = toolbarFrame.map { frame in
                foregroundFrames.contains { $0.intersects(frame) }
            } ?? true

            if let gridTarget, gridTarget.key == key,
               !Geometry.approximatelyEqual(gridTarget.frame, target.frame, tolerance: 0.5) {
                closeLayouts()
            }
            foregroundFrames.append(windowFrame)

            if let lastFrame = lastFrames[key], !Geometry.approximatelyEqual(lastFrame, target.frame, tolerance: 0.5) {
                lastFrames[key] = target.frame
                movingWindows.insert(key)
                panel.hide()
                scheduleSettle()
                continue
            }
            if movingWindows.contains(key) { continue }

            lastFrames[key] = target.frame
            if let toolbarFrame, !toolbarIsOccluded {
                panel.show(at: toolbarFrame.origin)
            } else {
                panel.hide()
            }
        }
    }

    private func panel(for target: TrackedWindow) -> ToolbarPanel {
        if let panel = panels[target.key] { return panel }
        let key = target.key
        let panel = ToolbarPanel(
            onAction: { [weak self] action in self?.perform(action, for: key) },
            onLayouts: { [weak self] _ in self?.toggleLayouts(for: key) }
        )
        panels[key] = panel
        return panel
    }

    private func toolbarFrame(for focused: TrackedWindow) -> CGRect? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }

        var placement = preferences.placement(forBundleID: focused.app.bundleIdentifier)
        let size = ToolbarPanel.panelSize

        // A narrow window has no room at the right end. Fall back to the left.
        if placement == .rightEnd, let zoom = focused.zoomButton,
           focused.frame.maxX - size.width - Geometry.Layout.rightEndInset < zoom.maxX + Geometry.Layout.gapAfterZoomButton {
            placement = .afterTrafficLights
        }

        let origin = Geometry.toolbarOrigin(
            zoomButton: focused.zoomButton,
            window: focused.frame,
            toolbarSize: size,
            placement: placement,
            primaryScreenHeight: primaryHeight
        )

        // Skip windows too narrow to hold the toolbar next to the traffic lights.
        let windowCocoa = Geometry.flip(focused.frame, primaryScreenHeight: primaryHeight)
        guard origin.x + size.width <= windowCocoa.maxX - 8 else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Waits until the window has held still for `settleDelay`.
    /// A drag sends many notifications. Each one only moves the deadline, so there is one timer, not one per notification.
    private func scheduleSettle() {
        settleDeadline = ProcessInfo.processInfo.systemUptime + settleDelay
        if settleWork == nil {
            armSettle(after: settleDelay)
        }
    }

    private func armSettle(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let remaining = self.settleDeadline - ProcessInfo.processInfo.systemUptime
                if remaining > 0.005 {
                    self.armSettle(after: remaining)
                    return
                }
                self.settleWork = nil
                self.movingWindows.removeAll()
                self.refresh()
            }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
    }

    private func hide() {
        closeLayouts()
        settleWork?.cancel()
        settleWork = nil
        movingWindows.removeAll()
        lastFrames.removeAll()
        windowsByKey.removeAll()
        panels.values.forEach { $0.close() }
        panels.removeAll()
    }

    // MARK: - Backup poll

    /// Some apps never report moves or focus changes, so Tilty also checks now and then.
    /// It checks often while the window is changing and rarely once it is still.
    private func schedulePoll() {
        let interval = pacer.interval
        if let pollTimer, pollTimer.isValid, pollTimer.timeInterval == interval { return }
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        // Let macOS line this wakeup up with others.
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        guard isWatching else { return }
        tracker.ensureAttached()
        let windows = tracker.visibleWindows()

        let seen = Dictionary(uniqueKeysWithValues: windows.map { ($0.key, $0.frame) })
        let changed = seen != lastPolled
        lastPolled = seen
        pacer.record(changed: changed)
        schedulePoll()

        apply(windows)
    }

    // MARK: - Window dragging

    private func startPointerMonitoring() {
        guard pointerMonitors.isEmpty else { return }
        let dragEvents: NSEvent.EventTypeMask = [.leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: dragEvents, handler: { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handleDragEvent(event) }
            }
        }) {
            pointerMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: dragEvents, handler: { [weak self] event in
            self?.handleDragEvent(event)
            return event
        }) {
            pointerMonitors.append(local)
        }
    }

    private func stopPointerMonitoring() {
        pointerMonitors.forEach(NSEvent.removeMonitor)
        pointerMonitors.removeAll()
    }

    private func handleDragEvent(_ event: NSEvent) {
        guard event.type == .leftMouseDragged || event.type == .rightMouseDragged else { return }
        panels.values.forEach { $0.hide() }
        scheduleSettle()
    }

    // MARK: - Actions

    private func perform(_ action: TileAction, for key: WindowKey) {
        guard let focused = windowsByKey[key],
              let primaryHeight = NSScreen.screens.first?.frame.height else { return }

        let screens = NSScreen.screens
        let current = Geometry.flip(focused.frame, primaryScreenHeight: primaryHeight)
        guard let index = Geometry.bestScreenIndex(for: current, screens: screens.map(\.frame)) else { return }

        let target = Geometry.targetFrame(for: action, in: screens[index].visibleFrame)
        let frame = history.resolve(key: key, action: action, current: current, target: target)

        // Optional: after Left or Right, offer windows for the other side.
        // Not after a second click that restores the window.
        let leftover = SnapLayout.leftover(after: action)
        var zoneFrames: [CGRect] = []
        if preferences.suggestAfterHalves, frame == target, !leftover.isEmpty {
            let visible = screens[index].visibleFrame
            zoneFrames = leftover.map { Geometry.frame(forZone: $0, in: visible) }
        }

        let window = focused.window
        beginMove(for: key)
        WindowMover.move(
            cocoaFrame: frame,
            to: window,
            appElement: focused.appElement,
            primaryScreenHeight: primaryHeight,
            animated: preferences.animateMoves
        ) { [weak self] in
            // Apps can clamp sizes or finish resizing a moment later.
            // Remember what they actually settled on so a second click still restores.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let actual = window.frame, let height = NSScreen.screens.first?.frame.height {
                        self.history.recordApplied(key: key, frame: Geometry.flip(actual, primaryScreenHeight: height))
                    }
                    self.finishMove(for: key)
                    if !zoneFrames.isEmpty {
                        self.startAssist(zoneFrames: zoneFrames, excluding: [key])
                    }
                }
            }
        }
    }

    /// Hides the toolbar while Tilty moves a window.
    private func beginMove(for key: WindowKey) {
        movingWindows.insert(key)
        panels[key]?.hide()
    }

    /// Brings the toolbar back at the window's new frame, without waiting for another settle.
    private func finishMove(for key: WindowKey? = nil) {
        if let key {
            movingWindows.remove(key)
            lastFrames[key] = nil
        } else {
            movingWindows.removeAll()
            lastFrames.removeAll()
        }
        refresh()
    }

    // MARK: - Layout grid

    private func toggleLayouts(for key: WindowKey) {
        if grid != nil {
            closeLayouts()
            return
        }
        endAssist()
        guard let focused = windowsByKey[key], let panel = panels[key] else { return }

        let grid = LayoutGridPanel(
            showStageManagerNotice: StageManager.isOn,
            onOpenSettings: { [weak self] in
                self?.closeLayouts()
                StageManager.openSettings()
            },
            onPick: { [weak self] layout, zone in self?.place(in: layout, zone: zone) }
        )
        grid.show(below: panel.frame)
        self.grid = grid
        gridTarget = focused
        gridPanelKey = key
        panel.setLayoutsOpen(true)
        gridMonitor = DismissMonitor { [weak self] in
            MainActor.assumeIsolated { self?.closeLayouts() }
        }
    }

    private func closeLayouts() {
        guard grid != nil else { return }
        gridMonitor?.stop()
        gridMonitor = nil
        grid?.orderOut(nil)
        grid = nil
        gridTarget = nil
        if let gridPanelKey { panels[gridPanelKey]?.setLayoutsOpen(false) }
        gridPanelKey = nil
    }

    /// Puts the window into the picked zone, then offers windows for the other zones.
    private func place(in layout: SnapLayout, zone index: Int) {
        guard let target = gridTarget,
              let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        // Close first so the hide-while-moving logic does not fight an open grid.
        closeLayouts()

        let screens = NSScreen.screens
        let current = Geometry.flip(target.frame, primaryScreenHeight: primaryHeight)
        guard let screenIndex = Geometry.bestScreenIndex(for: current, screens: screens.map(\.frame)) else { return }
        let visible = screens[screenIndex].visibleFrame

        let frame = Geometry.frame(forZone: layout.zones[index], in: visible)
        let rest = layout.remainingZones(after: index).map { Geometry.frame(forZone: $0, in: visible) }
        let placed = target.key
        beginMove(for: placed)
        WindowMover.move(
            cocoaFrame: frame,
            to: target.window,
            appElement: target.appElement,
            primaryScreenHeight: primaryHeight,
            animated: preferences.animateMoves
        ) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.finishMove(for: placed)
                    if !rest.isEmpty {
                        self.startAssist(zoneFrames: rest, excluding: [placed])
                    }
                }
            }
        }
    }

    // MARK: - Window picker

    private func startAssist(zoneFrames: [CGRect], excluding: Set<WindowKey>) {
        endAssist()
        let session = SnapAssistSession(
            zoneFrames: zoneFrames,
            excluding: excluding,
            animated: preferences.animateMoves,
            onMoved: { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    MainActor.assumeIsolated { self?.finishMove() }
                }
            },
            onFinish: { [weak self] in self?.assist = nil }
        )
        assist = session
        session?.start()
    }

    private func endAssist() {
        assist?.finish()
        assist = nil
    }
}
