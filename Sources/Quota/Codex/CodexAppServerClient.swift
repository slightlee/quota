import Foundation

final class CodexAppServerClient {
    private struct RPCResponse: Decodable {
        struct RPCError: Decodable {
            var message: String
        }

        var id: Int?
        var result: JSONValue?
        var error: RPCError?
    }

    private let codexURL: URL
    private let proxySettingsStore: ProxySettingsStore
    private let proxyEnvironmentBuilder: ProxyEnvironmentBuilder
    private let managedProcessRegistry: ManagedProcessRegistry
    private let appMetadata: AppMetadata
    private let queue = DispatchQueue(label: "CodexAppServerClient")
    private let decoder = JSONDecoder()

    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var stderr: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: (Result<JSONValue, Error>) -> Void] = [:]
    private var initialized = false
    private var initializing = false
    private var initQueue: [(Result<Void, Error>) -> Void] = []
    private var cachedAccount: AccountInfo?
    private var accountPending: [(Result<AccountInfo, Error>) -> Void] = []
    private var accountLoading = false
    private var processGeneration = 0
    private var reconnectTimer: DispatchSourceTimer?
    private var reconnectDelay: TimeInterval = 1
    private static let maxReconnectDelay: TimeInterval = 30

    init(
        proxySettingsStore: ProxySettingsStore = .shared,
        binaryLocator: CodexBinaryLocator = CodexBinaryLocator(),
        proxyEnvironmentBuilder: ProxyEnvironmentBuilder = ProxyEnvironmentBuilder(),
        managedProcessRegistry: ManagedProcessRegistry = ManagedProcessRegistry(),
        appMetadata: AppMetadata = .current
    ) {
        self.proxySettingsStore = proxySettingsStore
        self.proxyEnvironmentBuilder = proxyEnvironmentBuilder
        self.managedProcessRegistry = managedProcessRegistry
        self.appMetadata = appMetadata
        self.codexURL = binaryLocator.locate()
    }

    func readRateLimits(completion: @escaping (Result<GetAccountRateLimitsResponse, Error>) -> Void) {
        debugLog("[Quota] request account/rateLimits/read")
        request(method: "account/rateLimits/read", as: GetAccountRateLimitsResponse.self, completion: completion)
    }

    func readAccount(completion: @escaping (Result<AccountInfo, Error>) -> Void) {
        debugLog("[Quota] request account/read")
        queue.async {
            if let cachedAccount = self.cachedAccount {
                completion(.success(cachedAccount))
                return
            }

            self.accountPending.append(completion)
            guard !self.accountLoading else { return }

            self.accountLoading = true
            self.requestOnQueue(method: "account/read", as: AccountResponse.self) { result in
                switch result {
                case .success(let response):
                    let account = response.account
                    self.cachedAccount = account
                    self.finishAccountRequests(.success(account))
                case .failure(let error):
                    self.finishAccountRequests(.failure(error))
                }
            }
        }
    }

    func stop(notifyPending: Bool = true) {
        queue.async {
            self.reconnectTimer?.cancel()
            self.reconnectTimer = nil
            self.reconnectDelay = 1
            self.teardownProcess(error: CodexQuotaError.invalidResponse, notifyPending: notifyPending)
        }
    }

    private func request<T: Decodable>(
        method: String,
        as responseType: T.Type,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        queue.async {
            self.requestOnQueue(method: method, as: responseType, completion: completion)
        }
    }

    private func requestOnQueue<T: Decodable>(
        method: String,
        as responseType: T.Type,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        ensureStarted { result in
            switch result {
            case .success:
                self.send(method: method, params: nil) { result in
                    switch result {
                    case .success(let value):
                        do {
                            let data = try JSONEncoder().encode(value)
                            completion(.success(try self.decoder.decode(responseType, from: data)))
                        } catch {
                            completion(.failure(error))
                        }
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func teardownProcess(error: Error, notifyPending: Bool) {
        stdout?.readabilityHandler = nil
        stderr?.readabilityHandler = nil
        stdin?.closeFile()
        stdout?.closeFile()
        stderr?.closeFile()
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        stdin = nil
        stdout = nil
        stderr = nil
        buffer.removeAll(keepingCapacity: true)
        nextID = 1
        initialized = false
        initializing = false
        cachedAccount = nil
        processGeneration &+= 1
        if notifyPending {
            failPending(error)
            failInitQueue(error)
            failAccountRequests(error)
        } else {
            pending.removeAll()
            initQueue.removeAll()
            accountPending.removeAll()
            accountLoading = false
        }

        managedProcessRegistry.clear()
    }

    private func failInitQueue(_ error: Error) {
        let callbacks = initQueue
        initQueue = []
        callbacks.forEach { $0(.failure(error)) }
    }

    private func failAccountRequests(_ error: Error) {
        let callbacks = accountPending
        accountPending = []
        accountLoading = false
        callbacks.forEach { $0(.failure(error)) }
    }

    private func finishAccountRequests(_ result: Result<AccountInfo, Error>) {
        let callbacks = accountPending
        accountPending = []
        accountLoading = false
        callbacks.forEach { $0(result) }
    }

    /// Reconnects after an unexpected process exit with exponential backoff.
    private func scheduleReconnect() {
        reconnectTimer?.cancel()

        let delay = reconnectDelay
        debugLog("[Quota] scheduling reconnect in \(Int(delay))s")

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.reconnectTimer = nil
            // Restart the process through ensureStarted during reconnect.
            self.ensureStarted { result in
                switch result {
                case .success:
                    debugLog("[Quota] auto-reconnect succeeded")
                    self.reconnectDelay = 1  // Reset backoff after success.
                case .failure:
                    // Keep backing off after failures.
                    self.reconnectDelay = min(self.reconnectDelay * 2, Self.maxReconnectDelay)
                    self.scheduleReconnect()
                }
            }
        }
        timer.resume()
        reconnectTimer = timer
    }

    private func ensureStarted(completion: @escaping (Result<Void, Error>) -> Void) {
        if initialized {
            completion(.success(()))
            return
        }

        if initializing {
            initQueue.append(completion)
            return
        }

        initializing = true

        guard FileManager.default.isExecutableFile(atPath: codexURL.path) else {
            initializing = false
            completion(.failure(CodexQuotaError.codexBinaryMissing))
            return
        }

        // Reclaim only Quota's own stale app-server record.
        managedProcessRegistry.cleanupOrphanIfNeeded()

        do {
            if process == nil {
                debugLog("[Quota] starting app-server process")
                try startProcess()
            }
        } catch {
            debugLog("[Quota] failed to start app-server: \(error.localizedDescription)")
            initializing = false
            completion(.failure(error))
            return
        }

        send(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": appMetadata.name,
                    "version": appMetadata.version
                ],
                "capabilities": [:]
            ]
        ) { result in
            self.initializing = false
            let queue = self.initQueue
            self.initQueue = []
            switch result {
            case .success:
                self.initialized = true
                debugLog("[Quota] app-server initialized")
                completion(.success(()))
                queue.forEach { $0(.success(())) }
            case .failure(let error):
                debugLog("[Quota] app-server initialize failed: \(error.localizedDescription)")
                completion(.failure(error))
                queue.forEach { $0(.failure(error)) }
            }
        }
    }

    private func startProcess() throws {
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        let generation = processGeneration

        let process = Process()
        process.executableURL = codexURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.environment = launchEnvironment()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        process.terminationHandler = { [weak self] _ in
            self?.queue.async {
                debugLog("[Quota] app-server terminated")
                guard let self, self.processGeneration == generation else { return }
                self.teardownProcess(error: CodexQuotaError.invalidResponse, notifyPending: true)
                self.scheduleReconnect()
            }
        }

        stdout = output.fileHandleForReading
        stderr = error.fileHandleForReading
        stdin = input.fileHandleForWriting
        stdout?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async {
                self?.consume(data)
            }
        }
        stderr?.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
#if DEBUG
            if let text = String(data: data, encoding: .utf8) {
                debugLog("[Quota] app-server stderr: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
#endif
        }

        do {
            try process.run()
            self.process = process
            managedProcessRegistry.store(pid: Int(process.processIdentifier))
        } catch {
            stdin = nil
            stdout = nil
            stderr = nil
            throw error
        }
    }

    private func launchEnvironment() -> [String: String] {
        proxyEnvironmentBuilder.build(
            configuration: proxySettingsStore.configuration,
            baseEnvironment: ProcessInfo.processInfo.environment
        )
    }

    private func send(
        method: String,
        params: [String: Any]?,
        completion: @escaping (Result<JSONValue, Error>) -> Void
    ) {
        guard let stdin else {
            completion(.failure(CodexQuotaError.invalidResponse))
            return
        }

        let id = nextID
        nextID += 1
        pending[id] = completion

        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params ?? [:]
        ]

        do {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            stdin.write(data)
        } catch {
            pending.removeValue(forKey: id)
            completion(.failure(error))
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handleLine(Data(line))
        }
    }

    private func handleLine(_ data: Data) {
        do {
            let response = try decoder.decode(RPCResponse.self, from: data)
            guard let id = response.id, let callback = pending.removeValue(forKey: id) else {
                return
            }

            if let error = response.error {
                callback(.failure(CodexQuotaError.rpcError(error.message)))
                return
            }

            guard let result = response.result else {
                callback(.failure(CodexQuotaError.invalidResponse))
                return
            }

            callback(.success(result))
        } catch {
            debugLog("[Quota] failed to decode RPC response: \(error.localizedDescription)")
            return
        }
    }

    private func failPending(_ error: Error) {
        let callbacks = pending.values
        pending.removeAll()
        callbacks.forEach { $0(.failure(error)) }
    }
}
