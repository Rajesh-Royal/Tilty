import AppKit
import ApplicationServices
import OSLog
import TiltyCore

/// Moves and resizes other apps' windows through the Accessibility API.
///
/// macOS can't stretch another app's window picture the way its own tiling does,
/// so an animated move asks the app for a short series of frames instead.
/// Light apps keep up and slide smoothly. If an app is too slow to redraw,
/// the move jumps straight to the end so it never looks choppy.
@MainActor
enum WindowMover {

    static let duration: TimeInterval = 0.2
    /// A step slower than this means the app can't keep up.
    static let slowStep: TimeInterval = 0.03

    private static var running: [WindowKey: Slide] = [:]
    static let log = Logger(subsystem: "app.tilty.Tilty", category: "moves")

    /// True while any animated move is running.
    static var isSliding: Bool { !running.isEmpty }

    /// Moves a window to a frame given in Cocoa coordinates.
    /// `completion` runs once the window is at its final frame.
    static func move(
        cocoaFrame: CGRect,
        to window: AXUIElement,
        appElement: AXUIElement,
        primaryScreenHeight: CGFloat,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        let target = Geometry.flip(cocoaFrame, primaryScreenHeight: primaryScreenHeight)
        let key = WindowKey(element: window)
        running.removeValue(forKey: key)?.cancel()

        guard animated,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let start = window.frame,
              MoveAnimation.isWorthAnimating(from: start, to: target) else {
            withEnhancedUIOff(appElement) { place(window, at: target) }
            completion?()
            return
        }

        let slide = Slide(window: window, appElement: appElement, start: start, target: target) {
            running[key] = nil
            completion?()
        }
        running[key] = slide
        slide.begin()
    }

    /// Size first so the move is not clamped by the old size hanging off a screen edge.
    /// Then position, then size again in case the app clamped the first resize.
    fileprivate static func place(_ window: AXUIElement, at frame: CGRect) {
        window.setSize(frame.size)
        window.setPosition(frame.origin)
        window.setSize(frame.size)
    }

    /// Chromium and Electron apps turn this on for screen readers.
    /// While it is on, AX resizes animate slowly or land in the wrong place,
    /// so it is switched off for the move and restored right after.
    private static func withEnhancedUIOff(_ appElement: AXUIElement, _ body: () -> Void) {
        let enhanced = appElement.bool(AXName.enhancedUserInterface) == true
        if enhanced { appElement.setBool(AXName.enhancedUserInterface, false) }
        body()
        if enhanced { appElement.setBool(AXName.enhancedUserInterface, true) }
    }
}

/// One animated move, about 60 steps a second.
@MainActor
private final class Slide {
    private let window: AXUIElement
    private let appElement: AXUIElement
    private let start: CGRect
    private let target: CGRect
    private let onFinish: () -> Void
    private var timer: Timer?
    private var began: TimeInterval = 0
    private let restoreEnhancedUI: Bool
    private var steps = 0

    init(window: AXUIElement, appElement: AXUIElement, start: CGRect, target: CGRect, onFinish: @escaping () -> Void) {
        self.window = window
        self.appElement = appElement
        self.start = start
        self.target = target
        self.onFinish = onFinish
        restoreEnhancedUI = appElement.bool(AXName.enhancedUserInterface) == true
    }

    func begin() {
        if restoreEnhancedUI { appElement.setBool(AXName.enhancedUserInterface, false) }
        began = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        step()
    }

    private func step() {
        let now = ProcessInfo.processInfo.systemUptime
        let progress = (now - began) / WindowMover.duration
        guard progress < 1 else {
            finish()
            return
        }
        let frame = MoveAnimation.frame(from: start, to: target, progress: progress)
        steps += 1
        window.setPosition(frame.origin)
        window.setSize(frame.size)
        // The app took too long to redraw. Skip to the end instead of stuttering.
        let cost = ProcessInfo.processInfo.systemUptime - now
        if cost > WindowMover.slowStep {
            WindowMover.log.info("Slow step \(Int(cost * 1000), privacy: .public) ms, jumping to the end")
            finish()
        }
    }

    private func finish() {
        guard let timer else { return }
        timer.invalidate()
        self.timer = nil
        WindowMover.place(window, at: target)
        if restoreEnhancedUI { appElement.setBool(AXName.enhancedUserInterface, true) }
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - began) * 1000)
        WindowMover.log.info("Slide done in \(self.steps, privacy: .public) steps, \(elapsed, privacy: .public) ms")
        onFinish()
    }

    /// Stops without moving to the end, because a newer move takes over.
    func cancel() {
        timer?.invalidate()
        timer = nil
        if restoreEnhancedUI { appElement.setBool(AXName.enhancedUserInterface, true) }
    }
}
