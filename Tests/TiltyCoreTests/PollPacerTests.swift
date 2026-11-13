import Testing
@testable import TiltyCore

@Suite("Poll pacer")
struct PollPacerTests {

    @Test func startsFast() {
        let pacer = PollPacer(fast: 0.4, slow: 1.2, quietPollsBeforeSlow: 3)
        #expect(pacer.interval == 0.4)
    }

    @Test func slowsDownAfterEnoughQuietPolls() {
        var pacer = PollPacer(fast: 0.4, slow: 1.2, quietPollsBeforeSlow: 3)
        pacer.record(changed: false)
        pacer.record(changed: false)
        #expect(pacer.interval == 0.4)
        pacer.record(changed: false)
        #expect(pacer.interval == 1.2)
    }

    @Test func speedsUpAsSoonAsSomethingChanges() {
        var pacer = PollPacer(fast: 0.4, slow: 1.2, quietPollsBeforeSlow: 2)
        for _ in 0..<50 { pacer.record(changed: false) }
        #expect(pacer.interval == 1.2)
        pacer.record(changed: true)
        #expect(pacer.interval == 0.4)
    }

    @Test func resetGoesBackToFast() {
        var pacer = PollPacer(fast: 0.4, slow: 1.2, quietPollsBeforeSlow: 1)
        pacer.record(changed: false)
        #expect(pacer.interval == 1.2)
        pacer.reset()
        #expect(pacer.interval == 0.4)
    }
}
