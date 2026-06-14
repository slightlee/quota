import Foundation

struct CodexBinaryLocator {
    private let fileManager: FileManager
    private let codexAppBinaryURL = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Locates the codex binary by priority: CLI first, then Codex.app.
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

    /// Locates the CLI path through the which command.
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
