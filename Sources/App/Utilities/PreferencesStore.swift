import Foundation

class PreferencesStore: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let keepLocalRecordings = "keepLocalRecordings"
        static let recordingsDirectory = "recordingsDirectory"
    }

    @Published var keepLocalRecordings: Bool {
        didSet { defaults.set(keepLocalRecordings, forKey: Keys.keepLocalRecordings) }
    }

    var recordingsDirectory: URL {
        get {
            if let path = defaults.string(forKey: Keys.recordingsDirectory) {
                return URL(fileURLWithPath: path)
            }
            return defaultRecordingsDirectory
        }
        set {
            defaults.set(newValue.path, forKey: Keys.recordingsDirectory)
        }
    }

    private var defaultRecordingsDirectory: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ShaaaareMyScreeeen")
    }

    init() {
        self.keepLocalRecordings = defaults.bool(forKey: Keys.keepLocalRecordings)
    }
}
