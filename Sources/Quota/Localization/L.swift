import Foundation

/// Typed accessors for localized UI strings (wraps `LocalizationManager`).
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
    static var mimoTokenPlanTitle: String { tr(.mimoTokenPlanTitle) }
    static var remaining: String { tr(.remaining) }
    static var reset: String { tr(.reset) }
    static var noData: String { tr(.noData) }
    static func resetCreditsSuffix(_ count: Int) -> String { tr(.resetCreditsSuffix, count) }

    static var proxy: String { tr(.proxy) }
    static var hotkey: String { tr(.hotkey) }
    static var languageTitle: String { tr(.language) }
    static var providers: String { tr(.providers) }
    static var about: String { tr(.about) }
    static var save: String { tr(.save) }
    static var cancel: String { tr(.cancel) }
    static func appVersion(_ version: String) -> String { tr(.appVersion, version) }
    static var aboutSubtitle: String { tr(.aboutSubtitle) }
    static var aboutFeedback: String { tr(.aboutFeedback) }
    static var aboutGitHub: String { tr(.aboutGitHub) }

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
    static var providersSubtitle: String { tr(.providersSubtitle) }
    static var providersHelp: String { tr(.providersHelp) }
    static func providersSelectedCount(selected: Int, max: Int) -> String {
        tr(.providersSelectedCount, selected, max)
    }
    static var providersDragHint: String { tr(.providersDragHint) }
    static var mimoCookieLabel: String { tr(.mimoCookieLabel) }
    static var mimoCookiePlaceholder: String { tr(.mimoCookiePlaceholder) }
    static var mimoCookieHelp: String { tr(.mimoCookieHelp) }
    static var mimoCookieSaveErrorTitle: String { tr(.mimoCookieSaveErrorTitle) }

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
    static var requestTimedOut: String { tr(.requestTimedOut) }
    static var grokUnauthorized: String { tr(.grokUnauthorized) }
    static var grokNotSignedIn: String { tr(.grokNotSignedIn) }
    static func grokRequestFailed(_ statusCode: Int) -> String { tr(.grokRequestFailed, statusCode) }
    static var claudeUnauthorized: String { tr(.claudeUnauthorized) }
    static var claudeNotSignedIn: String { tr(.claudeNotSignedIn) }
    static var claudeTokenExpired: String { tr(.claudeTokenExpired) }
    static func claudeRequestFailed(_ statusCode: Int) -> String { tr(.claudeRequestFailed, statusCode) }
    static var mimoCodeNotSignedIn: String { tr(.mimoCodeNotSignedIn) }
    static var mimoCodeInvalidAuth: String { tr(.mimoCodeInvalidAuth) }
    static var mimoCookieMissing: String { tr(.mimoCookieMissing) }
    static var mimoUnauthorized: String { tr(.mimoUnauthorized) }
    static func mimoRequestFailed(_ statusCode: Int) -> String { tr(.mimoRequestFailed, statusCode) }
    static var mimoKeychainWriteFailed: String { tr(.mimoKeychainWriteFailed) }

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

    /// e.g. "Codex 周限额不足"
    static func lowQuotaTitle(providerName: String, windowTitle: String, severity: String) -> String {
        tr(.lowQuotaTitle, providerName, windowTitle, severity)
    }

    /// e.g. "剩余 18%"
    static func lowQuotaBody(remainingPercent: Int) -> String {
        tr(.lowQuotaBody, remainingPercent)
    }

    /// e.g. "剩余 18%，3/20 14:00 重置"
    static func lowQuotaBody(remainingPercent: Int, resetText: String) -> String {
        tr(.lowQuotaBodyWithReset, remainingPercent, resetText)
    }

    static var severityWarning: String { tr(.severityWarning) }
    static var severityUrgent: String { tr(.severityUrgent) }
    static var severityCritical: String { tr(.severityCritical) }

    private static func tr(_ key: LocalizationKey, _ arguments: CVarArg...) -> String {
        LocalizationManager.shared.localizedString(key, arguments: arguments)
    }
}
