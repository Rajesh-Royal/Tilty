import AppKit
import TiltyCore

/// Keeps the toolbar glued to the active window and runs the window moves.
@MainActor
final class TiltyController {

    let tracker = WindowTracker()
    private let preferences: Preferences
    private lazy var panel = ToolbarPanel { [weak self] action in
        self?.perform(action)
    }

    private var history = TileHistory<WindowKey>()
    private var pollTimer: Timer?
    private var settleWork: DispatchWorkItem?
    private var lastWindow: WindowKey?
    private var lastFrame: CGRect?
    private(set) var isRunning = false

    /// How long a window must hold still before the toolbar comes back after a move.
    private let settleDelay: TimeInterval = 0.15
    /// Backup check for apps that do not send move or focus notifications.
    private let pollInterval: TimeInterval = 0.4

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        tracker.onChange = { [weak self] in self?.refresh() }
        tracker.start()

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tracker.ensureAttached()
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        refresh()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        tracker.stop()
        hide()
        isRunning = false
    }

    /// Re-reads the focused window and shows, hides or moves the toolbar.
    func refresh() {
        guard isRunning, !preferences.isPaused, let focused = tracker.focusedWindow() else {
            hide()
            return
        }

        let key = focused.key
        let frame = focused.frame

        // Same window, new frame: it is being dragged or resized.
        // Hide while it moves and come back once it settles, instead of lagging behind.
        if key == lastWindow, let lastFrame, !Geometry.approximatelyEqual(lastFrame, frame, tolerance: 0.5) {
            self.lastFrame = frame
            panel.hide()
            scheduleSettle()
            return
        }

        // Waiting for a move to settle.
        if settleWork != nil, key == lastWindow { return }

        lastWindow = key
        lastFrame = frame
        position(for: focused)
    }

    private func position(for focused: FocusedWindow) {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else {
            panel.hide()
            return
        }

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
        guard origin.x + size.width <= windowCocoa.maxX - 8 else {
            panel.hide()
            return
        }

        panel.show(at: origin)
    }

    private func scheduleSettle() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.settleWork = nil
                self?.refresh()
            }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
    }

    private func hide() {
        settleWork?.cancel()
        settleWork = nil
        lastWindow = nil
        lastFrame = nil
        panel.hide()
    }

    // MARK: - Actions

    func perform(_ action: TileAction) {
        guard let focused = tracker.focusedWindow(),
              let primaryHeight = NSScreen.screens.first?.frame.height else { return }

        let screens = NSScreen.screens
        let current = Geometry.flip(focused.frame, primaryScreenHeight: primaryHeight)
        guard let index = Geometry.bestScreenIndex(for: current, screens: screens.map(\.frame)) else { return }

        let target = Geometry.targetFrame(for: action, in: screens[index].visibleFrame)
        let key = focused.key
        let frame = history.resolve(key: key, action: action, current: current, target: target)

        WindowMover.apply(
            cocoaFrame: frame,
            to: focused.window,
            appElement: focused.appElement,
            primaryScreenHeight: primaryHeight
        )

        // Apps can clamp sizes or finish resizing a moment later.
        // Remember what they actually settled on so a second click still restores.
        let window = focused.window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let actual = window.frame,
                      let height = NSScreen.screens.first?.frame.height else { return }
                self.history.recordApplied(key: key, frame: Geometry.flip(actual, primaryScreenHeight: height))
                self.refresh()
            }
        }
    }
}
