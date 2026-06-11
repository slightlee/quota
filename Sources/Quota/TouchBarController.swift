import AppKit

@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate, RateLimitServiceObserver {
    private let service: RateLimitService
    private let client: CodexAppServerClient
    private let itemIdentifier = NSTouchBarItem.Identifier("com.openai.codex.touchbar.quota")
    private let trayIdentifier = "com.openai.codex.touchbar.quota.tray"
    private let contentView = LimitBarsView(frame: NSRect(x: 0, y: 0, width: 450, height: 26))
    private lazy var touchBar: NSTouchBar = {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [itemIdentifier]
        return touchBar
    }()

    init(service: RateLimitService, client: CodexAppServerClient) {
        self.service = service
        self.client = client
    }

    func start() {
        debugLog("[Quota] presenting Touch Bar")
        client.readAccount { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let account) = result, let plan = account.planType {
                    self?.contentView.configureModel("Codex", plan: plan)
                }
            }
        }
        presentSystemModalTouchBar()
        service.addObserver(self)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == itemIdentifier else { return nil }

        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = contentView
        item.customizationLabel = "Codex 额度"
        return item
    }

    func rateLimitService(_ service: RateLimitService, didUpdate state: RateLimitDisplayState) {
        contentView.update(with: state)
        debugLog("[Quota] Touch Bar updated")
        presentSystemModalTouchBar()
    }

    func rateLimitService(_ service: RateLimitService, didFail error: Error, lastState: RateLimitDisplayState?) {
        if let lastState {
            contentView.update(with: lastState)
        }
        debugLog("[Quota] Touch Bar refresh failed: \(error.localizedDescription)")
        presentSystemModalTouchBar()
    }

    private func presentSystemModalTouchBar() {
        let selector = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        guard NSTouchBar.responds(to: selector) else {
            debugLog("[Quota] private Touch Bar selector unavailable on NSTouchBar")
            return
        }

        debugLog("[Quota] invoking private Touch Bar selector")
        let touchBarClass: AnyObject = NSTouchBar.self
        _ = touchBarClass.perform(selector, with: touchBar, with: trayIdentifier as NSString)
    }
}
