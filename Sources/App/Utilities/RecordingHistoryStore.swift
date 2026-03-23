import Foundation

struct RecordingEntry: Codable, Identifiable {
    let id: UUID
    let assetId: String
    let playbackId: String
    let playbackURL: String
    let createdAt: Date

    var thumbnailURL: URL? {
        URL(string: "https://image.mux.com/\(playbackId)/thumbnail.jpg?width=320&height=180&fit_mode=smartcrop")
    }

    init(assetId: String, playbackId: String, playbackURL: String) {
        self.id = UUID()
        self.assetId = assetId
        self.playbackId = playbackId
        self.playbackURL = playbackURL
        self.createdAt = Date()
    }
}

class RecordingHistoryStore {
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("com.mux.shaaaare-my-screeeen")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        fileURL = appDir.appendingPathComponent("history.json")
    }

    func load() -> [RecordingEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RecordingEntry].self, from: data)) ?? []
    }

    func append(_ entry: RecordingEntry) {
        var entries = load()
        entries.insert(entry, at: 0)
        save(entries)
    }

    func delete(id: UUID) {
        var entries = load()
        entries.removeAll { $0.id == id }
        save(entries)
    }

    private func save(_ entries: [RecordingEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
