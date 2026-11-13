import AppKit
import TiltyCore

/// Level for Tilty's pop-up UI, just above the title bar toolbar.
extension NSWindow.Level {
    static let tiltyOverlay = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
}

/// The grid of layouts that drops down from the chevron.
/// Each layout tile is split into zones. Clicking a zone picks it.
final class LayoutGridPanel: NSPanel {

    static let tileSize = CGSize(width: 100, height: 64)
    static let columns = 3
    static let padding: CGFloat = 10
    static let gap: CGFloat = 8

    /// Size of the layout tiles area, without the Stage Manager notice.
    static var gridSize: CGSize {
        let rows = (SnapLayout.all.count + columns - 1) / columns
        return CGSize(
            width: padding * 2 + tileSize.width * CGFloat(columns) + gap * CGFloat(columns - 1),
            height: padding * 2 + tileSize.height * CGFloat(rows) + gap * CGFloat(rows - 1)
        )
    }

    /// - Parameters:
    ///   - showStageManagerNotice: adds a warning under the layouts when Stage Manager is on.
    init(showStageManagerNotice: Bool = false, onOpenSettings: @escaping () -> Void = {}, onPick: @escaping (SnapLayout, Int) -> Void) {
        let grid = Self.gridSize
        var notice: NSView?
        var noticeHeight: CGFloat = 0
        if showStageManagerNotice {
            let view = makeStageManagerNotice(width: grid.width - Self.padding * 2 - 4, textColor: .secondaryLabelColor, onOpenSettings: onOpenSettings)
            view.layoutSubtreeIfNeeded()
            noticeHeight = view.fittingSize.height + Self.padding + 4
            notice = view
        }
        let size = CGSize(width: grid.width, height: grid.height + noticeHeight)

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        configureOverlayPanel(self)

        let background = makeOverlayBackground(size: size, cornerRadius: 12)
        let rows = (SnapLayout.all.count + Self.columns - 1) / Self.columns
        for (index, layout) in SnapLayout.all.enumerated() {
            let column = index % Self.columns
            let row = index / Self.columns
            let x = Self.padding + CGFloat(column) * (Self.tileSize.width + Self.gap)
            // Views have a bottom-left origin, so the first row goes at the top.
            let y = noticeHeight + Self.padding + CGFloat(rows - 1 - row) * (Self.tileSize.height + Self.gap)
            let tile = LayoutTileView(layout: layout) { zone in onPick(layout, zone) }
            tile.frame = NSRect(origin: CGPoint(x: x, y: y), size: Self.tileSize)
            background.addSubview(tile)
        }
        if let notice {
            background.addSubview(notice)
            NSLayoutConstraint.activate([
                notice.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Self.padding + 2),
                notice.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -Self.padding - 2),
            ])
        }
        contentView = background
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the grid under the toolbar, kept inside the screen.
    func show(below toolbarFrame: NSRect) {
        let size = frame.size
        var origin = CGPoint(x: toolbarFrame.minX, y: toolbarFrame.minY - 6 - size.height)
        let screen = NSScreen.screens.first { $0.frame.intersects(toolbarFrame) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 6), visible.maxX - size.width - 6)
            origin.y = max(origin.y, visible.minY + 6)
        }
        setFrameOrigin(origin)
        orderFrontRegardless()
    }
}

/// One layout in the grid. Draws its zones and highlights the one under the cursor.
final class LayoutTileView: NSView {

    private let layout: SnapLayout
    private let onPick: (Int) -> Void
    private var hoveredZone: Int? { didSet { if oldValue != hoveredZone { needsDisplay = true } } }

    private let inset: CGFloat = 4
    private let zoneGap: CGFloat = 3

    init(layout: SnapLayout, onPick: @escaping (Int) -> Void) {
        self.layout = layout
        self.onPick = onPick
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Layout \(layout.id)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Top-left origin, the same as the unit zones.
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) { hoveredZone = zone(at: event) }
    override func mouseEntered(with event: NSEvent) { hoveredZone = zone(at: event) }
    override func mouseExited(with event: NSEvent) { hoveredZone = nil }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if let index = zone(at: event) {
            onPick(index)
        }
    }

    private func zone(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return zoneRects().firstIndex { $0.contains(point) }
    }

    /// Zone rectangles in view coordinates, with small gaps between them.
    private func zoneRects() -> [NSRect] {
        let area = bounds.insetBy(dx: inset, dy: inset)
        return layout.zones.map { zone in
            NSRect(
                x: area.minX + area.width * zone.x,
                y: area.minY + area.height * zone.y,
                width: area.width * zone.width,
                height: area.height * zone.height
            ).insetBy(dx: zoneGap / 2, dy: zoneGap / 2)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            NSColor.labelColor.withAlphaComponent(hoveredZone == nil ? 0.06 : 0.1).setFill()
            frame.fill()
            NSColor.labelColor.withAlphaComponent(0.12).setStroke()
            frame.lineWidth = 1
            frame.stroke()

            for (index, rect) in zoneRects().enumerated() {
                let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                if index == hoveredZone {
                    NSColor.controlAccentColor.setFill()
                } else {
                    NSColor.labelColor.withAlphaComponent(0.18).setFill()
                }
                path.fill()
            }
        }
    }
}

// MARK: - Shared panel setup

func configureOverlayPanel(_ panel: NSPanel) {
    panel.isFloatingPanel = true
    panel.level = .tiltyOverlay
    panel.hidesOnDeactivate = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isMovable = false
    panel.isReleasedWhenClosed = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.animationBehavior = .none
    panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenNone]
}

func makeOverlayBackground(size: CGSize, cornerRadius: CGFloat, material: NSVisualEffectView.Material = .popover) -> NSVisualEffectView {
    let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
    background.material = material
    background.blendingMode = .behindWindow
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = cornerRadius
    background.layer?.masksToBounds = true
    background.layer?.borderWidth = 0.5
    background.layer?.borderColor = NSColor.black.withAlphaComponent(0.15).cgColor
    return background
}
