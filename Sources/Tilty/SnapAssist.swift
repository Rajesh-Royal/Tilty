import AppKit
import ApplicationServices
import TiltyCore

// MARK: - Finding other windows

/// Another app's window that can be placed into an empty zone.
struct WindowCandidate {
    let app: NSRunningApplication
    let appElement: AXUIElement
    let window: AXUIElement
    let title: String

    var key: WindowKey { WindowKey(element: window) }
}

enum WindowCatalog {

    /// Regular windows of visible apps, front to back, minus the ones in `excluding`.
    static func candidates(excluding excluded: Set<WindowKey>, limit: Int = 20) -> [WindowCandidate] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let order = frontToBackPIDs()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != ownPID }
            .sorted { (order[$0.processIdentifier] ?? .max) < (order[$1.processIdentifier] ?? .max) }

        var result: [WindowCandidate] = []
        for app in apps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            // One stuck app must not freeze the picker.
            AXUIElementSetMessagingTimeout(appElement, 0.1)
            guard let windows = appElement.copyValue(kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for window in windows {
                guard window.string(kAXSubroleAttribute) == kAXStandardWindowSubrole,
                      window.bool(kAXMinimizedAttribute) != true,
                      window.bool(AXName.fullScreen) != true,
                      !excluded.contains(WindowKey(element: window)) else { continue }
                let rawTitle = window.string(kAXTitleAttribute)?.trimmingCharacters(in: .whitespaces) ?? ""
                let title = rawTitle.isEmpty ? (app.localizedName ?? "Window") : rawTitle
                result.append(WindowCandidate(app: app, appElement: appElement, window: window, title: title))
                if result.count >= limit { return result }
            }
        }
        return result
    }

    /// Process IDs ranked by their frontmost on-screen window.
    private static func frontToBackPIDs() -> [pid_t: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var rank: [pid_t: Int] = [:]
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            if let pid = info[kCGWindowOwnerPID as String] as? pid_t, rank[pid] == nil {
                rank[pid] = rank.count
            }
        }
        return rank
    }

    /// Brings a window to the front through Accessibility.
    /// `NSRunningApplication.activate()` can be refused for background apps on newer macOS.
    static func raise(_ candidate: WindowCandidate) {
        candidate.appElement.setBool(kAXFrontmostAttribute, true)
        AXUIElementPerformAction(candidate.window, kAXRaiseAction as CFString)
    }
}

// MARK: - The picker panels

/// One row in a picker panel.
struct PickerRow {
    let icon: NSImage?
    let title: String
    let subtitle: String
}

/// Fills one empty zone and lists windows to put there.
final class AssistPanel: NSPanel {

    static let rowHeight: CGFloat = 48

    init(frame: NSRect, rows: [PickerRow], showStageManagerNotice: Bool = false, onChoose: @escaping (Int) -> Void) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        configureOverlayPanel(self)

        let background = makeOverlayBackground(size: frame.size, cornerRadius: 14, material: .hudWindow)
        background.appearance = NSAppearance(named: .vibrantDark)

        let heading = NSTextField(labelWithString: "Choose a window for this space")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        heading.textColor = .white

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        for (index, row) in rows.enumerated() {
            let view = PickerRowView(row: row) { onChoose(index) }
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        for view in [heading, scroll] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        // With Stage Manager on, explain why picked windows hide the others.
        var listTop = heading.bottomAnchor
        if showStageManagerNotice {
            let notice = makeStageManagerNotice(width: max(160, frame.width - 36), textColor: NSColor.white.withAlphaComponent(0.8)) {
                StageManager.openSettings()
            }
            background.addSubview(notice)
            NSLayoutConstraint.activate([
                notice.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
                notice.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            ])
            listTop = notice.bottomAnchor
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: background.topAnchor, constant: 18),
            heading.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: background.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: listTop, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -12),
        ])
        contentView = background
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A big, easy to hit row: app icon, window title, app name.
final class PickerRowView: NSView {

