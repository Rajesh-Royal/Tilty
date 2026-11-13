import AppKit
import ApplicationServices

/// Small, typed helpers over the C Accessibility API.
/// All frames here are in Accessibility coordinates (top-left origin).
extension AXUIElement {

    func copyValue(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = copyValue(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func string(_ attribute: String) -> String? {
        copyValue(attribute) as? String
    }

    func bool(_ attribute: String) -> Bool? {
        copyValue(attribute) as? Bool
    }

    var position: CGPoint? {
        guard let value = copyValue(kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    var size: CGSize? {
        guard let value = copyValue(kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    var frame: CGRect? {
        guard let position, let size else { return nil }
        return CGRect(origin: position, size: size)
    }

    @discardableResult
    func setPosition(_ point: CGPoint) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, value) == .success
    }

    @discardableResult
    func setSize(_ size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, value) == .success
    }

    @discardableResult
    func setBool(_ attribute: String, _ flag: Bool) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, (flag ? kCFBooleanTrue : kCFBooleanFalse)) == .success
    }
}

/// Attribute names that have no constant in the SDK headers.
enum AXName {
    static let fullScreen = "AXFullScreen"
    static let enhancedUserInterface = "AXEnhancedUserInterface"
}

/// Lets an AXUIElement be used as a dictionary key.
/// Two elements for the same window compare equal through CFEqual.
struct WindowKey: Hashable {
    let element: AXUIElement

    static func == (lhs: WindowKey, rhs: WindowKey) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

enum Accessibility {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that sends the user to the Accessibility settings.
    @discardableResult
    static func requestTrust() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
