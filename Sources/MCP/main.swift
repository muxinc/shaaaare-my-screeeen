import Foundation

// MARK: - Recording Model (mirrors the app's RecordingEntry)

struct RecordingEntry: Codable {
    let id: UUID
    let assetId: String
    let playbackId: String
    let playbackURL: String
    let createdAt: Date
    var title: String?
    var summary: String?
    var tags: [String]?
    var summarizing: Bool?

    var thumbnailURL: String {
        "https://image.mux.com/\(playbackId)/thumbnail.jpg?width=320&height=180&fit_mode=smartcrop"
    }

    var displayTitle: String {
        title ?? assetId
    }
}

// MARK: - History Store

func loadHistory() -> [RecordingEntry] {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let historyFile = appSupport
        .appendingPathComponent("com.mux.shaaaare-my-screeeen")
        .appendingPathComponent("history.json")

    guard let data = try? Data(contentsOf: historyFile) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([RecordingEntry].self, from: data)) ?? []
}

// MARK: - JSON-RPC Types

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCId?
    let method: String
    let params: AnyCodable?
}

enum JSONRPCId: Codable, Equatable {
    case string(String)
    case int(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.typeMismatch(JSONRPCId.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected string or int"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        }
    }
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let dbl = try? container.decode(Double.self) {
            value = dbl
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let s as String: try container.encode(s)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let b as Bool: try container.encode(b)
        case let arr as [Any]: try container.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        case is NSNull: try container.encodeNil()
        default: try container.encodeNil()
        }
    }
}

// MARK: - Response Helpers

func sendResponse(id: JSONRPCId?, result: Any) {
    let response: [String: Any] = [
        "jsonrpc": "2.0",
        "id": idToAny(id),
        "result": result
    ]
    sendJSON(response)
}

func sendError(id: JSONRPCId?, code: Int, message: String) {
    let response: [String: Any] = [
        "jsonrpc": "2.0",
        "id": idToAny(id),
        "error": ["code": code, "message": message] as [String: Any]
    ]
    sendJSON(response)
}

func idToAny(_ id: JSONRPCId?) -> Any {
    switch id {
    case .string(let s): return s
    case .int(let i): return i
    case nil: return NSNull()
    }
}

func sendJSON(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj),
          let str = String(data: data, encoding: .utf8) else { return }
    let output = str + "\n"
    FileHandle.standardOutput.write(output.data(using: .utf8)!)
}

// MARK: - Tool Definitions

let toolDefinitions: [[String: Any]] = [
    [
        "name": "list_recordings",
        "description": "List screen recordings from the shaaaare-my-screeeen app library. Returns recordings sorted by date (newest first). Can filter by date range or search text.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "search": [
                    "type": "string",
                    "description": "Search term to filter by title, summary, tags, or asset ID"
                ] as [String: Any],
                "since": [
                    "type": "string",
                    "description": "ISO 8601 date string. Only return recordings created after this date. Example: 2026-03-24T00:00:00Z"
                ] as [String: Any],
                "before": [
                    "type": "string",
                    "description": "ISO 8601 date string. Only return recordings created before this date."
                ] as [String: Any],
                "limit": [
                    "type": "integer",
                    "description": "Maximum number of recordings to return. Default: 20"
                ] as [String: Any]
            ] as [String: Any],
            "required": [] as [String]
        ] as [String: Any]
    ],
    [
        "name": "get_recording",
        "description": "Get full details of a specific screen recording by asset ID, playback ID, or entry UUID.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "id": [
                    "type": "string",
                    "description": "The recording's asset ID, playback ID, or entry UUID"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["id"]
        ] as [String: Any]
    ]
]

// MARK: - Tool Handlers

func handleListRecordings(params: [String: Any]?) -> Any {
    var entries = loadHistory()

    let search = (params?["search"] as? String)?.lowercased()
    let sinceStr = params?["since"] as? String
    let beforeStr = params?["before"] as? String
    let limit = params?["limit"] as? Int ?? 20

    let iso = ISO8601DateFormatter()

    if let sinceStr, let since = iso.date(from: sinceStr) {
        entries = entries.filter { $0.createdAt >= since }
    }
    if let beforeStr, let before = iso.date(from: beforeStr) {
        entries = entries.filter { $0.createdAt < before }
    }
    if let search, !search.isEmpty {
        entries = entries.filter { entry in
            entry.displayTitle.lowercased().contains(search) ||
            (entry.summary?.lowercased().contains(search) ?? false) ||
            (entry.tags?.contains(where: { $0.lowercased().contains(search) }) ?? false) ||
            entry.assetId.lowercased().contains(search) ||
            entry.playbackId.lowercased().contains(search)
        }
    }

    entries = Array(entries.prefix(limit))

    let formatter = ISO8601DateFormatter()
    let items: [[String: Any]] = entries.map { entry in
        var item: [String: Any] = [
            "id": entry.id.uuidString,
            "assetId": entry.assetId,
            "playbackId": entry.playbackId,
            "playbackURL": entry.playbackURL,
            "thumbnailURL": entry.thumbnailURL,
            "createdAt": formatter.string(from: entry.createdAt),
            "title": entry.displayTitle
        ]
        if let summary = entry.summary { item["summary"] = summary }
        if let tags = entry.tags { item["tags"] = tags }
        if entry.summarizing == true { item["summarizing"] = true }
        return item
    }

    let text = formatRecordingsList(items)
    return [
        "content": [
            ["type": "text", "text": text] as [String: Any]
        ]
    ] as [String: Any]
}

