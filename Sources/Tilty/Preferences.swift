import Foundation
import TiltyCore

/// Settings saved between launches.
final class Preferences {
    private let defaults: UserDefaults
    private enum Key {
        static let paused = "paused"
        static let placementOverrides = "placementOverrides"
        static let suggestAfterHalves = "suggestAfterHalves"
        static let animateMoves = "animateMoves"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isPaused: Bool {
        get { defaults.bool(forKey: Key.paused) }
        set { defaults.set(newValue, forKey: Key.paused) }
    }

    /// Show the window picker for the other side after Left or Right. Off by default.
    var suggestAfterHalves: Bool {
        get { defaults.bool(forKey: Key.suggestAfterHalves) }
        set { defaults.set(newValue, forKey: Key.suggestAfterHalves) }
    }

    /// Slide windows into place instead of snapping. On by default.
    var animateMoves: Bool {
        get { defaults.object(forKey: Key.animateMoves) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.animateMoves) }
    }

    var placementOverrides: [String: ToolbarPlacement] {
        let raw = defaults.dictionary(forKey: Key.placementOverrides) as? [String: String] ?? [:]
        return raw.compactMapValues(ToolbarPlacement.init(rawValue:))
    }

    func placement(forBundleID bundleID: String?) -> ToolbarPlacement {
        PlacementRules.placement(forBundleID: bundleID, overrides: placementOverrides)
    }

    func setPlacement(_ placement: ToolbarPlacement, forBundleID bundleID: String) {
        var raw = defaults.dictionary(forKey: Key.placementOverrides) as? [String: String] ?? [:]
        raw[bundleID] = placement.rawValue
        defaults.set(raw, forKey: Key.placementOverrides)
    }
}
