import CoreGraphics

/// The window moves Tilty offers.
public enum TileAction: String, CaseIterable, Sendable {
    case fill
    case leftHalf
    case rightHalf
}

/// Where the toolbar sits inside a window's title bar.
public enum ToolbarPlacement: String, CaseIterable, Sendable {
    /// Just to the right of the green zoom button.
    case afterTrafficLights
    /// Near the right edge of the title bar.
    case rightEnd
}

/// Coordinate math shared by the app.
///
/// Two coordinate systems are in play:
/// - Cocoa (NSScreen, NSWindow): origin at the bottom left of the primary screen, y grows up.
/// - Accessibility (AXUIElement): origin at the top left of the primary screen, y grows down.
///
/// The primary screen is always `NSScreen.screens[0]`, never `NSScreen.main`.
public enum Geometry {

    /// Converts a rect between Cocoa and Accessibility coordinates.
    /// The flip is its own inverse, so the same function works both ways.
    public static func flip(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenHeight - rect.origin.y - rect.size.height,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    /// The frame a window should get for an action, in the same coordinates as `visibleFrame`.
    /// `visibleFrame` is the usable screen area (no menu bar, no Dock), in Cocoa coordinates.
    public static func targetFrame(for action: TileAction, in visibleFrame: CGRect) -> CGRect {
        let v = visibleFrame.integral
        let leftWidth = (v.width / 2).rounded(.down)
        switch action {
        case .fill:
            return v
        case .leftHalf:
            return CGRect(x: v.minX, y: v.minY, width: leftWidth, height: v.height)
        case .rightHalf:
            return CGRect(x: v.minX + leftWidth, y: v.minY, width: v.width - leftWidth, height: v.height)
        }
    }

    /// Picks the screen a window belongs to.
    /// Uses the largest overlap first, then the screen nearest to the window's center.
    /// - Parameters:
    ///   - window: window frame in Cocoa coordinates.
    ///   - screens: screen frames in Cocoa coordinates.
    /// - Returns: index into `screens`, or nil when the list is empty.
    public static func bestScreenIndex(for window: CGRect, screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }

        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, screen) in screens.enumerated() {
            let overlap = screen.intersection(window)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        if let bestIndex { return bestIndex }

        let center = CGPoint(x: window.midX, y: window.midY)
        return screens.indices.min { a, b in
            distanceSquared(from: center, to: screens[a]) < distanceSquared(from: center, to: screens[b])
        }
    }

    /// Where the toolbar's origin goes, in Cocoa coordinates.
    /// - Parameters:
    ///   - zoomButton: frame of the green button in AX coordinates, if the app exposes it.
    ///   - window: window frame in AX coordinates.
    ///   - toolbarSize: size of the toolbar panel.
    ///   - placement: which side of the title bar to use.
    ///   - primaryScreenHeight: height of `NSScreen.screens[0]`.
    public static func toolbarOrigin(
        zoomButton: CGRect?,
        window: CGRect,
        toolbarSize: CGSize,
        placement: ToolbarPlacement,
        primaryScreenHeight: CGFloat
    ) -> CGPoint {
        // Vertical center of the title bar row, in AX coordinates.
        let centerY: CGFloat
        if let zoomButton, zoomButton.height > 0 {
            centerY = zoomButton.midY
        } else {
            centerY = window.minY + Layout.fallbackTitleBarCenter
        }

        let x: CGFloat
        switch placement {
        case .afterTrafficLights:
            if let zoomButton, zoomButton.width > 0 {
                x = zoomButton.maxX + Layout.gapAfterZoomButton
            } else {
                x = window.minX + Layout.fallbackLeftInset
            }
        case .rightEnd:
            x = window.maxX - toolbarSize.width - Layout.rightEndInset
        }

        let axRect = CGRect(
            x: x.rounded(),
            y: (centerY - toolbarSize.height / 2).rounded(),
            width: toolbarSize.width,
            height: toolbarSize.height
        )
        return flip(axRect, primaryScreenHeight: primaryScreenHeight).origin
    }

    /// True when two frames match within a small tolerance.
    /// Apps often round sizes, so exact equality is too strict.
    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }

    private static func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    /// Spacing constants for toolbar placement.
    public enum Layout {
        public static let gapAfterZoomButton: CGFloat = 10
        /// Used when an app does not expose its zoom button.
        public static let fallbackLeftInset: CGFloat = 78
        /// Standard title bars are 28pt tall, so the row center sits 14pt down.
        public static let fallbackTitleBarCenter: CGFloat = 14
        /// Leaves room for the tab search button at the right of Chromium tab strips.
        public static let rightEndInset: CGFloat = 44
    }
}
