import AppKit

/// The Tilty menu bar icon: one tall tile on the left, two stacked tiles on the right.
/// Drawn in code because no SF Symbol has this exact layout.
enum StatusIcon {

    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let unit = rect.width / 18
            let line = 1.3 * unit
            let radius = 1.3 * unit
            let inset = line / 2

            // Tile frames on an 18pt grid, top-left origin.
            let top: CGFloat = 2, bottom: CGFloat = 16, gap: CGFloat = 2
            let left = CGRect(x: 2, y: top, width: 6, height: bottom - top)
            let rightX = left.maxX + gap
            let rightWidth = 16 - rightX
            let halfHeight = (bottom - top - gap) / 2
            let rightTop = CGRect(x: rightX, y: top, width: rightWidth, height: halfHeight)
            let rightBottom = CGRect(x: rightX, y: top + halfHeight + gap, width: rightWidth, height: halfHeight)

            NSColor.black.setStroke()
            for tile in [left, rightTop, rightBottom] {
                let scaled = CGRect(x: tile.minX * unit, y: tile.minY * unit, width: tile.width * unit, height: tile.height * unit)
                let path = NSBezierPath(roundedRect: scaled.insetBy(dx: inset, dy: inset), xRadius: radius, yRadius: radius)
                path.lineWidth = line
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tilty"
        return image
    }
}
