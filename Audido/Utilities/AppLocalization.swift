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
        String(
            localized: String.LocalizationValue(stringLiteral: key),
            bundle: .main,
            locale: locale(forUiLanguage: uiLanguage)
        )
    }
}
