import Foundation

struct CodexBinaryLocator {
    private let fileManager: FileManager
    private let codexAppBinaryURL = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// 按优先级查找 codex 二进制：CLI > Codex.app。
    func locate() -> URL {
        if let cliPath = findCLI() {
            debugLog("[Quota] found CLI codex at \(cliPath)")
            return cliPath
        }

        if fileManager.isExecutableFile(atPath: codexAppBinaryURL.path) {
            debugLog("[Quota] found Codex.app binary at \(codexAppBinaryURL.path)")
            return codexAppBinaryURL
        }

        debugLog("[Quota] no codex binary found")
        return codexAppBinaryURL
    }

    /// 通过 which 命令查找 CLI 路径。
    private func findCLI() -> URL? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["codex"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        guard task.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: output)
        return fileManager.isExecutableFile(atPath: url.path) ? url : nil
    }
}
