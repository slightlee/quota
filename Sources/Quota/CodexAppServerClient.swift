import Foundation
import CFNetwork

final class CodexAppServerClient {
    private struct RPCResponse: Decodable {
        struct RPCError: Decodable {
            var message: String
        }

        var id: Int?
        var result: JSONValue?
        var error: RPCError?
    }

    private let codexURL = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")
    private let proxySettingsStore: ProxySettingsStore
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
    private static let managedProcessRecordURL: URL = {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let quotaDirectory = baseDirectory.appendingPathComponent("Quota", isDirectory: true)
        try? fileManager.createDirectory(at: quotaDirectory, withIntermediateDirectories: true)
        return quotaDirectory.appendingPathComponent("app-server.pid")
    }()

    init(proxySettingsStore: ProxySettingsStore = .shared) {
        self.proxySettingsStore = proxySettingsStore
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

        Self.clearManagedProcessRecord()
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

    /// 进程异常退出后自动重连，指数退避（1s → 2s → 4s → ... → 30s）
    private func scheduleReconnect() {
        reconnectTimer?.cancel()

        let delay = reconnectDelay
        debugLog("[Quota] scheduling reconnect in \(Int(delay))s")

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.reconnectTimer = nil
            // 重连时通过 ensureStarted 重新启动进程
            self.ensureStarted { result in
                switch result {
                case .success:
                    debugLog("[Quota] auto-reconnect succeeded")
                    self.reconnectDelay = 1  // 成功后重置退避
                case .failure:
                    // 失败后继续退避重连
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

        // 只回收 Quota 自己上次遗留的 app-server 记录
        Self.cleanupManagedOrphanIfNeeded()

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
                    "name": "Quota",
                    "version": "0.1.0"
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
            Self.storeManagedProcessRecord(pid: Int(process.processIdentifier))
        } catch {
            stdin = nil
            stdout = nil
            stderr = nil
            throw error
        }
    }

    private func launchEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let proxyKeys = Self.proxyEnvironmentKeys

        switch proxySettingsStore.configuration.mode {
        case .automatic:
            if !proxyKeys.contains(where: { environment[$0]?.isEmpty == false }) {
                let systemEnvironment = Self.systemProxyEnvironment()
                for (key, value) in systemEnvironment {
                    environment[key] = value
                }
            }
        case .manual:
            let proxyURL = proxySettingsStore.configuration.proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !proxyURL.isEmpty {
                Self.applyProxy(proxyURL, to: &environment)
            }
            // 清除 automatic 模式可能残留的 bypass 列表
            environment.removeValue(forKey: "NO_PROXY")
            environment.removeValue(forKey: "no_proxy")
        case .disabled:
            for key in proxyKeys {
                environment.removeValue(forKey: key)
            }
            // 显式设置 NO_PROXY=* 确保子进程跳过所有代理
            environment["NO_PROXY"] = "*"
            environment["no_proxy"] = "*"
        }

        return environment
    }

    private static let proxyEnvironmentKeys = [
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "NO_PROXY",
        "http_proxy",
        "https_proxy",
        "all_proxy",
        "no_proxy"
    ]

    private static func applyProxy(_ proxyURL: String, to environment: inout [String: String]) {
        for key in proxyEnvironmentKeys {
            if key.lowercased().contains("no_proxy") {
                continue
            }
            environment[key] = proxyURL
        }
    }

    private static func systemProxyEnvironment() -> [String: String] {
        guard let settingsUnmanaged = CFNetworkCopySystemProxySettings() else {
            return [:]
        }

        guard let settings = settingsUnmanaged.takeRetainedValue() as? [String: Any] else {
            return [:]
        }
        var environment: [String: String] = [:]

        if let host = settings[kCFNetworkProxiesHTTPProxy as String] as? String,
           let port = settings[kCFNetworkProxiesHTTPPort as String] as? NSNumber,
           (settings[kCFNetworkProxiesHTTPEnable as String] as? NSNumber)?.intValue != 0 {
            applyHTTPProxy(host: host, port: port.intValue, into: &environment)
        }

        if let host = settings[kCFNetworkProxiesHTTPSProxy as String] as? String,
           let port = settings[kCFNetworkProxiesHTTPSPort as String] as? NSNumber,
           (settings[kCFNetworkProxiesHTTPSEnable as String] as? NSNumber)?.intValue != 0 {
            applyHTTPProxy(host: host, port: port.intValue, into: &environment)
        }

        if let host = settings[kCFNetworkProxiesSOCKSProxy as String] as? String,
           let port = settings[kCFNetworkProxiesSOCKSPort as String] as? NSNumber,
           (settings[kCFNetworkProxiesSOCKSEnable as String] as? NSNumber)?.intValue != 0 {
            applySOCKSProxy(host: host, port: port.intValue, into: &environment)
        }

        if let exceptions = settings[kCFNetworkProxiesExceptionsList as String] as? [String] {
            applyBypassList(exceptions, into: &environment)
        }

        if let excludeSimpleHostnames = settings[kCFNetworkProxiesExcludeSimpleHostnames as String] as? NSNumber,
           excludeSimpleHostnames.intValue != 0 {
            applyBypassList(["localhost", "127.0.0.1", "::1"], into: &environment)
        }

        return environment
    }

    private static func applyHTTPProxy(host: String, port: Int, into environment: inout [String: String]) {
        let proxyURL = "http://\(host):\(port)"
        environment["HTTP_PROXY"] = proxyURL
        environment["HTTPS_PROXY"] = proxyURL
        environment["ALL_PROXY"] = proxyURL
        environment["http_proxy"] = proxyURL
        environment["https_proxy"] = proxyURL
        environment["all_proxy"] = proxyURL
    }

    private static func applySOCKSProxy(host: String, port: Int, into environment: inout [String: String]) {
        let proxyURL = "socks5://\(host):\(port)"
        environment["HTTP_PROXY"] = proxyURL
        environment["HTTPS_PROXY"] = proxyURL
        environment["ALL_PROXY"] = proxyURL
        environment["http_proxy"] = proxyURL
        environment["https_proxy"] = proxyURL
        environment["all_proxy"] = proxyURL
    }

    private static func applyBypassList(_ hosts: [String], into environment: inout [String: String]) {
        let bypass = hosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")

        guard !bypass.isEmpty else { return }

        if let existing = environment["NO_PROXY"], !existing.isEmpty {
            environment["NO_PROXY"] = existing + "," + bypass
        } else {
            environment["NO_PROXY"] = bypass
        }

        if let existing = environment["no_proxy"], !existing.isEmpty {
            environment["no_proxy"] = existing + "," + bypass
        } else {
            environment["no_proxy"] = bypass
        }
    }

    // MARK: - 受管进程恢复

    /// 只清理 Quota 自己上次写下的 app-server PID 记录。
    ///
    /// 仅当该 PID 仍然对应 `codex app-server --listen stdio://` 且父进程已死亡时才会终止。
    private static func cleanupManagedOrphanIfNeeded() {
        let recordURL = managedProcessRecordURL
        guard let rawValue = try? String(contentsOf: recordURL, encoding: .utf8),
              let pid = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else {
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(pid)", "-o", "pid=,ppid=,command="]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            clearManagedProcessRecord()
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            clearManagedProcessRecord()
            return
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearManagedProcessRecord()
            return
        }

        let fields = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard fields.count >= 3,
              let reportedPID = Int(fields[0]),
              let ppid = Int(fields[1]),
              reportedPID == pid else {
            clearManagedProcessRecord()
            return
        }

        let command = fields.dropFirst(2).joined(separator: " ")
        guard command.contains("codex") && command.contains("app-server") && command.contains("stdio://") else {
            clearManagedProcessRecord()
            return
        }

        guard ppid == 1 else {
            return
        }

        kill(pid_t(pid), SIGTERM)
        debugLog("[Quota] killed managed orphaned app-server pid=\(pid)")
        clearManagedProcessRecord()
    }

    private static func storeManagedProcessRecord(pid: Int) {
        do {
            try "\(pid)".write(to: managedProcessRecordURL, atomically: true, encoding: .utf8)
        } catch {
            debugLog("[Quota] failed to persist app-server pid: \(error.localizedDescription)")
        }
    }

    private static func clearManagedProcessRecord() {
        try? FileManager.default.removeItem(at: managedProcessRecordURL)
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

enum JSONValue: Codable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
