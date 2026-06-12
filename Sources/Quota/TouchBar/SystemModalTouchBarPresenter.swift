import AppKit

@MainActor
final class SystemModalTouchBarPresenter {
    private let trayIdentifier: String
    private var isPresented = false

    init(trayIdentifier: String) {
        self.trayIdentifier = trayIdentifier
    }

    func present(_ touchBar: NSTouchBar) {
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

    func dismiss(_ touchBar: NSTouchBar) {
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
