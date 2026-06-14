import Foundation

final class LocalizationManager {
    static let shared = LocalizationManager()

    private let fallbackLanguage: AppLanguage = .english

    var language: AppLanguage {
        LanguageSettingsStore.shared.preference.resolvedLanguage
    }

    var locale: Locale {
        language.locale
    }

    func localizedString(_ key: LocalizationKey, arguments: CVarArg...) -> String {
        let format = localizedFormat(for: key, language: language)
        guard !arguments.isEmpty else {
            return format
        }
        return String(format: format, locale: locale, arguments: arguments)
    }

    private func localizedFormat(for key: LocalizationKey, language: AppLanguage) -> String {
        let value = bundle(for: language)?.localizedString(forKey: key.rawValue, value: nil, table: nil)
        if let value, value != key.rawValue {
            return value
        }

        let fallback = bundle(for: fallbackLanguage)?.localizedString(forKey: key.rawValue, value: nil, table: nil)
        if let fallback, fallback != key.rawValue {
            return fallback
        }

        return key.rawValue
    }

    private func bundle(for language: AppLanguage) -> Bundle? {
        if let packagedBundleURL = Bundle.main.resourceURL?.appendingPathComponent("Quota_Quota.bundle"),
           let packagedBundle = Bundle(url: packagedBundleURL),
           let path = packagedBundle.path(forResource: language.rawValue, ofType: "lproj") {
            return Bundle(path: path)
        }

        guard let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}
