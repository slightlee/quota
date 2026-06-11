import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = CodexAppServerClient()
    private lazy var rateLimitService = RateLimitService(client: client)
    private lazy var statusBarController = StatusBarController(service: rateLimitService)
    private lazy var touchBarController = TouchBarController(service: rateLimitService, client: client)

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("[Quota] launched")
        statusBarController.start()
        touchBarController.start()
        rateLimitService.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        debugLog("[Quota] terminating")
        rateLimitService.stop()
        client.stop()
    }
}
