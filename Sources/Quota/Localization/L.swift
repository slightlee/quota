import Foundation

enum L {
    static var locale: Locale {
        LocalizationManager.shared.locale
    }

    static var settings: String { tr(.settings) }
    static var refresh: String { tr(.refresh) }
    static var quit: String { tr(.quit) }
    static var quotaTooltip: String { tr(.quotaTooltip) }
    static var errorPrefix: String { tr(.errorPrefix) }
    static var refreshFailedPrefix: String { tr(.refreshFailedPrefix) }

    static var fiveHourTitle: String { tr(.fiveHourTitle) }
    static var weeklyTitle: String { tr(.weeklyTitle) }
    static var remaining: String { tr(.remaining) }
    static var reset: String { tr(.reset) }

    static var proxy: String { tr(.proxy) }
    static var hotkey: String { tr(.hotkey) }
    static var languageTitle: String { tr(.language) }
    static var save: String { tr(.save) }
    static var cancel: String { tr(.cancel) }

    static var proxySubtitle: String { tr(.proxySubtitle) }
    static var proxyMode: String { tr(.proxyMode) }
    static var proxyAddress: String { tr(.proxyAddress) }
    static var proxyManualHelp: String { tr(.proxyManualHelp) }
    static var proxyAutomaticHelp: String { tr(.proxyAutomaticHelp) }

    static var hotkeySubtitle: String { tr(.hotkeySubtitle) }
    static var enableGlobalHotkey: String { tr(.enableGlobalHotkey) }
    static var openMenu: String { tr(.openMenu) }
    static var pressHotkey: String { tr(.pressHotkey) }
    static var clickToRecordHotkey: String { tr(.clickToRecordHotkey) }

    static var languageSubtitle: String { tr(.languageSubtitle) }

    static var invalidProxyTitle: String { tr(.invalidProxyTitle) }
    static var invalidProxyMessage: String { tr(.invalidProxyMessage) }
    static var invalidHotkeyTitle: String { tr(.invalidHotkeyTitle) }
    static var invalidHotkeyMessage: String { tr(.invalidHotkeyMessage) }

    static var notificationPermissionTitle: String { tr(.notificationPermissionTitle) }
    static var notificationPermissionMessage: String { tr(.notificationPermissionMessage) }
    static var openSystemSettings: String { tr(.openSystemSettings) }
    static var later: String { tr(.later) }

    static var codexBinaryMissing: String { tr(.codexBinaryMissing) }
    static var missingRateLimitWindow: String { tr(.missingRateLimitWindow) }
    static var invalidResponse: String { tr(.invalidResponse) }

    static func proxyModeTitle(_ mode: ProxyMode) -> String {
        switch mode {
        case .automatic:
            return tr(.proxyModeAutomatic)
        case .manual:
            return tr(.proxyModeManual)
        case .disabled:
            return tr(.proxyModeDisabled)
        }
    }

    static func languagePreferenceTitle(_ preference: AppLanguagePreference) -> String {
        switch preference {
        case .system:
            return tr(.languagePreferenceSystem)
        case .english:
            return tr(.languagePreferenceEnglish)
        case .simplifiedChinese:
            return tr(.languagePreferenceSimplifiedChinese)
        }
    }

    static func lowQuotaTitle(fiveCrossed: Bool, weeklyCrossed: Bool, severity: String, emoji: String) -> String {
        if fiveCrossed && !weeklyCrossed {
            return tr(.lowQuotaFiveHourTitle, emoji, severity)
        }
        if weeklyCrossed && !fiveCrossed {
            return tr(.lowQuotaWeeklyTitle, emoji, severity)
        }
        return tr(.lowQuotaCombinedTitle, emoji, severity)
    }

    static var severityWarning: String { tr(.severityWarning) }
    static var severityUrgent: String { tr(.severityUrgent) }
    static var severityCritical: String { tr(.severityCritical) }

    private static func tr(_ key: LocalizationKey, _ arguments: CVarArg...) -> String {
        LocalizationManager.shared.localizedString(key, arguments: arguments)
    }
}
