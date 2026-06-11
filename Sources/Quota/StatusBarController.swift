import AppKit

@MainActor
final class StatusBarController: NSObject, RateLimitServiceObserver {
    private let service: RateLimitService
    private let client: CodexAppServerClient
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let contentView = LimitBarsView(width: 300)
    private let errorItem = NSMenuItem()

    init(service: RateLimitService, client: CodexAppServerClient) {
        self.service = service
        self.client = client
    }

    func start() {
        statusItem.button?.title = "Codex --%"
        statusItem.button?.toolTip = "Codex 额度"
        debugLog("[Quota] status item created")

        client.readAccount { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let account) = result, let plan = account.planType {
                    self?.contentView.configureModel("Codex", plan: plan)
                }
            }
        }

        let menu = NSMenu()
        let visualItem = NSMenuItem()
        visualItem.view = contentView
        visualItem.isEnabled = false

        errorItem.isEnabled = false
        errorItem.isHidden = true

        menu.addItem(visualItem)
        menu.addItem(errorItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "刷新", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu

        service.addObserver(self)
    }

    func rateLimitService(_ service: RateLimitService, didUpdate state: RateLimitDisplayState) {
        render(state: state, error: nil)
    }

    func rateLimitService(_ service: RateLimitService, didFail error: Error, lastState: RateLimitDisplayState?) {
        if let lastState {
            render(state: lastState, error: error)
        } else {
            statusItem.button?.title = "Codex --%"
            errorItem.title = "错误：\(error.localizedDescription)"
            errorItem.isHidden = false
        }
    }

    private func render(state: RateLimitDisplayState, error: Error?) {
        statusItem.button?.title = "Codex \(Int(state.fiveHour.remainingPercent.rounded()))% / \(Int(state.weekly.remainingPercent.rounded()))%"
        debugLog("[Quota] status updated: fiveHour=\(Int(state.fiveHour.remainingPercent.rounded())) weekly=\(Int(state.weekly.remainingPercent.rounded()))")

        contentView.update(with: state)

        if let error {
            debugLog("[Quota] refresh failed: \(error.localizedDescription)")
            errorItem.title = "刷新失败：\(error.localizedDescription)"
            errorItem.isHidden = false
        } else {
            errorItem.isHidden = true
        }
    }

    @objc private func refresh() {
        service.refresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

}
