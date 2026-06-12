import AppKit

@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate, RateLimitServiceObserver {
    private let service: RateLimitService
    private let workspace: NSWorkspace
    private let presentationPolicy: ActiveApplicationTouchBarPolicy
    private let itemIdentifier = NSTouchBarItem.Identifier("com.openai.codex.touchbar.quota")
    private let trayIdentifier = "com.openai.codex.touchbar.quota.tray"
    private let contentView = TouchBarLimitView(frame: NSRect(x: 0, y: 0, width: 450, height: 26))
    private var activeApplicationObserver: NSObjectProtocol?
    private var isPresented = false
    private lazy var touchBar: NSTouchBar = {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [itemIdentifier]
        return touchBar
    }()

    init(
        service: RateLimitService,
        workspace: NSWorkspace = .shared,
        presentationPolicy: ActiveApplicationTouchBarPolicy = ActiveApplicationTouchBarPolicy()
    ) {
        self.service = service
        self.workspace = workspace
        self.presentationPolicy = presentationPolicy
    }

    func start() {
        observeActiveApplication()
        updatePresentation(for: currentActiveApplication())
        service.addObserver(self)
    }

    func applyPlan(_ plan: String) {
        contentView.configureModel("Codex", plan: plan)
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
        updatePresentation(for: currentActiveApplication())
    }

    func rateLimitService(_ service: RateLimitService, didFail error: Error, lastState: RateLimitDisplayState?) {
        if let lastState {
            contentView.update(with: lastState)
        }
        debugLog("[Quota] Touch Bar refresh failed: \(error.localizedDescription)")
        updatePresentation(for: currentActiveApplication())
    }

    private func observeActiveApplication() {
        guard activeApplicationObserver == nil else { return }

        activeApplicationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let runningApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let application = ActiveApplicationInfo(
                bundleIdentifier: runningApplication?.bundleIdentifier,
                localizedName: runningApplication?.localizedName
            )

            Task { @MainActor [weak self] in
                self?.updatePresentation(for: application)
            }
        }
    }

    private func currentActiveApplication() -> ActiveApplicationInfo {
        let runningApplication = workspace.frontmostApplication
        return ActiveApplicationInfo(
            bundleIdentifier: runningApplication?.bundleIdentifier,
            localizedName: runningApplication?.localizedName
        )
    }

    private func updatePresentation(for application: ActiveApplicationInfo) {
        if presentationPolicy.shouldShow(for: application) {
            presentSystemModalTouchBar()
        } else {
            dismissSystemModalTouchBar()
        }
    }

    private func presentSystemModalTouchBar() {
        guard !isPresented else { return }

        let selector = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        guard NSTouchBar.responds(to: selector) else {
            debugLog("[Quota] private Touch Bar selector unavailable on NSTouchBar")
            return
        }

        debugLog("[Quota] invoking private Touch Bar selector")
        let touchBarClass: AnyObject = NSTouchBar.self
        _ = touchBarClass.perform(selector, with: touchBar, with: trayIdentifier as NSString)
        isPresented = true
    }

    private func dismissSystemModalTouchBar() {
        guard isPresented else { return }

        let selector = NSSelectorFromString("dismissSystemModalTouchBar:")
        guard NSTouchBar.responds(to: selector) else {
            debugLog("[Quota] private Touch Bar dismiss selector unavailable on NSTouchBar")
            isPresented = false
            return
        }

        debugLog("[Quota] dismissing private Touch Bar")
        let touchBarClass: AnyObject = NSTouchBar.self
        _ = touchBarClass.perform(selector, with: touchBar)
        isPresented = false
    }
}
