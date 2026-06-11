import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("[Quota] launched")
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
        client.stop(notifyPending: false)
        loadAccountMetadata()
        rateLimitService.reconnectAndRefresh()
    }
}
