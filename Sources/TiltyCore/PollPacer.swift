/// Decides how often Tilty's backup poll runs.
///
/// Most apps report window moves and focus changes, so the poll rarely finds anything new.
/// It runs fast while the focused window is changing and slows down once things are quiet,
/// so an idle Mac is not woken up several times a second.
public struct PollPacer: Sendable {

    /// Seconds between polls while something is changing.
    public let fast: Double
    /// Seconds between polls once things have been quiet.
    public let slow: Double
    /// How many quiet polls in a row it takes to slow down.
    public let quietPollsBeforeSlow: Int

    private var quietPolls = 0

    public init(fast: Double = 0.4, slow: Double = 1.2, quietPollsBeforeSlow: Int = 8) {
        self.fast = fast
        self.slow = slow
        self.quietPollsBeforeSlow = quietPollsBeforeSlow
    }

    /// Seconds until the next poll.
    public var interval: Double {
        quietPolls >= quietPollsBeforeSlow ? slow : fast
    }

    /// Records whether the last poll saw the focused window or its frame change.
    public mutating func record(changed: Bool) {
        quietPolls = changed ? 0 : min(quietPolls + 1, quietPollsBeforeSlow)
    }

    /// Goes back to fast polling, for example after waking up.
    public mutating func reset() {
        quietPolls = 0
    }
}
