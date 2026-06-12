import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    private let proxySettingsStore = ProxySettingsStore.shared
    private lazy var client = CodexAppServerClient(proxySettingsStore: proxySettingsStore)
    private lazy var rateLimitService = RateLimitService(client: client)
    private lazy var proxySettingsWindowController = ProxySettingsWindowController(store: proxySettingsStore) { [weak self] _ in
        self?.proxySettingsDidChange()
    }
    private lazy var menuBarController = MenuBarController(service: rateLimitService) { [weak self] in
        self?.showProxySettings()
    }
    private lazy var touchBarController = TouchBarController(service: rateLimitService)
    private lazy var notificationManager = QuotaNotificationManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("[Quota] launched")
        setupNotifications()
        menuBarController.start()
        touchBarController.start()
        rateLimitService.start()
        loadAccountMetadata()
    }

    func applicationWillTerminate(_ notification: Notification) {
        debugLog("[Quota] terminating")
        rateLimitService.stop()
        client.stop()
    }

    private func setupNotifications() {
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().delegate = self
        }
        rateLimitService.addObserver(notificationManager)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// 前台时也展示通知（菜单栏应用常驻运行，需要此回调）
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func showProxySettings() {
        proxySettingsWindowController.show()
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
        client.stop(notifyPending: false)      // 杀旧进程
        loadAccountMetadata()                   // 读账户信息（ensureStarted 会启动新进程）
        rateLimitService.reconnectAndRefresh()  // 刷新配额（ensureStarted 有守卫，不会重复启动）
    }
}
