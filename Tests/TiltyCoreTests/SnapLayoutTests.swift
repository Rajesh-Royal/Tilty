import CoreGraphics
import Testing
@testable import TiltyCore

@Suite("Snap layouts")
struct SnapLayoutTests {
    /// Odd sizes and a non-zero origin catch rounding gaps.
    let visible = CGRect(x: 80, y: 70, width: 1441, height: 875)

    @Test func hasTheSixApprovedLayouts() {
        #expect(SnapLayout.all.map(\.id) == [
            "halves", "twoThirdsOneThird", "oneThirdTwoThirds", "thirds", "mainAndStack", "quarters",
        ])
        #expect(SnapLayout.all.map(\.zones.count) == [2, 2, 2, 3, 3, 4])
    }

    @Test(arguments: SnapLayout.all)
    func zonesCoverTheScreenExactly(layout: SnapLayout) {
        let frames = layout.zones.map { Geometry.frame(forZone: $0, in: visible) }

        // Every zone stays inside the visible frame.
        for frame in frames {
            #expect(visible.contains(frame))
        }

        // Areas add up to the whole screen, so there are no gaps.
        let area = frames.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
        #expect(area == visible.width * visible.height)

        // No two zones overlap.
        for i in frames.indices {
            for j in frames.indices where j > i {
                let overlap = frames[i].intersection(frames[j])
                #expect(overlap.isNull || overlap.width == 0 || overlap.height == 0)
            }
        }

        // Every edge lands on whole points.
        for frame in frames {
            #expect(frame == frame.integral)
        }
    }

    @Test func halvesShareTheMiddleEdge() {
        let frames = SnapLayout.halves.zones.map { Geometry.frame(forZone: $0, in: visible) }
        #expect(frames[0].maxX == frames[1].minX)
        #expect(frames[0].minX == visible.minX)
        #expect(frames[1].maxX == visible.maxX)
    }

    @Test func zonesUseTopLeftOrigin() {
        // In the stacked layout, zone 1 is the top right and zone 2 is the bottom right.
        // Cocoa y grows up, so the top zone has the larger y.
        let frames = SnapLayout.mainAndStack.zones.map { Geometry.frame(forZone: $0, in: visible) }
        #expect(frames[1].minY > frames[2].minY)
        #expect(frames[1].maxY == visible.maxY)
        #expect(frames[2].minY == visible.minY)
        #expect(frames[1].minY == frames[2].maxY)
        #expect(frames[0].height == visible.height)
    }

    @Test func quartersMeetInTheMiddle() {
        let f = SnapLayout.quarters.zones.map { Geometry.frame(forZone: $0, in: visible) }
        // Order: top left, top right, bottom left, bottom right.
        #expect(f[0].maxX == f[1].minX)
        #expect(f[2].maxX == f[3].minX)
        #expect(f[0].minY == f[2].maxY)
        #expect(f[1].minY == f[3].maxY)
    }

    @Test func remainingZonesSkipThePickedOne() {
        let rest = SnapLayout.thirds.remainingZones(after: 1)
        #expect(rest == [SnapLayout.thirds.zones[0], SnapLayout.thirds.zones[2]])
    }

    @Test func leftoverZoneForQuickActions() {
        #expect(SnapLayout.leftover(after: .leftHalf) == [SnapLayout.halves.zones[1]])
        #expect(SnapLayout.leftover(after: .rightHalf) == [SnapLayout.halves.zones[0]])
        #expect(SnapLayout.leftover(after: .fill).isEmpty)
    }
}
