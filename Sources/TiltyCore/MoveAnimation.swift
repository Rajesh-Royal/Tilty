import CoreGraphics

/// The math for sliding a window from one frame to another.
public enum MoveAnimation {

    /// Ease out: quick at the start, gentle at the end, like macOS window moves.
    public static func ease(_ progress: Double) -> Double {
        let remaining = 1 - min(max(progress, 0), 1)
        return 1 - remaining * remaining * remaining
    }

    /// The frame part way through a move. Edges are whole points so apps lay out cleanly.
    public static func frame(from start: CGRect, to end: CGRect, progress: Double) -> CGRect {
        if progress <= 0 { return start }
        if progress >= 1 { return end }
        let e = CGFloat(ease(progress))
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { (a + (b - a) * e).rounded() }
        return CGRect(
            x: mix(start.minX, end.minX),
            y: mix(start.minY, end.minY),
            width: mix(start.width, end.width),
            height: mix(start.height, end.height)
        )
    }

    /// A move of a few points is not worth animating.
    public static func isWorthAnimating(from start: CGRect, to end: CGRect) -> Bool {
        let change = [
            abs(start.minX - end.minX), abs(start.minY - end.minY),
            abs(start.width - end.width), abs(start.height - end.height),
        ].max() ?? 0
        return change > 4
    }
}
