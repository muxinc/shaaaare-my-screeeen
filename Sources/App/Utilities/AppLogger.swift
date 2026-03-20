import Foundation

final class AppLogger {
    static let shared = AppLogger()

    private let queue = DispatchQueue(label: "com.mux.app-logger")
    private let logURL: URL

    private init() {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ShaaaareMyScreeeen", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logURL = logsDir.appendingPathComponent("app.log", isDirectory: false)
    }

    func bootstrap() {
        log("Logging to \(logURL.path)")
    }

    func log(_ message: String) {
        let line = "\(timestamp()) \(message)"
        Swift.print(line)

        queue.async {
            guard let data = "\(line)\n".data(using: .utf8) else { return }
            if !FileManager.default.fileExists(atPath: self.logURL.path) {
                FileManager.default.createFile(atPath: self.logURL.path, contents: nil)
            }

            guard let handle = try? FileHandle(forWritingTo: self.logURL) else { return }
            defer { try? handle.close() }

            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                Swift.print("[AppLogger] Failed to write log: \(error.localizedDescription)")
            }
        }
    }

    func path() -> String {
        logURL.path
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

func appLog(_ message: String) {
    AppLogger.shared.log(message)
}
