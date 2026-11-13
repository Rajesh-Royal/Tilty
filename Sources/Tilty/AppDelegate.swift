import AppKit
import ServiceManagement
import TiltyCore

/// Owns the menu bar item and starts Tilty once Accessibility access is granted.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let preferences = Preferences()
    private lazy var controller = TiltyController(preferences: preferences)
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?

    private var previewPanel: ToolbarPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        if CommandLine.arguments.contains("--preview") {
            showPreview()
            return
        }

        if Accessibility.isTrusted {
            controller.start()
        } else {
            Accessibility.requestTrust()
            waitForPermission()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    // MARK: - Preview

    /// Debug aid: draws the toolbar on the frontmost window without Accessibility access.
    /// Uses the window list for the frame and a typical zoom button spot.
    private func showPreview() {
        guard let primaryHeight = NSScreen.screens.first?.frame.height,
              let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let info = list.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == frontPID && ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
            NSLog("Tilty preview: no frontmost window found")
            return
        }
        let zoom = CGRect(x: bounds.minX + 48, y: bounds.minY + 6, width: 16, height: 16)
        let panel = ToolbarPanel { NSLog("Tilty preview: clicked \($0.rawValue)") }
        let origin = Geometry.toolbarOrigin(
            zoomButton: zoom, window: bounds, toolbarSize: ToolbarPanel.panelSize,
            placement: .afterTrafficLights, primaryScreenHeight: primaryHeight
        )
        panel.show(at: origin)
        previewPanel = panel
    }

    // MARK: - Permission

    private func waitForPermission() {
        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard Accessibility.isTrusted else { return }
                timer.invalidate()
                self?.permissionTimer = nil
                self?.controller.start()
                self?.updateStatusIcon()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
        updateStatusIcon()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let name: String
        if !Accessibility.isTrusted {
            name = "exclamationmark.triangle"
        } else if preferences.isPaused {
            name = "rectangle.split.2x1.slash"
        } else {
            name = "rectangle.split.2x1"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Tilty")
            ?? NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Tilty")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let trusted = Accessibility.isTrusted
        let status: String
        if !trusted {
            status = "Needs Accessibility access"
        } else if preferences.isPaused {
            status = "Paused"
        } else {
            status = "Running"
        }
        menu.addItem(disabled("Tilty: \(status)"))
        menu.addItem(.separator())

        if !trusted {
            menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }

        let pause = item("Pause Tilty", #selector(togglePause))
        pause.state = preferences.isPaused ? .on : .off
        pause.isEnabled = trusted
        menu.addItem(pause)

        if trusted, let app = controller.tracker.currentApp, let bundleID = app.bundleIdentifier {
            let name = app.localizedName ?? bundleID
            let current = preferences.placement(forBundleID: bundleID)
            let submenu = NSMenu()
            for placement in ToolbarPlacement.allCases {
                let choice = item(placement.menuTitle, #selector(choosePlacement(_:)))
                choice.representedObject = PlacementChoice(bundleID: bundleID, placement: placement)
                choice.state = placement == current ? .on : .off
                submenu.addItem(choice)
            }
            let parent = NSMenuItem(title: "Icons in \(name)", action: nil, keyEquivalent: "")
            parent.submenu = submenu
            menu.addItem(parent)
        }

        menu.addItem(.separator())

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = item("Quit Tilty", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Menu actions

    @objc private func openAccessibilitySettings() {
        Accessibility.requestTrust()
        Accessibility.openSettings()
    }

    @objc private func togglePause() {
        preferences.isPaused.toggle()
        controller.refresh()
        updateStatusIcon()
    }

    @objc private func choosePlacement(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? PlacementChoice else { return }
        preferences.setPlacement(choice.placement, forBundleID: choice.bundleID)
        controller.refresh()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Carried by a placement menu item.
private final class PlacementChoice: NSObject {
    let bundleID: String
    let placement: ToolbarPlacement

    init(bundleID: String, placement: ToolbarPlacement) {
        self.bundleID = bundleID
        self.placement = placement
    }
}

private extension ToolbarPlacement {
    var menuTitle: String {
        switch self {
        case .afterTrafficLights: return "After the Traffic Lights"
        case .rightEnd: return "At the Right End"
        }
    }
}
