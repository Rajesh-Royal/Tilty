import CoreGraphics
import Testing
@testable import TiltyCore

@Suite("Move animation")
struct MoveAnimationTests {
    let start = CGRect(x: 200, y: 120, width: 800, height: 600)
    let end = CGRect(x: 0, y: 25, width: 1440, height: 875)

    @Test func startsAndEndsExactly() {
        #expect(MoveAnimation.frame(from: start, to: end, progress: 0) == start)
        #expect(MoveAnimation.frame(from: start, to: end, progress: 1) == end)
    }

    @Test func clampsProgressOutsideZeroToOne() {
        #expect(MoveAnimation.frame(from: start, to: end, progress: -0.5) == start)
        #expect(MoveAnimation.frame(from: start, to: end, progress: 1.7) == end)
    }

    @Test func easesOutSoMostOfTheMoveHappensEarly() {
        #expect(MoveAnimation.ease(0.5) > 0.5)
        var last = 0.0
        for step in 1...20 {
            let value = MoveAnimation.ease(Double(step) / 20)
            #expect(value >= last)
            last = value
        }
    }

    @Test func middleFramesUseWholePoints() {
        let frame = MoveAnimation.frame(from: start, to: end, progress: 0.37)
        for value in [frame.minX, frame.minY, frame.width, frame.height] {
            #expect(value == value.rounded())
        }
        #expect(frame.width > start.width && frame.width < end.width)
    }

    @Test func skipsTinyMoves() {
        #expect(!MoveAnimation.isWorthAnimating(from: start, to: start.offsetBy(dx: 2, dy: -1)))
        #expect(MoveAnimation.isWorthAnimating(from: start, to: end))
    }
}
