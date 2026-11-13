import CoreGraphics
import Testing
@testable import TiltyCore

@Suite("Coordinate flip")
struct FlipTests {
    @Test func flipsAXToCocoa() {
        let ax = CGRect(x: 0, y: 25, width: 800, height: 600)
        let cocoa = Geometry.flip(ax, primaryScreenHeight: 1080)
        #expect(cocoa == CGRect(x: 0, y: 455, width: 800, height: 600))
    }

    @Test func flipIsItsOwnInverse() {
        let rect = CGRect(x: -1440, y: 1200, width: 333, height: 444)
        let twice = Geometry.flip(Geometry.flip(rect, primaryScreenHeight: 900), primaryScreenHeight: 900)
        #expect(twice == rect)
    }

    @Test func secondaryScreenAbovePrimaryHasNegativeAXY() {
        // Secondary screen sits on top of a 1080pt primary, so in Cocoa it starts at y = 1080.
        let secondaryCocoa = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        let ax = Geometry.flip(secondaryCocoa, primaryScreenHeight: 1080)
        #expect(ax.minY == -1080)
    }
}

@Suite("Target frames")
struct TargetFrameTests {
    let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)

    @Test func fillUsesWholeVisibleFrame() {
        #expect(Geometry.targetFrame(for: .fill, in: visible) == visible)
    }

    @Test func halvesSplitTheVisibleFrame() {
        let left = Geometry.targetFrame(for: .leftHalf, in: visible)
        let right = Geometry.targetFrame(for: .rightHalf, in: visible)
        #expect(left == CGRect(x: 0, y: 70, width: 720, height: 805))
        #expect(right == CGRect(x: 720, y: 70, width: 720, height: 805))
    }

    @Test func oddWidthsLeaveNoGap() {
        let odd = CGRect(x: 0, y: 0, width: 1441, height: 900)
        let left = Geometry.targetFrame(for: .leftHalf, in: odd)
        let right = Geometry.targetFrame(for: .rightHalf, in: odd)
        #expect(left.maxX == right.minX)
        #expect(left.width + right.width == 1441)
    }

    @Test func dockOnTheLeftShiftsHalves() {
        let dockLeft = CGRect(x: 80, y: 0, width: 1360, height: 875)
        let left = Geometry.targetFrame(for: .leftHalf, in: dockLeft)
        let right = Geometry.targetFrame(for: .rightHalf, in: dockLeft)
        #expect(left.minX == 80)
        #expect(right.maxX == 1440)
    }

    @Test func fractionalVisibleFramesBecomeWholePoints() {
        let fractional = CGRect(x: 0, y: 24.5, width: 1512, height: 857.5)
        let fill = Geometry.targetFrame(for: .fill, in: fractional)
        #expect(fill.minY == fill.minY.rounded())
        #expect(fill.height == fill.height.rounded())
    }
}

@Suite("Screen choice")
struct ScreenChoiceTests {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let rightOfPrimary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    let leftOfPrimary = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let abovePrimary = CGRect(x: 0, y: 900, width: 1920, height: 1080)

    @Test func emptyScreenListGivesNil() {
        #expect(Geometry.bestScreenIndex(for: .init(x: 0, y: 0, width: 10, height: 10), screens: []) == nil)
    }

    @Test func picksScreenWithLargestOverlap() {
        // Mostly on the right screen, a little on the primary.
        let window = CGRect(x: 1300, y: 100, width: 800, height: 600)
        #expect(Geometry.bestScreenIndex(for: window, screens: [primary, rightOfPrimary]) == 1)
    }

    @Test func handlesScreenToTheLeft() {
        let window = CGRect(x: -1000, y: 200, width: 600, height: 400)
        #expect(Geometry.bestScreenIndex(for: window, screens: [primary, leftOfPrimary]) == 1)
    }

    @Test func handlesScreenAbove() {
        let window = CGRect(x: 100, y: 1200, width: 600, height: 400)
        #expect(Geometry.bestScreenIndex(for: window, screens: [primary, abovePrimary]) == 1)
    }

    @Test func offscreenWindowGoesToNearestScreen() {
        let window = CGRect(x: 5000, y: 100, width: 300, height: 300)
        #expect(Geometry.bestScreenIndex(for: window, screens: [primary, rightOfPrimary]) == 1)
    }
}

@Suite("Toolbar placement")
struct ToolbarPlacementTests {
    let size = CGSize(width: 78, height: 22)
    let window = CGRect(x: 0, y: 0, width: 1000, height: 700)   // AX coordinates
    let zoom = CGRect(x: 52, y: 6, width: 14, height: 16)       // AX coordinates

    @Test func sitsRightAfterZoomButton() {
        let origin = Geometry.toolbarOrigin(
            zoomButton: zoom, window: window, toolbarSize: size,
            placement: .afterTrafficLights, primaryScreenHeight: 1080
        )
        #expect(origin.x == 66 + Geometry.Layout.gapAfterZoomButton)
        // Centered on the zoom button: AX top = 14 - 11 = 3, Cocoa y = 1080 - 3 - 22.
        #expect(origin.y == 1055)
    }

    @Test func rightEndHugsTheRightEdge() {
        let origin = Geometry.toolbarOrigin(
            zoomButton: zoom, window: window, toolbarSize: size,
            placement: .rightEnd, primaryScreenHeight: 1080
        )
        #expect(origin.x == 1000 - 78 - Geometry.Layout.rightEndInset)
        #expect(origin.y == 1055)
    }

    @Test func fallsBackWithoutZoomButton() {
        let origin = Geometry.toolbarOrigin(
            zoomButton: nil, window: window, toolbarSize: size,
            placement: .afterTrafficLights, primaryScreenHeight: 1080
        )
        #expect(origin.x == Geometry.Layout.fallbackLeftInset)
        #expect(origin.y == 1055)
    }

    @Test func worksOnScreenAbovePrimary() {
        let highWindow = CGRect(x: 200, y: -1000, width: 900, height: 600)
        let highZoom = CGRect(x: 252, y: -994, width: 14, height: 16)
        let origin = Geometry.toolbarOrigin(
            zoomButton: highZoom, window: highWindow, toolbarSize: size,
            placement: .afterTrafficLights, primaryScreenHeight: 1080
        )
        // AX top = -986 - 11 = -997, Cocoa y = 1080 + 997 - 22.
        #expect(origin.y == 2055)
        #expect(origin.x == 266 + Geometry.Layout.gapAfterZoomButton)
    }
}
