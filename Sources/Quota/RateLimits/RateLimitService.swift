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
    private let refreshTimeout: TimeInterval
    private let mainQueue = DispatchQueue.main
    private var refreshTimer: DispatchSourceTimer?
    private var refreshTimeoutTimer: DispatchSourceTimer?
    private var observers = NSHashTable<AnyObject>.weakObjects()
    private var isRefreshing = false
    /// Increments on every refresh so stale callbacks are ignored after timeout or newer requests.
    private var refreshGeneration = 0
    private(set) var state: RateLimitDisplayState?

    init(client: CodexAppServerClient, refreshInterval: TimeInterval = 120, refreshTimeout: TimeInterval = 30) {
        self.client = client
        self.refreshInterval = refreshInterval
        self.refreshTimeout = refreshTimeout
    }

    func addObserver(_ observer: RateLimitServiceObserver) {
        observers.add(observer)
        if let state {
            observer.rateLimitService(self, didUpdate: state)
        }
    }

    func start() {
        guard refreshTimer == nil else { return }

        debugLog("[Quota] rate-limit refresh started")
        refresh()

        let timer = DispatchSource.makeTimerSource(queue: mainQueue)
        timer.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval)
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        timer.resume()
        refreshTimer = timer
    }

    func stop() {
        refreshTimer?.cancel()
        refreshTimer = nil
        refreshTimeoutTimer?.cancel()
        refreshTimeoutTimer = nil
    }

    func reconnectAndRefresh() {
        isRefreshing = false
        refreshGeneration &+= 1
        refreshTimeoutTimer?.cancel()
        refreshTimeoutTimer = nil
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }

        isRefreshing = true
        refreshGeneration &+= 1
        let generation = refreshGeneration
        startRefreshTimeout()
        debugLog("[Quota] refreshing rate limits")
        client.readRateLimits { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.refreshGeneration == generation else { return }
                self.cancelRefreshTimeout()
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

    /// Timeout guard that resets isRefreshing when the callback never arrives.
    private func startRefreshTimeout() {
        refreshTimeoutTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: mainQueue)
        timer.schedule(deadline: .now() + refreshTimeout)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.isRefreshing {
                debugLog("[Quota] refresh timed out after \(Int(self.refreshTimeout))s, force resetting")
                self.isRefreshing = false
            }
        }
        timer.resume()
        refreshTimeoutTimer = timer
    }

    private func cancelRefreshTimeout() {
        refreshTimeoutTimer?.cancel()
        refreshTimeoutTimer = nil
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
