import Foundation

struct DirectUpload: Codable {
    let id: String
    let url: String

    enum CodingKeys: String, CodingKey {
        case data
    }

    enum DataKeys: String, CodingKey {
        case id
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data = try container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        id = try data.decode(String.self, forKey: .id)
        url = try data.decode(String.self, forKey: .url)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var data = container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        try data.encode(id, forKey: .id)
        try data.encode(url, forKey: .url)
    }
}

struct UploadStatus {
    let status: String
    let assetId: String?
}

struct AssetStatus {
    let status: String
    let playbackIds: [PlaybackId]?
    let tracks: [AssetTrack]?
}

struct PlaybackId: Codable {
    let id: String
    let policy: String
}

// Response wrappers for Mux API
struct MuxUploadResponse: Codable {
    let data: MuxUploadData
}

struct MuxUploadData: Codable {
    let id: String
    let status: String
    let assetId: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case assetId = "asset_id"
    }
}

struct MuxAssetResponse: Codable {
    let data: MuxAssetData
}

struct MuxAssetData: Codable {
    let id: String
    let status: String
    let playbackIds: [PlaybackId]?
    let tracks: [AssetTrack]?

    enum CodingKeys: String, CodingKey {
        case id, status, tracks
        case playbackIds = "playback_ids"
    }
}

struct AssetTrack: Codable {
    let id: String?
    let type: String?
    let status: String?
    let textType: String?
    let languageCode: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id, type, status, name
        case textType = "text_type"
        case languageCode = "language_code"
    }
}

struct MuxCreateUploadRequest: Codable {
    let newAssetSettings: NewAssetSettings
    let corsOrigin: String?

    enum CodingKeys: String, CodingKey {
        case newAssetSettings = "new_asset_settings"
        case corsOrigin = "cors_origin"
    }
}

struct NewAssetSettings: Codable {
    let playbackPolicy: [String]
    let inputs: [AssetInput]?

    enum CodingKeys: String, CodingKey {
        case playbackPolicy = "playback_policy"
        case inputs
    }
}

struct AssetInput: Codable {
    let generatedSubtitles: [GeneratedSubtitle]?

    enum CodingKeys: String, CodingKey {
        case generatedSubtitles = "generated_subtitles"
    }
}

struct GeneratedSubtitle: Codable {
    let languageCode: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case languageCode = "language_code"
        case name
    }
}

// MARK: - Robots API

struct RobotsJobRequest: Codable {
    let parameters: RobotsSummarizeParameters
}

struct RobotsSummarizeParameters: Codable {
    let assetId: String
    let tone: String?

    enum CodingKeys: String, CodingKey {
        case assetId = "asset_id"
        case tone
    }
}

struct RobotsJobResponse: Codable {
    let data: RobotsJob
}

struct RobotsJob: Codable {
    let id: String
    let workflow: String
    let status: String
    let outputs: SummarizeOutputs?
    let errors: [RobotsError]?
}

struct SummarizeOutputs: Codable {
    let title: String?
    let description: String?
    let tags: [String]?
}

struct RobotsError: Codable {
    let message: String?
}
