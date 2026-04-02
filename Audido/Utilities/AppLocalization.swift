import Foundation

/// Resolves String Catalog keys using the app’s UI language (`ModelManager.uiLanguage`).
/// SwiftUI’s `environment(\.locale)` is not reliably applied for catalog lookups in the macOS Settings scene.
enum AppLocalization {
    static func locale(forUiLanguage code: String) -> Locale {
        switch code {
        case "nl": return Locale(identifier: "nl_NL")
        case "en": return Locale(identifier: "en_US")
        default: return Locale(identifier: code)
        }
    }

    static func string(_ key: String, uiLanguage: String) -> String {
        let bundle = bundle(forUiLanguage: uiLanguage)
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }

    private static var bundleCache: [String: Bundle] = [:]

    private static func bundle(forUiLanguage code: String) -> Bundle {
        if let cached = bundleCache[code] { return cached }
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            bundleCache[code] = bundle
            return bundle
        }
        return .main
    }
}
