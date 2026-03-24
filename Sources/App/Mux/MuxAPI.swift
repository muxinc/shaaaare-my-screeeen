import Foundation

class MuxAPI {
    let tokenId: String
    let tokenSecret: String
    private let baseURL = "https://api.mux.com"
    private let session: URLSession

    init(tokenId: String, tokenSecret: String) {
        self.tokenId = tokenId
        self.tokenSecret = tokenSecret
        self.session = URLSession.shared
    }

    private func authHeader() -> String {
        let credentials = "\(tokenId):\(tokenSecret)"
        let data = credentials.data(using: .utf8)!
        return "Basic \(data.base64EncodedString())"
    }

    func createDirectUpload() async throws -> DirectUpload {
        let url = URL(string: "\(baseURL)/video/v1/uploads")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = MuxCreateUploadRequest(
            newAssetSettings: NewAssetSettings(
                playbackPolicy: ["public"],
                inputs: [
                    AssetInput(generatedSubtitles: [
                        GeneratedSubtitle(languageCode: "en", name: "English CC")
                    ])
                ]
            ),
            corsOrigin: nil
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MuxAPIError.requestFailed(statusCode: statusCode, body: body)
        }

        return try JSONDecoder().decode(DirectUpload.self, from: data)
    }

    func uploadFile(_ fileURL: URL, to uploadURL: URL, progress: @escaping (Double) -> Void) async throws {
        let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 ?? 0

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")

        let delegate = UploadProgressDelegate(totalBytes: fileSize, onProgress: progress)
        let uploadSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let (_, response) = try await uploadSession.upload(for: request, fromFile: fileURL)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw MuxAPIError.uploadFailed(statusCode: statusCode)
        }

        progress(1.0)
    }

    func getUpload(id: String) async throws -> UploadStatus {
        let url = URL(string: "\(baseURL)/video/v1/uploads/\(id)")!
        var request = URLRequest(url: url)
        request.setValue(authHeader(), forHTTPHeaderField: "Authorization")

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(MuxUploadResponse.self, from: data)

        return UploadStatus(status: response.data.status, assetId: response.data.assetId)
    }

    func getAsset(id: String) async throws -> AssetStatus {
        let url = URL(string: "\(baseURL)/video/v1/assets/\(id)")!
        var request = URLRequest(url: url)
        request.setValue(authHeader(), forHTTPHeaderField: "Authorization")

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(MuxAssetResponse.self, from: data)

        return AssetStatus(status: response.data.status, playbackIds: response.data.playbackIds, tracks: response.data.tracks)
    }
    // MARK: - Robots API

    func createSummarizeJob(assetId: String, tone: String = "neutral") async throws -> RobotsJob {
        let url = URL(string: "\(baseURL)/robots/v1/jobs/summarize")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RobotsJobRequest(parameters: RobotsSummarizeParameters(assetId: assetId, tone: tone))
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse

        guard let statusCode = httpResponse?.statusCode, (200...299).contains(statusCode) else {
            let statusCode = httpResponse?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MuxAPIError.requestFailed(statusCode: statusCode, body: body)
        }

        return try JSONDecoder().decode(RobotsJobResponse.self, from: data).data
    }

    func getSummarizeJob(jobId: String) async throws -> RobotsJob {
        let url = URL(string: "\(baseURL)/robots/v1/jobs/summarize/\(jobId)")!
        var request = URLRequest(url: url)
        request.setValue(authHeader(), forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse

        guard let statusCode = httpResponse?.statusCode, (200...299).contains(statusCode) else {
            let statusCode = httpResponse?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MuxAPIError.requestFailed(statusCode: statusCode, body: body)
        }

        return try JSONDecoder().decode(RobotsJobResponse.self, from: data).data
    }
}

enum MuxAPIError: LocalizedError {
    case requestFailed(statusCode: Int, body: String)
    case uploadFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let code, let body):
            return "Mux API request failed (\(code)): \(body)"
        case .uploadFailed(let code):
            return "File upload failed with status \(code)"
        }
    }
}

private class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    let totalBytes: Int64
    let onProgress: (Double) -> Void

    init(totalBytes: Int64, onProgress: @escaping (Double) -> Void) {
        self.totalBytes = totalBytes
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progress = Double(totalBytesSent) / Double(max(totalBytes, 1))
        DispatchQueue.main.async {
            self.onProgress(min(progress, 1.0))
        }
    }
}
