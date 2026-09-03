import Foundation

private final class BundleToken {}

extension Bundle {
    /// The framework's own bundle. Strings shipped with CleanerKit live here,
    /// not in the app bundle, so they must be looked up explicitly.
    static let cleanerKit = Bundle(for: BundleToken.self)
}

/// Looks a string up in CleanerKit's own catalog.
func kitString(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .cleanerKit)
}
