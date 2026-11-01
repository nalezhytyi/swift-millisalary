import Foundation

/// A text from this package's catalog, in the app's language: the one its
/// bundle picks from the user's preferred languages, as the app's own
/// texts do. `locale` names the language instead (the tests pin it):
/// `String(localized:bundle:locale:)` only formats with its locale and
/// still looks the text up in the preferred language
func localized(_ key: String.LocalizationValue, _ locale: Locale?) -> String {
    guard let locale else { return String(localized: key, bundle: .module) }
    return String(localized: LocalizedStringResource(key, locale: locale, bundle: .atURL(Bundle.module.bundleURL)))
}
