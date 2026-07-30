import AppKit
import UserNotifications

/// Application composition root: wires providers, quota refresh, menu bar, Touch Bar,
/// notifications, hotkeys, and settings.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let proxySettingsStore = ProxySettingsStore.shared
    private let hotkeySettingsStore = HotkeySettingsStore.shared
    private let languageSettingsStore = LanguageSettingsStore.shared
    private let providerSettingsStore = ProviderSettingsStore.shared
    private var currentProxyConfiguration = ProxySettingsStore.shared.configuration
    private var currentHotkeyConfiguration = HotkeySettingsStore.shared.configuration
    private var currentProviderConfiguration = ProviderSettingsStore.shared.configuration

    private lazy var registry = ProviderRegistry.makeDefault(proxySettingsStore: proxySettingsStore)
    private lazy var quotaService = QuotaService(
        registry: registry,
        providerSettingsStore: providerSettingsStore
    )
    private lazy var settingsWindowController = SettingsWindowController(
        proxyStore: proxySettingsStore,
        hotkeyStore: hotkeySettingsStore,
        languageStore: languageSettingsStore,
        providerStore: providerSettingsStore,
        providerOptions: registry.settingsOptions
    ) { [weak self] proxyConfig, hotkeyConfig, languagePreference, providerConfig in
        self?.settingsDidSave(
            proxyConfig: proxyConfig,
            hotkeyConfig: hotkeyConfig,
            languagePreference: languagePreference,
            providerConfig: providerConfig
        )
    }
    private lazy var menuBarController = MenuBarController(service: quotaService) { [weak self] in
        self?.showSettings()
    }
    private let hotkeyManager = GlobalHotkeyManager()
    private lazy var touchBarController = TouchBarController(service: quotaService)
    private lazy var notificationManager = QuotaNotificationManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("[Quota] launched")
        configureApplicationIcon()
        setupNotifications()
        menuBarController.start()
        touchBarController.start()
        quotaService.start()
        updateHotkeyRegistration(with: currentHotkeyConfiguration)
    }

    func applicationWillTerminate(_ notification: Notification) {
        debugLog("[Quota] terminating")
        hotkeyManager.unregister()
        quotaService.stop()
    }

    private func setupNotifications() {
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().delegate = self
        }
        quotaService.addObserver(notificationManager)
    }

    private func configureApplicationIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            return
        }

        NSApplication.shared.applicationIconImage = icon
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shows notifications while the menu bar app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func showSettings() {
        settingsWindowController.show()
    }

    private func updateHotkeyRegistration(with config: HotkeyConfiguration) {
        hotkeyManager.unregister()
        guard config.isEnabled, config.isValid else { return }
        hotkeyManager.register(keyCode: config.keyCode, modifiers: config.modifiers) { [weak self] in
            self?.menuBarController.showMenu()
        }
    }

    private func settingsDidSave(
        proxyConfig: ProxyConfiguration,
        hotkeyConfig: HotkeyConfiguration,
        languagePreference: AppLanguagePreference,
        providerConfig: ProviderSettingsConfiguration
    ) {
        // Language is already persisted by SettingsWindowController before this callback.
        _ = languagePreference

        let proxyChanged = proxyConfig != currentProxyConfiguration
        let hotkeyChanged = hotkeyConfig != currentHotkeyConfiguration
        currentProxyConfiguration = proxyConfig
        currentHotkeyConfiguration = hotkeyConfig
        currentProviderConfiguration = providerConfig

        if proxyChanged {
            proxySettingsDidChange()
        } else {
            // Also picks up provider credentials saved from the Settings window.
            quotaService.refreshAll()
        }

        if hotkeyChanged {
            updateHotkeyRegistration(with: hotkeyConfig)
        }

        reloadLocalizedText()
    }

    private func reloadLocalizedText() {
        menuBarController.reloadLocalizedText()
        touchBarController.reloadLocalizedText()
    }

    private func proxySettingsDidChange() {
        // Drop live CLI connections so the next fetch picks up new proxy env.
        quotaService.reconnectAndRefresh()
    }
}