    private let onClick: () -> Void
    private var isHovered = false { didSet { updateLook() } }

    init(row: PickerRow, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: AssistPanel.rowHeight).isActive = true

        let icon = NSImageView(image: row.icon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)!)
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = NSTextField(labelWithString: row.title)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .white
        title.lineBreakMode = .byTruncatingTail
        let subtitle = NSTextField(labelWithString: row.subtitle)
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.65)
        subtitle.lineBreakMode = .byTruncatingTail

        for view in [icon, title, subtitle] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(row.title), \(row.subtitle)")
        updateLook()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }

    private func updateLook() {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(isHovered ? 0.2 : 0.08).cgColor
    }
}

// MARK: - Closing on Esc or a click elsewhere

/// Watches for Esc and for clicks outside Tilty's panels while a pop-up is open.
/// Uses global monitors so Tilty never takes keyboard focus from the user's window.
/// Global monitors never see clicks on Tilty's own panels, so those keep working.
final class DismissMonitor {
    private var monitors: [Any] = []

    init(onDismiss: @escaping () -> Void) {
        if let click = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            DispatchQueue.main.async { onDismiss() }
        }) {
            monitors.append(click)
        }
        if let key = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            if event.keyCode == 53 { DispatchQueue.main.async { onDismiss() } }
        }) {
            monitors.append(key)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    deinit { stop() }
}

// MARK: - Running a picker session

/// Shows a picker in each empty zone and places the windows the user chooses.
@MainActor
final class SnapAssistSession {

    private struct Zone {
        let frame: CGRect      // Cocoa coordinates
        var panel: AssistPanel?
    }

    private var zones: [Zone]
    private var candidates: [WindowCandidate]
    private var monitor: DismissMonitor?
    private let onFinish: () -> Void

    /// Returns nil when there is nothing to offer.
    init?(zoneFrames: [CGRect], excluding: Set<WindowKey>, onFinish: @escaping () -> Void) {
        let found = WindowCatalog.candidates(excluding: excluding)
        guard !zoneFrames.isEmpty, !found.isEmpty else { return nil }
        zones = zoneFrames.map { Zone(frame: $0, panel: nil) }
        candidates = found
        self.onFinish = onFinish
    }

    func start() {
        monitor = DismissMonitor { [weak self] in
            MainActor.assumeIsolated { self?.finish() }
        }
        rebuildPanels()
    }

    func finish() {
        monitor?.stop()
        monitor = nil
        for zone in zones { zone.panel?.orderOut(nil) }
        zones.removeAll()
        onFinish()
    }

    private func rebuildPanels() {
        let rows = candidates.map { candidate in
            PickerRow(icon: candidate.app.icon, title: candidate.title, subtitle: candidate.app.localizedName ?? "")
        }
        for index in zones.indices {
            zones[index].panel?.orderOut(nil)
            let frame = zones[index].frame.insetBy(dx: 10, dy: 10)
            let panel = AssistPanel(frame: frame, rows: rows, showStageManagerNotice: StageManager.isOn) { [weak self] row in
                MainActor.assumeIsolated { self?.choose(row: row, zoneIndex: index) }
            }
            panel.orderFrontRegardless()
            zones[index].panel = panel
        }
    }

    private func choose(row: Int, zoneIndex: Int) {
        guard candidates.indices.contains(row), zones.indices.contains(zoneIndex),
              let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let candidate = candidates.remove(at: row)
        let zone = zones.remove(at: zoneIndex)
        zone.panel?.orderOut(nil)

        WindowMover.apply(cocoaFrame: zone.frame, to: candidate.window, appElement: candidate.appElement, primaryScreenHeight: primaryHeight)
        WindowCatalog.raise(candidate)

        if zones.isEmpty || candidates.isEmpty {
            finish()
        } else {
            rebuildPanels()
        }
    }
}
