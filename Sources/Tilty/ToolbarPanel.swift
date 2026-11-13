import AppKit
import TiltyCore

/// The small floating toolbar that sits in the active window's title bar.
///
/// It is a non-activating panel, so clicking it never steals focus
/// from the window it is about to move.
final class ToolbarPanel: NSPanel {

    static let buttonSize = CGSize(width: 32, height: 22)
    static let chevronWidth: CGFloat = 22
    static let inset: CGFloat = 2
    static let spacing: CGFloat = 2
    /// Gap on each side of the thin line before the chevron.
    static let dividerGap: CGFloat = 3

    static var panelSize: CGSize {
        let count = CGFloat(TileAction.allCases.count)
        let actions = buttonSize.width * count + spacing * (count - 1)
        let chevron = dividerGap * 2 + 1 + chevronWidth
        return CGSize(width: inset * 2 + actions + chevron, height: inset * 2 + buttonSize.height)
    }

    private let chevron: ToolbarButton

    /// - Parameters:
    ///   - onAction: a quick button was clicked.
    ///   - onLayouts: the chevron was clicked. Gets the chevron's frame on screen.
    init(onAction: @escaping (TileAction) -> Void, onLayouts: @escaping (NSRect) -> Void) {
        var chevronFrameProvider: (() -> NSRect)?
        chevron = ToolbarButton(symbolName: "chevron.down", title: "More Layouts", pointSize: 11, weight: .bold) {
            onLayouts(chevronFrameProvider?() ?? .zero)
        }

        super.init(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenNone]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 7
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor

        var x = Self.inset
        for action in TileAction.allCases {
            let button = ToolbarButton(symbolName: action.symbolName, title: action.title) { onAction(action) }
            button.frame = NSRect(x: x, y: Self.inset, width: Self.buttonSize.width, height: Self.buttonSize.height)
            background.addSubview(button)
            x += Self.buttonSize.width + Self.spacing
        }
        x += Self.dividerGap - Self.spacing

        let divider = NSBox(frame: NSRect(x: x, y: Self.inset + 4, width: 1, height: Self.buttonSize.height - 8))
        divider.boxType = .custom
        divider.borderWidth = 0
        divider.fillColor = NSColor.separatorColor
        background.addSubview(divider)
        x += 1 + Self.dividerGap

        chevron.frame = NSRect(x: x, y: Self.inset, width: Self.chevronWidth, height: Self.buttonSize.height)
        background.addSubview(chevron)

        contentView = background

        chevronFrameProvider = { [weak self] in
            guard let self, let window = self.chevron.window else { return .zero }
            return window.convertToScreen(self.chevron.convert(self.chevron.bounds, to: nil))
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Keeps the chevron highlighted while the layout grid is open.
    func setLayoutsOpen(_ open: Bool) {
        chevron.isLatched = open
    }

    /// Called on every refresh, so it only talks to the window server when something changed.
    func show(at origin: CGPoint) {
        if frame.origin != origin {
            setFrameOrigin(origin)
        }
        if !isVisible {
            orderFrontRegardless()
        }
    }

    func hide() {
        guard isVisible else { return }
        orderOut(nil)
        // The panel can vanish under the cursor (after a click), so no exit event arrives.
        // Clear the highlight so the buttons look normal when the panel comes back.
        contentView?.subviews.compactMap { $0 as? ToolbarButton }.forEach { $0.resetHighlight() }
    }
}

/// One icon button with a hover highlight.
/// Responds to the first click even though Tilty is never the active app.
final class ToolbarButton: NSView {

    private let onClick: () -> Void
    private let imageView = NSImageView()
    // Each look change commits a layer update, so skip it when nothing changed.
    private var isHovered = false { didSet { if oldValue != isHovered { updateLook() } } }
    private var isPressed = false { didSet { if oldValue != isPressed { updateLook() } } }
    /// Stays highlighted, for a button whose menu is open.
    var isLatched = false { didSet { if oldValue != isLatched { updateLook() } } }

    init(symbolName: String, title: String, pointSize: CGFloat = 14, weight: NSFont.Weight = .medium, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 5

        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(config)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        toolTip = title
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
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; isPressed = false }
    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        let point = convert(event.locationInWindow, from: nil)
        if wasPressed && bounds.contains(point) {
            onClick()
        }
    }

    func resetHighlight() {
        isHovered = false
        isPressed = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLook()
    }

    private func updateLook() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let highlight: CGFloat = isPressed ? 0.22 : ((isHovered || isLatched) ? 0.12 : 0)
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(highlight).cgColor
            imageView.contentTintColor = (isHovered || isLatched) ? .labelColor : .secondaryLabelColor
        }
    }
}

extension TileAction {
    var title: String {
        switch self {
        case .fill: return "Fill"
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        }
    }

    var symbolName: String {
        switch self {
        case .fill: return "rectangle.inset.filled"
        case .leftHalf: return "rectangle.lefthalf.inset.filled"
        case .rightHalf: return "rectangle.righthalf.inset.filled"
        }
    }
}
