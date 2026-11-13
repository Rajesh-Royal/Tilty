import AppKit

/// The About panel and the links in it.
enum About {
    static let website = URL(string: "https://rajesh-royal.github.io/Tilty/")!
    static let repository = URL(string: "https://github.com/Rajesh-Royal/Tilty")!
    static let releases = URL(string: "https://github.com/Rajesh-Royal/Tilty/releases")!
    static let issues = URL(string: "https://github.com/Rajesh-Royal/Tilty/issues")!
    static let license = URL(string: "https://github.com/Rajesh-Royal/Tilty/blob/main/LICENSE.md")!

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// Shows the standard macOS About panel with Tilty's links.
    /// Tilty has no Dock icon, so it activates first to bring the panel to the front.
    @MainActor
    static func show() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Tilty",
            .applicationVersion: version,
            .version: build,
            .credits: credits(),
        ])
    }

    @MainActor
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private static func credits() -> NSAttributedString {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        center.paragraphSpacing = 3

        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: center,
        ]
        let muted: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: center,
        ]

        let text = NSMutableAttributedString()
        func add(_ string: String, _ attributes: [NSAttributedString.Key: Any]) {
            text.append(NSAttributedString(string: string, attributes: attributes))
        }
        func link(_ title: String, _ url: URL) {
            var attributes = body
            attributes[.link] = url
            text.append(NSAttributedString(string: title, attributes: attributes))
        }

        add("Big one-click buttons for tiling windows.\nMade for one laptop and one trackpad.\n\n", body)
        link("Website", website)
        add("     ", body)
        link("GitHub", repository)
        add("\n", body)
        link("Release notes", releases)
        add("     ", body)
        link("Report a problem", issues)
        add("\n\nFree for personal and noncommercial use.\n", muted)
        var licenseLink = muted
        licenseLink[.link] = license
        text.append(NSAttributedString(string: "PolyForm Noncommercial License", attributes: licenseLink))
        return text
    }
}
