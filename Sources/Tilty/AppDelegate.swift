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

    private var previewPanels: [NSPanel] = []

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
        let panel = ToolbarPanel(
            onAction: { NSLog("Tilty preview: clicked \($0.rawValue)") },
            onLayouts: { _ in NSLog("Tilty preview: clicked layouts") }
        )
        let origin = Geometry.toolbarOrigin(
            zoomButton: zoom, window: bounds, toolbarSize: ToolbarPanel.panelSize,
            placement: .afterTrafficLights, primaryScreenHeight: primaryHeight
        )
        panel.show(at: origin)
        previewPanels.append(panel)

        // --preview-layouts also opens the layout grid and a sample window picker.
        guard CommandLine.arguments.contains("--preview-layouts") else { return }
        panel.setLayoutsOpen(true)
        let notice = CommandLine.arguments.contains("--preview-stage-manager")
        let grid = LayoutGridPanel(showStageManagerNotice: notice) { layout, zone in NSLog("Tilty preview: picked \(layout.id) zone \(zone)") }
        grid.show(below: panel.frame)
        previewPanels.append(grid)

        if let screen = NSScreen.main {
            let zone = Geometry.frame(forZone: SnapLayout.halves.zones[1], in: screen.visibleFrame)
            let rows = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .prefix(5)
                .map { PickerRow(icon: $0.icon, title: $0.localizedName ?? "App", subtitle: "Sample window") }
            let picker = AssistPanel(frame: zone.insetBy(dx: 10, dy: 10), rows: Array(rows), showStageManagerNotice: notice) { NSLog("Tilty preview: chose row \($0)") }
            picker.orderFrontRegardless()
            previewPanels.append(picker)
        }
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
        guard let button = statusItem?.button else { return }
        if Accessibility.isTrusted {
            button.image = StatusIcon.make()
            // Paused shows the same icon, dimmed.
            button.appearsDisabled = preferences.isPaused
        } else {
            let warning = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Tilty needs Accessibility access")
            warning?.isTemplate = true
            button.image = warning
            button.appearsDisabled = false
        }
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

        if trusted, StageManager.isOn {
            let stage = item("Stage Manager Is On, Turn It Off…", #selector(openStageManagerSettings))
            stage.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            stage.toolTip = StageManager.warning
            menu.addItem(stage)
        }

        let suggest = item("Suggest Windows After Left or Right", #selector(toggleSuggest))
        suggest.state = preferences.suggestAfterHalves ? .on : .off
        suggest.isEnabled = trusted
        menu.addItem(suggest)

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

    @objc private func openStageManagerSettings() {
        StageManager.openSettings()
    }

    @objc private func toggleSuggest() {
        preferences.suggestAfterHalves.toggle()
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
