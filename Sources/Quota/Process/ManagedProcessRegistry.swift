import Foundation

struct ManagedProcessRegistry {
    private let fileManager: FileManager
    private let recordURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let quotaDirectory = baseDirectory.appendingPathComponent("Quota", isDirectory: true)
        try? fileManager.createDirectory(at: quotaDirectory, withIntermediateDirectories: true)
        self.recordURL = quotaDirectory.appendingPathComponent("app-server.pid")
    }

    /// 只清理 Quota 自己上次写下的 app-server PID 记录。
    ///
    /// 仅当该 PID 仍然对应 `codex app-server --listen stdio://` 且父进程已死亡时才会终止。
    func cleanupOrphanIfNeeded() {
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
            clear()
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            clear()
            return
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear()
            return
        }

        let fields = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard fields.count >= 3,
              let reportedPID = Int(fields[0]),
              let ppid = Int(fields[1]),
              reportedPID == pid else {
            clear()
            return
        }

        let command = fields.dropFirst(2).joined(separator: " ")
        guard command.contains("codex") && command.contains("app-server") && command.contains("stdio://") else {
            clear()
            return
        }

        guard ppid == 1 else {
            return
        }

        kill(pid_t(pid), SIGTERM)
        debugLog("[Quota] killed managed orphaned app-server pid=\(pid)")
        clear()
    }

    func store(pid: Int) {
        do {
            try "\(pid)".write(to: recordURL, atomically: true, encoding: .utf8)
        } catch {
            debugLog("[Quota] failed to persist app-server pid: \(error.localizedDescription)")
        }
    }

    func clear() {
        try? fileManager.removeItem(at: recordURL)
    }
}
