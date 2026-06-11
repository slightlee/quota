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

    private let codexURL = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")
    private let queue = DispatchQueue(label: "CodexAppServerClient")
    private let decoder = JSONDecoder()

    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: (Result<JSONValue, Error>) -> Void] = [:]
    private var initialized = false
    private var initializing = false
    private var initQueue: [(Result<Void, Error>) -> Void] = []
    private var cachedAccount: AccountInfo?
    private var accountPending: [(Result<AccountInfo, Error>) -> Void] = []
    private var accountLoading = false

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

    func stop() {
        queue.async {
            self.teardownProcess(error: CodexQuotaError.invalidResponse)
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

    private func teardownProcess(error: Error) {
        stdout?.readabilityHandler = nil
        stdin?.closeFile()
        stdout?.closeFile()
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        stdin = nil
        stdout = nil
        buffer.removeAll(keepingCapacity: true)
        nextID = 1
        initialized = false
        initializing = false
        cachedAccount = nil
        failPending(error)
        failInitQueue(error)
        failAccountRequests(error)
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

        let process = Process()
        process.executableURL = codexURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        process.terminationHandler = { [weak self] _ in
            self?.queue.async {
                debugLog("[Quota] app-server terminated")
                self?.teardownProcess(error: CodexQuotaError.invalidResponse)
            }
        }

        stdout = output.fileHandleForReading
        stdin = input.fileHandleForWriting
        stdout?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async {
                self?.consume(data)
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            stdin = nil
            stdout = nil
            throw error
        }
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
