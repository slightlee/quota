import AppKit

@MainActor
final class StatusBarController: NSObject, RateLimitServiceObserver {
    private let service: RateLimitService
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let fiveHourItem = NSMenuItem()
    private let weeklyItem = NSMenuItem()
    private let errorItem = NSMenuItem()

    init(service: RateLimitService) {
        self.service = service
    }

    func start() {
        statusItem.button?.title = "Codex --%"
        statusItem.button?.toolTip = "Codex 额度"
        debugLog("[Quota] status item created")

        let menu = NSMenu()
        fiveHourItem.isEnabled = false
        weeklyItem.isEnabled = false
        errorItem.isEnabled = false
        errorItem.isHidden = true

        menu.addItem(fiveHourItem)
        menu.addItem(weeklyItem)
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

    @objc private func refresh() {
        service.refresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func render(state: RateLimitDisplayState, error: Error?) {
        statusItem.button?.title = "Codex \(Int(state.fiveHour.remainingPercent.rounded()))% / \(Int(state.weekly.remainingPercent.rounded()))%"
        debugLog("[Quota] status updated: fiveHour=\(Int(state.fiveHour.remainingPercent.rounded())) weekly=\(Int(state.weekly.remainingPercent.rounded()))")
        fiveHourItem.title = title(for: state.fiveHour)
        weeklyItem.title = title(for: state.weekly)

        if let error {
            debugLog("[Quota] refresh failed: \(error.localizedDescription)")
            errorItem.title = "刷新失败：\(error.localizedDescription)"
            errorItem.isHidden = false
        } else {
            errorItem.isHidden = true
        }
    }

    private func title(for window: LimitWindowDisplay) -> String {
        "\(window.title)：剩余 \(Int(window.remainingPercent.rounded()))%，\(window.resetText)"
    }
}
