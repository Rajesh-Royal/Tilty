import Foundation
import TiltyCore

/// Settings saved between launches.
///
/// Values are read once and kept in memory, because the toolbar checks them on every refresh.
/// Changes are written straight through to UserDefaults.
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
        isPaused = defaults.bool(forKey: Key.paused)
        suggestAfterHalves = defaults.bool(forKey: Key.suggestAfterHalves)
        animateMoves = defaults.object(forKey: Key.animateMoves) as? Bool ?? true
        let raw = defaults.dictionary(forKey: Key.placementOverrides) as? [String: String] ?? [:]
        placementOverrides = raw.compactMapValues(ToolbarPlacement.init(rawValue:))
    }

    var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: Key.paused) }
    }

    /// Show the window picker for the other side after Left or Right. Off by default.
    var suggestAfterHalves: Bool {
        didSet { defaults.set(suggestAfterHalves, forKey: Key.suggestAfterHalves) }
    }

    /// Slide windows into place instead of snapping. On by default.
    var animateMoves: Bool {
        didSet { defaults.set(animateMoves, forKey: Key.animateMoves) }
    }

    private(set) var placementOverrides: [String: ToolbarPlacement]

    func placement(forBundleID bundleID: String?) -> ToolbarPlacement {
        PlacementRules.placement(forBundleID: bundleID, overrides: placementOverrides)
    }

    func setPlacement(_ placement: ToolbarPlacement, forBundleID bundleID: String) {
        placementOverrides[bundleID] = placement
        defaults.set(placementOverrides.mapValues(\.rawValue), forKey: Key.placementOverrides)
    }
}
