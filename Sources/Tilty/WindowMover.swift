import AppKit
import ApplicationServices
import TiltyCore

/// Moves and resizes other apps' windows through the Accessibility API.
enum WindowMover {

    /// Applies a frame given in Cocoa coordinates.
    static func apply(cocoaFrame: CGRect, to window: AXUIElement, appElement: AXUIElement, primaryScreenHeight: CGFloat) {
        let target = Geometry.flip(cocoaFrame, primaryScreenHeight: primaryScreenHeight)

        // Chromium and Electron apps turn this on for screen readers.
        // While it is on, AX resizes animate slowly or land in the wrong place,
        // so it is switched off for the move and restored right after.
        let enhanced = appElement.bool(AXName.enhancedUserInterface) == true
        if enhanced { appElement.setBool(AXName.enhancedUserInterface, false) }
        defer { if enhanced { appElement.setBool(AXName.enhancedUserInterface, true) } }

        // Size first so the move is not clamped by the old size hanging off a screen edge.
        // Then position, then size again in case the app clamped the first resize.
        window.setSize(target.size)
        window.setPosition(target.origin)
        window.setSize(target.size)
    }
}
