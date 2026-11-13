import AppKit
import ApplicationServices
import os

/// The focused window of the frontmost app, ready for Tilty to act on.
struct FocusedWindow {
    let app: NSRunningApplication
    let appElement: AXUIElement
    let window: AXUIElement
    /// Window frame in Accessibility coordinates.
    let frame: CGRect
    /// Green button frame in Accessibility coordinates, when the app exposes it.
    let zoomButton: CGRect?

    var key: WindowKey { WindowKey(element: window) }
}

/// Follows the frontmost app and its focused window, and calls `onChange`
/// whenever something that affects the toolbar might have changed.
@MainActor
final class WindowTracker {

    var onChange: (() -> Void)?

    private(set) var currentApp: NSRunningApplication?
    private var appElement: AXUIElement?
    private var observer: AXObserver?
    private var watchedWindow: AXUIElement?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var appTokens: [NSObjectProtocol] = []

    private let log = Logger(subsystem: "app.tilty.Tilty", category: "tracker")

    /// Notifications watched on the app element.
    private static let appNotifications: [String] = [
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXWindowCreatedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]

    /// Notifications watched on the focused window itself.
    /// Some apps only send moves and resizes to the window, not the app.
    private static let windowNotifications: [String] = [
        kAXMovedNotification,
        kAXResizedNotification,
        kAXUIElementDestroyedNotification,
    ]

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.attach(to: app) }
        })
        workspaceTokens.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.attach(to: NSWorkspace.shared.frontmostApplication) }
        })
        appTokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        })

        attach(to: NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        workspaceTokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        appTokens.forEach(NotificationCenter.default.removeObserver)
        workspaceTokens.removeAll()
        appTokens.removeAll()
        detach()
    }

    /// Re-attaches if the observer could not be created earlier,
    /// for example while an app was still launching.
    func ensureAttached() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != currentApp?.processIdentifier || (currentApp != nil && observer == nil) {
            attach(to: frontmost)
        }
    }

    /// Reads the focused window fresh from the app.
    /// Returns nil when there is nothing Tilty should decorate.
    func focusedWindow() -> FocusedWindow? {
        guard let app = currentApp, let appElement, !app.isHidden else { return nil }

        guard let window = appElement.element(kAXFocusedWindowAttribute)
            ?? appElement.element(kAXMainWindowAttribute) else { return nil }

        // Only regular document windows. Dialogs, sheets, palettes and popovers are skipped.
        guard window.string(kAXRoleAttribute) == kAXWindowRole,
              window.string(kAXSubroleAttribute) == kAXStandardWindowSubrole else { return nil }
        if window.bool(kAXMinimizedAttribute) == true { return nil }
        if window.bool(AXName.fullScreen) == true { return nil }

        guard let frame = window.frame, frame.width >= 160, frame.height >= 60 else { return nil }

        if !CFEqualOptional(window, watchedWindow) {
            watch(window: window)
        }

        let zoomButton = window.element(kAXZoomButtonAttribute)?.frame
        return FocusedWindow(app: app, appElement: appElement, window: window, frame: frame, zoomButton: zoomButton)
    }

    // MARK: - Attaching

    private func attach(to app: NSRunningApplication?) {
        detach()

        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            currentApp = nil
            onChange?()
            return
        }

        currentApp = app
        let pid = app.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        // Never let a busy app freeze Tilty for long.
        AXUIElementSetMessagingTimeout(element, 0.25)
        appElement = element

        var newObserver: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            MainActor.assumeIsolated { tracker.handle(notification: name) }
        }

        guard AXObserverCreate(pid, callback, &newObserver) == .success, let newObserver else {
            log.debug("Could not create observer for pid \(pid)")
            onChange?()
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.appNotifications {
            AXObserverAddNotification(newObserver, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
        observer = newObserver

        onChange?()
    }

    private func detach() {
        if let observer {
            unwatchWindow()
            if let appElement {
                for name in Self.appNotifications {
                    AXObserverRemoveNotification(observer, appElement, name as CFString)
                }
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        appElement = nil
        watchedWindow = nil
    }

    private func watch(window: AXUIElement) {
        unwatchWindow()
        guard let observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.windowNotifications {
            AXObserverAddNotification(observer, window, name as CFString, refcon)
        }
        watchedWindow = window
    }

    private func unwatchWindow() {
        guard let observer, let watchedWindow else { return }
        for name in Self.windowNotifications {
            AXObserverRemoveNotification(observer, watchedWindow, name as CFString)
        }
        self.watchedWindow = nil
    }

    private func handle(notification: String) {
        if notification == kAXUIElementDestroyedNotification {
            watchedWindow = nil
        }
        onChange?()
    }
}

private func CFEqualOptional(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (a?, b?): return CFEqual(a, b)
    default: return false
    }
}
