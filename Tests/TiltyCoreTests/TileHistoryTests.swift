import CoreGraphics
import Testing
@testable import TiltyCore

@Suite("Tile history")
struct TileHistoryTests {
    let original = CGRect(x: 200, y: 200, width: 700, height: 500)
    let fill = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let left = CGRect(x: 0, y: 0, width: 720, height: 875)

    @Test func firstClickAppliesTarget() {
        var history = TileHistory<Int>()
        let frame = history.resolve(key: 1, action: .fill, current: original, target: fill)
        #expect(frame == fill)
        #expect(history.hasOriginal(for: 1))
    }

    @Test func sameActionTwiceRestoresOriginal() {
        var history = TileHistory<Int>()
        _ = history.resolve(key: 1, action: .fill, current: original, target: fill)
        let frame = history.resolve(key: 1, action: .fill, current: fill, target: fill)
        #expect(frame == original)
        #expect(!history.hasOriginal(for: 1))
    }

    @Test func switchingActionsKeepsTrueOriginal() {
        var history = TileHistory<Int>()
        _ = history.resolve(key: 1, action: .fill, current: original, target: fill)
        let toLeft = history.resolve(key: 1, action: .leftHalf, current: fill, target: left)
        #expect(toLeft == left)
        let back = history.resolve(key: 1, action: .leftHalf, current: left, target: left)
        #expect(back == original)
    }

    @Test func manualMoveForgetsOldOriginal() {
        var history = TileHistory<Int>()
        _ = history.resolve(key: 1, action: .fill, current: original, target: fill)
        let movedByHand = CGRect(x: 50, y: 50, width: 600, height: 400)
        let frame = history.resolve(key: 1, action: .fill, current: movedByHand, target: fill)
        #expect(frame == fill)
        // A second click now goes back to where the user put it, not the older frame.
        let back = history.resolve(key: 1, action: .fill, current: fill, target: fill)
        #expect(back == movedByHand)
    }

    @Test func clampedFrameStillCountsAsTiled() {
        var history = TileHistory<Int>()
        _ = history.resolve(key: 1, action: .leftHalf, current: original, target: left)
        // The app refused to go narrower than 800pt.
        let clamped = CGRect(x: 0, y: 0, width: 800, height: 875)
        history.recordApplied(key: 1, frame: clamped)
        let back = history.resolve(key: 1, action: .leftHalf, current: clamped, target: left)
        #expect(back == original)
    }

    @Test func windowsAreTrackedSeparately() {
        var history = TileHistory<Int>()
        _ = history.resolve(key: 1, action: .fill, current: original, target: fill)
        let other = CGRect(x: 10, y: 10, width: 300, height: 300)
        _ = history.resolve(key: 2, action: .fill, current: other, target: fill)
        #expect(history.resolve(key: 1, action: .fill, current: fill, target: fill) == original)
        #expect(history.resolve(key: 2, action: .fill, current: fill, target: fill) == other)
    }
}

@Suite("Placement rules")
struct PlacementRulesTests {
    @Test func chromeUsesRightEnd() {
        #expect(PlacementRules.placement(forBundleID: "com.google.Chrome", overrides: [:]) == .rightEnd)
    }

    @Test func vsCodeUsesAfterTrafficLights() {
        #expect(PlacementRules.placement(forBundleID: "com.microsoft.VSCode", overrides: [:]) == .afterTrafficLights)
    }

    @Test func userOverrideWins() {
        let overrides: [String: ToolbarPlacement] = ["com.google.Chrome": .afterTrafficLights]
        #expect(PlacementRules.placement(forBundleID: "com.google.Chrome", overrides: overrides) == .afterTrafficLights)
    }

    @Test func unknownAppUsesDefault() {
        #expect(PlacementRules.placement(forBundleID: nil, overrides: [:]) == .afterTrafficLights)
    }
}
