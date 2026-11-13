import AppKit

/// Stage Manager shows one app at a time, so it hides windows Tilty lays out side by side.
/// Tilty reads its switch to warn people who don't know it's on.
enum StageManager {

    private static let domain = "com.apple.WindowManager" as CFString

    static var isOn: Bool {
        // Read fresh, since people turn it on and off from Control Center.
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesGetAppBooleanValue("GloballyEnabled" as CFString, domain, nil)
    }

    static let warning = "Stage Manager is on, so only one app shows at a time. Other windows will hide."

    /// Opens System Settings at Desktop & Dock, where Stage Manager is switched off.
    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Desktop-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.dock",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}

/// A clickable text link that works in Tilty's non-activating panels.
final class LinkButton: NSView {
    private let label: NSTextField
    private let onClick: () -> Void
    private var isHovered = false { didSet { updateLook() } }

    init(title: String, onClick: @escaping () -> Void) {
        label = NSTextField(labelWithString: title)
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
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
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLook()
    }

    private func updateLook() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            label.textColor = .controlAccentColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(isHovered ? 0.22 : 0.12).cgColor
        }
    }
}

/// The warning strip: an icon, the message and a button to open the settings.
func makeStageManagerNotice(width: CGFloat, textColor: NSColor, onOpenSettings: @escaping () -> Void) -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)!)
    icon.contentTintColor = .systemOrange
    let text = NSTextField(wrappingLabelWithString: StageManager.warning)
    text.font = .systemFont(ofSize: 12)
    text.textColor = textColor
    text.preferredMaxLayoutWidth = width - 26
    let button = LinkButton(title: "Turn Off in Settings", onClick: onOpenSettings)

    for view in [icon, text, button] as [NSView] {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
    }
    NSLayoutConstraint.activate([
        container.widthAnchor.constraint(equalToConstant: width),
        icon.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
        icon.widthAnchor.constraint(equalToConstant: 16),
        icon.heightAnchor.constraint(equalToConstant: 15),
        text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
        text.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        text.topAnchor.constraint(equalTo: container.topAnchor),
        button.leadingAnchor.constraint(equalTo: text.leadingAnchor),
        button.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 8),
        button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    return container
}
