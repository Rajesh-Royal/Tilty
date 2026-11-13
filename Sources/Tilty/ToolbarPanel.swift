import AppKit
import TiltyCore

/// The small floating toolbar that sits in the active window's title bar.
///
/// It is a non-activating panel, so clicking it never steals focus
/// from the window it is about to move.
final class ToolbarPanel: NSPanel {

    static let buttonSize = CGSize(width: 32, height: 22)
    static let inset: CGFloat = 2
    static let spacing: CGFloat = 2

    static var panelSize: CGSize {
        let count = CGFloat(TileAction.allCases.count)
        return CGSize(
            width: inset * 2 + buttonSize.width * count + spacing * (count - 1),
            height: inset * 2 + buttonSize.height
        )
    }

    init(onAction: @escaping (TileAction) -> Void) {
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
            let button = TileButton(action: action, onClick: onAction)
            button.frame = NSRect(x: x, y: Self.inset, width: Self.buttonSize.width, height: Self.buttonSize.height)
            background.addSubview(button)
            x += Self.buttonSize.width + Self.spacing
        }

        contentView = background
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(at origin: CGPoint) {
        setFrameOrigin(origin)
        if !isVisible {
            orderFrontRegardless()
        }
    }

    func hide() {
        if isVisible {
            orderOut(nil)
        }
    }
}

/// One icon button with a hover highlight.
/// Responds to the first click even though Tilty is never the active app.
final class TileButton: NSView {

    private let action: TileAction
    private let onClick: (TileAction) -> Void
    private let imageView = NSImageView()
    private var isHovered = false { didSet { updateLook() } }
    private var isPressed = false { didSet { updateLook() } }

    init(action: TileAction, onClick: @escaping (TileAction) -> Void) {
        self.action = action
        self.onClick = onClick
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 5

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        imageView.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: action.title)?
            .withSymbolConfiguration(config)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        toolTip = action.title
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(action.title)
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
            onClick(action)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLook()
    }

    private func updateLook() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let highlight: CGFloat = isPressed ? 0.22 : (isHovered ? 0.12 : 0)
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(highlight).cgColor
            imageView.contentTintColor = isHovered ? .labelColor : .secondaryLabelColor
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
