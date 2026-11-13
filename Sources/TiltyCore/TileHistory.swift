import CoreGraphics

/// Remembers each window's frame from before Tilty moved it.
///
/// Clicking the same action twice puts the window back where it was.
/// For example, Fill then Fill again restores the original size.
/// Switching between actions (Fill, then Left) keeps the original frame,
/// so the second click on Left still goes back to the true original.
/// If the user moves the window by hand, the old memory is dropped.
public struct TileHistory<Key: Hashable> {

    struct Entry {
        var original: CGRect
        var action: TileAction
        /// The frame Tilty asked for.
        var target: CGRect
        /// The frame the app actually settled on. Apps can clamp sizes.
        var applied: CGRect
    }

    private var entries: [Key: Entry] = [:]
    private let capacity: Int

    public init(capacity: Int = 64) {
        self.capacity = capacity
    }

    /// Decides which frame to apply for a click and updates the memory.
    /// - Parameters:
    ///   - key: identifies the window.
    ///   - action: the button the user clicked.
    ///   - current: the window frame right now.
    ///   - target: the frame for `action` on the window's screen.
    /// - Returns: the frame to apply.
    public mutating func resolve(key: Key, action: TileAction, current: CGRect, target: CGRect) -> CGRect {
        if let entry = entries[key], isStillTiled(current, by: entry) {
            if entry.action == action {
                entries[key] = nil
                return entry.original
            }
            entries[key] = Entry(original: entry.original, action: action, target: target, applied: target)
            return target
        }

        if entries.count >= capacity {
            entries.removeAll(keepingCapacity: true)
        }
        entries[key] = Entry(original: current, action: action, target: target, applied: target)
        return target
    }

    /// Records the frame the app ended up with after a move.
    public mutating func recordApplied(key: Key, frame: CGRect) {
        entries[key]?.applied = frame
    }

    /// Whether Tilty has a saved original frame for this window.
    public func hasOriginal(for key: Key) -> Bool {
        entries[key] != nil
    }

    private func isStillTiled(_ current: CGRect, by entry: Entry) -> Bool {
        Geometry.approximatelyEqual(current, entry.applied) || Geometry.approximatelyEqual(current, entry.target)
    }
}
