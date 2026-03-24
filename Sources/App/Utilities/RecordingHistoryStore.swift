import Foundation

struct RecordingEntry: Codable, Identifiable {
    let id: UUID
    let assetId: String
    let playbackId: String
    let playbackURL: String
    let createdAt: Date

    // Robots API summary (populated async after upload)
    var title: String?
    var summary: String?
    var tags: [String]?
    var summarizing: Bool?

    var thumbnailURL: URL? {
        URL(string: "https://image.mux.com/\(playbackId)/thumbnail.jpg?width=320&height=180&fit_mode=smartcrop")
    }

    var displayTitle: String {
        title ?? assetId
    }

    init(assetId: String, playbackId: String, playbackURL: String) {
        self.id = UUID()
        self.assetId = assetId
        self.playbackId = playbackId
        self.playbackURL = playbackURL
        self.createdAt = Date()
        self.summarizing = true
    }
}

@MainActor
class RecordingHistoryStore: ObservableObject {
    @Published var entries: [RecordingEntry] = []
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("com.mux.shaaaare-my-screeeen")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        fileURL = appDir.appendingPathComponent("history.json")
        entries = loadFromDisk()
    }

    func load() -> [RecordingEntry] {
        entries
    }

    func reload() {
        entries = loadFromDisk()
    }

    func append(_ entry: RecordingEntry) {
        entries.insert(entry, at: 0)
        saveToDisk()
    }

    func update(id: UUID, transform: (inout RecordingEntry) -> Void) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            transform(&entries[index])
            saveToDisk()
        }
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        saveToDisk()
    }

    private func loadFromDisk() -> [RecordingEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RecordingEntry].self, from: data)) ?? []
    }

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
