import Foundation

enum MCPSetup {
    /// Path to the shaaaare-mcp binary bundled alongside the app
    static var mcpBinaryPath: String? {
        guard let execURL = Bundle.main.executableURL else { return nil }
        let mcpURL = execURL.deletingLastPathComponent().appendingPathComponent("shaaaare-mcp")
        return FileManager.default.fileExists(atPath: mcpURL.path) ? mcpURL.path : nil
    }

    /// Whether MCP is already configured in Claude Code
    static var isConfigured: Bool {
        guard let config = readClaudeConfig() else { return false }
        guard let servers = config["mcpServers"] as? [String: Any] else { return false }
        return servers["shaaaare-my-screeeen"] != nil
    }

    /// Install the MCP server config into ~/.claude.json
    static func install() -> Result<Void, MCPSetupError> {
        guard let binaryPath = mcpBinaryPath else {
            return .failure(.binaryNotFound)
        }

        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")

        var config = readClaudeConfig() ?? [:]
        var servers = (config["mcpServers"] as? [String: Any]) ?? [:]

        servers["shaaaare-my-screeeen"] = [
            "command": binaryPath,
            "args": [] as [String]
        ] as [String: Any]

        config["mcpServers"] = servers

        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configPath, options: .atomic)
            return .success(())
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
    }

    /// Remove the MCP server config from ~/.claude.json
    static func uninstall() -> Result<Void, MCPSetupError> {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")

        guard var config = readClaudeConfig() else {
            return .success(()) // Nothing to remove
        }

        guard var servers = config["mcpServers"] as? [String: Any] else {
            return .success(())
        }

        servers.removeValue(forKey: "shaaaare-my-screeeen")
        config["mcpServers"] = servers

        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configPath, options: .atomic)
            return .success(())
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
    }

    private static func readClaudeConfig() -> [String: Any]? {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

enum MCPSetupError: LocalizedError {
    case binaryNotFound
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "MCP binary not found in app bundle. Try rebuilding the app."
        case .writeFailed(let msg):
            return "Failed to write Claude config: \(msg)"
        }
    }
}