func handleGetRecording(params: [String: Any]?) -> Any {
    guard let id = params?["id"] as? String else {
        return errorContent("Missing required parameter: id")
    }

    let entries = loadHistory()
    let entry = entries.first { e in
        e.id.uuidString == id ||
        e.assetId == id ||
        e.playbackId == id
    }

    guard let entry else {
        return errorContent("No recording found matching '\(id)'")
    }

    let formatter = ISO8601DateFormatter()
    var details: [String: Any] = [
        "id": entry.id.uuidString,
        "assetId": entry.assetId,
        "playbackId": entry.playbackId,
        "playbackURL": entry.playbackURL,
        "thumbnailURL": entry.thumbnailURL,
        "createdAt": formatter.string(from: entry.createdAt),
        "title": entry.displayTitle
    ]
    if let summary = entry.summary { details["summary"] = summary }
    if let tags = entry.tags { details["tags"] = tags }
    if entry.summarizing == true { details["summarizing"] = true }

    let text = formatRecordingDetail(details)
    return [
        "content": [
            ["type": "text", "text": text] as [String: Any]
        ]
    ] as [String: Any]
}

func formatRecordingsList(_ items: [[String: Any]]) -> String {
    if items.isEmpty { return "No recordings found." }
    var lines: [String] = ["Found \(items.count) recording(s):\n"]
    for item in items {
        let title = item["title"] as? String ?? "Untitled"
        let date = item["createdAt"] as? String ?? ""
        let url = item["playbackURL"] as? String ?? ""
        let assetId = item["assetId"] as? String ?? ""
        var line = "- **\(title)** (\(date))\n  Asset: \(assetId)\n  URL: \(url)"
        if let tags = item["tags"] as? [String], !tags.isEmpty {
            line += "\n  Tags: \(tags.joined(separator: ", "))"
        }
        if let summarizing = item["summarizing"] as? Bool, summarizing {
            line += "\n  ⏳ Summary in progress..."
        }
        lines.append(line)
    }
    return lines.joined(separator: "\n")
}

func formatRecordingDetail(_ item: [String: Any]) -> String {
    var lines: [String] = []
    lines.append("# \(item["title"] as? String ?? "Untitled")")
    lines.append("")
    lines.append("- **Asset ID:** \(item["assetId"] as? String ?? "")")
    lines.append("- **Playback ID:** \(item["playbackId"] as? String ?? "")")
    lines.append("- **Playback URL:** \(item["playbackURL"] as? String ?? "")")
    lines.append("- **Thumbnail:** \(item["thumbnailURL"] as? String ?? "")")
    lines.append("- **Created:** \(item["createdAt"] as? String ?? "")")
    if let summary = item["summary"] as? String {
        lines.append("")
        lines.append("## Summary")
        lines.append(summary)
    }
    if let tags = item["tags"] as? [String], !tags.isEmpty {
        lines.append("")
        lines.append("## Tags")
        lines.append(tags.joined(separator: ", "))
    }
    if let summarizing = item["summarizing"] as? Bool, summarizing {
        lines.append("")
        lines.append("⏳ *Summary is still being generated...*")
    }
    return lines.joined(separator: "\n")
}

func errorContent(_ message: String) -> [String: Any] {
    [
        "content": [
            ["type": "text", "text": "Error: \(message)"] as [String: Any]
        ],
        "isError": true
    ] as [String: Any]
}

// MARK: - Request Handler

func handleRequest(_ request: JSONRPCRequest) {
    switch request.method {
    case "initialize":
        sendResponse(id: request.id, result: [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": [:] as [String: Any]
            ] as [String: Any],
            "serverInfo": [
                "name": "shaaaare-my-screeeen",
                "version": "1.0.0"
            ] as [String: Any]
        ] as [String: Any])

    case "notifications/initialized", "notifications/cancelled":
        // No response needed for notifications
        break

    case "tools/list":
        sendResponse(id: request.id, result: ["tools": toolDefinitions] as [String: Any])

    case "tools/call":
        let params = request.params?.value as? [String: Any]
        let toolName = params?["name"] as? String
        let toolArgs = params?["arguments"] as? [String: Any]

        switch toolName {
        case "list_recordings":
            let result = handleListRecordings(params: toolArgs)
            sendResponse(id: request.id, result: result)
        case "get_recording":
            let result = handleGetRecording(params: toolArgs)
            sendResponse(id: request.id, result: result)
        default:
            sendError(id: request.id, code: -32601, message: "Unknown tool: \(toolName ?? "nil")")
        }

    case "ping":
        sendResponse(id: request.id, result: [:] as [String: Any])

    default:
        if request.id != nil {
            sendError(id: request.id, code: -32601, message: "Method not found: \(request.method)")
        }
    }
}

// MARK: - Main Loop

let decoder = JSONDecoder()

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty else { continue }
    guard let data = line.data(using: .utf8) else { continue }

    do {
        let request = try decoder.decode(JSONRPCRequest.self, from: data)
        handleRequest(request)
    } catch {
        sendError(id: nil, code: -32700, message: "Parse error: \(error.localizedDescription)")
    }
}
