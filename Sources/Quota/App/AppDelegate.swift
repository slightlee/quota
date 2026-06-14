import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let proxySettingsStore = ProxySettingsStore.shared
    private let hotkeySettingsStore = HotkeySettingsStore.shared
    private var currentProxyConfiguration = ProxySettingsStore.shared.configuration
    private var currentHotkeyConfiguration = HotkeySettingsStore.shared.configuration
    private lazy var client = CodexAppServerClient(proxySettingsStore: proxySettingsStore)
    private lazy var rateLimitService = RateLimitService(client: client)
    private lazy var settingsWindowController = SettingsWindowController(
        proxyStore: proxySettingsStore,
        hotkeyStore: hotkeySettingsStore
    ) { [weak self] proxyConfig, hotkeyConfig in
        self?.settingsDidSave(proxyConfig: proxyConfig, hotkeyConfig: hotkeyConfig)
    }
    private lazy var menuBarController = MenuBarController(service: rateLimitService) { [weak self] in
        self?.showSettings()
    }
    private let hotkeyManager = GlobalHotkeyManager()
    private lazy var touchBarController = TouchBarController(service: rateLimitService)
    private lazy var notificationManager = QuotaNotificationManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("[Quota] launched")
        configureApplicationIcon()
        setupNotifications()
        menuBarController.start()
        touchBarController.start()
        rateLimitService.start()
        loadAccountMetadata()
        updateHotkeyRegistration(with: currentHotkeyConfiguration)
    }

    func applicationWillTerminate(_ notification: Notification) {
        debugLog("[Quota] terminating")
        hotkeyManager.unregister()
        rateLimitService.stop()
        client.stop()
    }

    private func setupNotifications() {
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().delegate = self
        }
        rateLimitService.addObserver(notificationManager)
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

    private func settingsDidSave(proxyConfig: ProxyConfiguration, hotkeyConfig: HotkeyConfiguration) {
        let proxyChanged = proxyConfig != currentProxyConfiguration
        let hotkeyChanged = hotkeyConfig != currentHotkeyConfiguration

        currentProxyConfiguration = proxyConfig
        currentHotkeyConfiguration = hotkeyConfig

        if proxyChanged {
            proxySettingsDidChange()
        }

        if hotkeyChanged {
            updateHotkeyRegistration(with: hotkeyConfig)
        }
    }

    private func loadAccountMetadata() {
        client.readAccount { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success(let account):
                    guard let plan = account.planType else { return }
                    self.menuBarController.applyPlan(plan)
                    self.touchBarController.applyPlan(plan)
                case .failure(let error):
                    debugLog("[Quota] account metadata load failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func proxySettingsDidChange() {
        client.stop(notifyPending: false)      // Stop the old process.
        loadAccountMetadata()                   // Read account metadata; ensureStarted starts a new process.
        rateLimitService.reconnectAndRefresh()  // Refresh quota; ensureStarted prevents duplicate starts.
    }
}
