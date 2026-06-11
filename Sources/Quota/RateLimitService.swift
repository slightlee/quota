import Foundation

@MainActor
protocol RateLimitServiceObserver: AnyObject {
    func rateLimitService(_ service: RateLimitService, didUpdate state: RateLimitDisplayState)
    func rateLimitService(_ service: RateLimitService, didFail error: Error, lastState: RateLimitDisplayState?)
}

@MainActor
final class RateLimitService {
    private let client: CodexAppServerClient
    private let refreshInterval: TimeInterval
    private var timer: Timer?
    private var observers = NSHashTable<AnyObject>.weakObjects()
    private var isRefreshing = false
    private(set) var state: RateLimitDisplayState?

    init(client: CodexAppServerClient, refreshInterval: TimeInterval = 120) {
        self.client = client
        self.refreshInterval = refreshInterval
    }

    func addObserver(_ observer: RateLimitServiceObserver) {
        observers.add(observer)
        if let state {
            observer.rateLimitService(self, didUpdate: state)
        }
    }

    func start() {
        guard timer == nil else { return }

        debugLog("[Quota] rate-limit refresh started")
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func reconnectAndRefresh() {
        isRefreshing = false
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }

        isRefreshing = true
        debugLog("[Quota] refreshing rate limits")
        client.readRateLimits { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false

                switch result {
                case .success(let response):
                    do {
                        let displayState = try response.displayState()
                        self.state = displayState
                        debugLog("[Quota] rate limits updated")
                        self.notifyUpdate(displayState)
                    } catch {
                        self.notifyFailure(error)
                    }
                case .failure(let error):
                    self.notifyFailure(error)
                }
            }
        }
    }

    private func notifyUpdate(_ state: RateLimitDisplayState) {
        for observer in observers.allObjects {
            (observer as? RateLimitServiceObserver)?.rateLimitService(self, didUpdate: state)
        }
    }

    private func notifyFailure(_ error: Error) {
        for observer in observers.allObjects {
            (observer as? RateLimitServiceObserver)?.rateLimitService(self, didFail: error, lastState: state)
        }
    }
}
