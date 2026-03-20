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

    enum CodingKeys: String, CodingKey {
        case id, status
        case playbackIds = "playback_ids"
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

    enum CodingKeys: String, CodingKey {
        case playbackPolicy = "playback_policy"
    }
}
