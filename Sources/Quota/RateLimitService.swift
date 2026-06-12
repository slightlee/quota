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
    private var timer: Timer?
    private var refreshTimeoutTimer: Timer?
    private var observers = NSHashTable<AnyObject>.weakObjects()
    private var isRefreshing = false
    /// 每次 refresh 递增，超时或新请求后旧回调自动失效
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
        refreshTimeoutTimer?.invalidate()
        refreshTimeoutTimer = nil
    }

    func reconnectAndRefresh() {
        isRefreshing = false
        refreshGeneration &+= 1  // 使旧回调失效
        refreshTimeoutTimer?.invalidate()
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

    /// 超时保护：如果回调迟迟不来，强制重置 isRefreshing
    private func startRefreshTimeout() {
        refreshTimeoutTimer?.invalidate()
        refreshTimeoutTimer = Timer.scheduledTimer(withTimeInterval: refreshTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isRefreshing {
                    debugLog("[Quota] refresh timed out after \(Int(self.refreshTimeout))s, force resetting")
                    self.isRefreshing = false
                }
            }
        }
    }

    private func cancelRefreshTimeout() {
        refreshTimeoutTimer?.invalidate()
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
