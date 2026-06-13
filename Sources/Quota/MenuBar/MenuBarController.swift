import AppKit

@MainActor
final class MenuBarController: NSObject, RateLimitServiceObserver {
    private let service: RateLimitService
    private let showSettings: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let contentView = MenuBarLimitView(frame: NSRect(x: 0, y: 0, width: 260, height: 105))
    private let errorItem = NSMenuItem()
    private var usesIconOnly = false

    init(service: RateLimitService, showSettings: @escaping () -> Void) {
        self.service = service
        self.showSettings = showSettings
    }

    func start() {
        if let image = loadStatusImage() {
            statusItem.button?.image = image
            statusItem.button?.imagePosition = .imageOnly
            usesIconOnly = true
        } else {
            statusItem.button?.title = "Codex"
        }
        statusItem.button?.toolTip = "Codex 额度"
        debugLog("[Quota] status item created")

        let menu = NSMenu()
        let visualItem = NSMenuItem()
        visualItem.view = contentView
        visualItem.isEnabled = false

        errorItem.isEnabled = false
        errorItem.isHidden = true

        menu.addItem(visualItem)
        menu.addItem(errorItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "刷新", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu

        service.addObserver(self)
    }

    func applyPlan(_ plan: String) {
        contentView.configureModel("Codex", plan: plan)
    }

    func rateLimitService(_ service: RateLimitService, didUpdate state: RateLimitDisplayState) {
        render(state: state, error: nil)
    }

    func rateLimitService(_ service: RateLimitService, didFail error: Error, lastState: RateLimitDisplayState?) {
        if let lastState {
            render(state: lastState, error: error)
        } else {
            updateStatusLabel(fiveHour: nil, weekly: nil)
            errorItem.title = "错误：\(error.localizedDescription)"
            errorItem.isHidden = false
        }
    }

    private func render(state: RateLimitDisplayState, error: Error?) {
        updateStatusLabel(
            fiveHour: Int(state.fiveHour.remainingPercent.rounded()),
            weekly: Int(state.weekly.remainingPercent.rounded())
        )
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

    @objc private func openSettings() {
        showSettings()
    }

    /// Open the status item menu (used by global hotkey).
    func showMenu() {
        statusItem.button?.performClick(nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func loadStatusImage() -> NSImage? {
        let imageURL = Bundle.main
            .url(forResource: "MenuBarIcon", withExtension: "png")
            ?? Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png")

        guard let image = imageURL.flatMap(NSImage.init(contentsOf:)) else {
            return nil
        }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }

    private func updateStatusLabel(fiveHour: Int?, weekly: Int?) {
        guard !usesIconOnly else {
            return
        }

        if let fiveHour, let weekly {
            statusItem.button?.title = "Codex \(fiveHour)% / \(weekly)%"
        } else {
            statusItem.button?.title = "Codex --%"
        }
    }

}
