import CoreGraphics

/// A rectangle in unit space (0 to 1) with a top-left origin, like reading a screen.
public struct UnitRect: Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// A screen layout from the chevron grid, split into zones.
public struct SnapLayout: Hashable, Sendable, CustomStringConvertible {
    public let id: String
    public let zones: [UnitRect]

    public var description: String { id }

    public init(id: String, zones: [UnitRect]) {
        self.id = id
        self.zones = zones
    }

    /// Zones still empty after the window went into `pickedIndex`.
    public func remainingZones(after pickedIndex: Int) -> [UnitRect] {
        zones.enumerated().filter { $0.offset != pickedIndex }.map(\.element)
    }

    /// The empty side after a quick Left or Right click. Fill leaves nothing.
    public static func leftover(after action: TileAction) -> [UnitRect] {
        switch action {
        case .fill: return []
        case .leftHalf: return [halves.zones[1]]
        case .rightHalf: return [halves.zones[0]]
        }
    }

    // MARK: - The layouts, in grid order

    public static let halves = SnapLayout(id: "halves", zones: [
        UnitRect(x: 0, y: 0, width: 1.0 / 2, height: 1),
        UnitRect(x: 1.0 / 2, y: 0, width: 1.0 / 2, height: 1),
    ])

    public static let twoThirdsOneThird = SnapLayout(id: "twoThirdsOneThird", zones: [
        UnitRect(x: 0, y: 0, width: 2.0 / 3, height: 1),
        UnitRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1),
    ])

    public static let oneThirdTwoThirds = SnapLayout(id: "oneThirdTwoThirds", zones: [
        UnitRect(x: 0, y: 0, width: 1.0 / 3, height: 1),
        UnitRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1),
    ])

    public static let thirds = SnapLayout(id: "thirds", zones: [
        UnitRect(x: 0, y: 0, width: 1.0 / 3, height: 1),
        UnitRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1),
        UnitRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1),
    ])

    /// One tall window on the left, two stacked on the right. Same shape as the Tilty icon.
    public static let mainAndStack = SnapLayout(id: "mainAndStack", zones: [
        UnitRect(x: 0, y: 0, width: 1.0 / 2, height: 1),
        UnitRect(x: 1.0 / 2, y: 0, width: 1.0 / 2, height: 1.0 / 2),
        UnitRect(x: 1.0 / 2, y: 1.0 / 2, width: 1.0 / 2, height: 1.0 / 2),
    ])

    public static let quarters = SnapLayout(id: "quarters", zones: [
        UnitRect(x: 0, y: 0, width: 1.0 / 2, height: 1.0 / 2),
        UnitRect(x: 1.0 / 2, y: 0, width: 1.0 / 2, height: 1.0 / 2),
        UnitRect(x: 0, y: 1.0 / 2, width: 1.0 / 2, height: 1.0 / 2),
        UnitRect(x: 1.0 / 2, y: 1.0 / 2, width: 1.0 / 2, height: 1.0 / 2),
    ])

    public static let all: [SnapLayout] = [
        halves, twoThirdsOneThird, oneThirdTwoThirds, thirds, mainAndStack, quarters,
    ]
}

extension Geometry {
    /// The frame for a layout zone on a screen, in Cocoa coordinates.
    ///
    /// Each edge is rounded on its own, from the unit position, so two zones
    /// that share an edge always land on the exact same point. No gaps, no overlaps.
    public static func frame(forZone zone: UnitRect, in visibleFrame: CGRect) -> CGRect {
        let v = visibleFrame.integral
        func xEdge(_ unit: Double) -> CGFloat { (v.minX + v.width * unit).rounded() }
        // Unit y grows down from the top, Cocoa y grows up from the bottom.
        func yEdge(_ unit: Double) -> CGFloat { (v.maxY - v.height * unit).rounded() }

        let left = xEdge(zone.x)
        let right = xEdge(zone.x + zone.width)
        let top = yEdge(zone.y)
        let bottom = yEdge(zone.y + zone.height)
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }
}
