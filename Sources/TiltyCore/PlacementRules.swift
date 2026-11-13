/// Decides where the toolbar goes for a given app.
public enum PlacementRules {

    /// Chromium browsers put tabs right after the traffic lights.
    /// In these apps the toolbar moves to the right end of the tab strip so it does not cover a tab.
    public static let rightEndByDefault: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    /// The placement for an app.
    /// - Parameters:
    ///   - bundleID: the app's bundle identifier, if known.
    ///   - overrides: placements the user picked from the menu, keyed by bundle identifier.
    public static func placement(forBundleID bundleID: String?, overrides: [String: ToolbarPlacement]) -> ToolbarPlacement {
        guard let bundleID else { return .afterTrafficLights }
        if let override = overrides[bundleID] { return override }
        return rightEndByDefault.contains(bundleID) ? .rightEnd : .afterTrafficLights
    }
}
