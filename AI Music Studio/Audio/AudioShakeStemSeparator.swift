//
//  AudioShakeStemSeparator.swift
//  AI Music Studio
//

import AVFoundation
import Foundation

struct StemSeparationSource: Sendable {
    let fileURL: URL
    let originalFileName: String
    let duration: TimeInterval
}

enum AudioShakeStemTarget: String, CaseIterable, Hashable, Identifiable, Sendable {
    case vocals
    case drums
    case bass
    case guitar
    case keys
    case residual
    case piano
    case strings
    case wind
    case drumKit

    var id: String { rawValue }

    var modelName: String {
        switch self {
        case .drumKit: return "drum_kit"
        default: return rawValue
        }
    }

    var title: String {
        switch self {
        case .drumKit: return "Drum Kit"
        case .residual: return "Residual"
        default: return rawValue.capitalized
        }
    }

    var symbolName: String {
        switch self {
        case .vocals: return "mic.fill"
        case .drums: return "drum.fill"
        case .bass: return "guitars.fill"
        case .guitar: return "guitar.fill"
        case .keys, .piano: return "pianokeys"
        case .residual: return "waveform"
        case .strings: return "guitars"
        case .wind: return "wind"
        case .drumKit: return "music.note.list"
        }
    }

    var isAdditional: Bool {
        [.piano, .strings, .wind, .drumKit].contains(self)
    }

    static let defaultSelection: Set<AudioShakeStemTarget> = [
        .vocals, .drums, .bass, .guitar, .keys, .residual
    ]

    static func displayName(model: String, outputName: String?) -> String {
        guard model == "drum_kit",
              let outputName,
              !outputName.isEmpty else {
            switch model {
            case "vocals_lead": return "Lead Vocals"
            case "vocals_backing": return "Backing Vocals"
            case "guitar_electric": return "Electric Guitar"
            case "guitar_acoustic": return "Acoustic Guitar"
            case "drum_kit": return "Drum Kit"
            case "residual": return "Residual"
            default: return model.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }

        let output = URL(fileURLWithPath: outputName)
            .deletingPathExtension()
            .lastPathComponent
            .lowercased()
        let parts = ["kick", "snare", "toms", "hi-hat", "hihat", "cymbals", "percussion"]
        if let part = parts.first(where: { output.contains($0) }) {
            return part == "hihat" ? "Hi-Hat" : part.capitalized
        }
        return output.isEmpty ? "Drum Kit" : output.capitalized
    }
}

struct AudioShakeSeparationResult: Sendable {
    let stems: [ImportedStem]
    let failures: [String]
}

enum AudioShakeStemSeparatorError: LocalizedError {
    case missingAPIKey
    case unsupportedAudioFormat
    case fileTooLarge
    case invalidResponse
    case requestFailed(String)
    case taskTimedOut
    case noResults(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your AudioShake API key before separating a song."
        case .unsupportedAudioFormat:
            return "This audio format is not supported by AudioShake. Try WAV, MP3, M4A, AIFF, or FLAC."
        case .fileTooLarge:
            return "AudioShake accepts files up to 5 GB."
        case .invalidResponse:
            return "AudioShake returned an unexpected response. Please try again."
        case .requestFailed(let message):
            return message
        case .taskTimedOut:
            return "AudioShake is taking longer than expected. Your source song is still saved on this device."
        case .noResults(let message):
            return message.isEmpty ? "AudioShake did not return any stems." : message
        }
    }
}

enum AudioShakeStemSeparator {
    static let apiKeyName = "STEM_SEPARATION_API_KEY"
    private static let apiBaseURL = URL(string: "https://api.audioshake.ai")!
    private static let maximumUploadBytes: Int64 = 5 * 1_024 * 1_024 * 1_024
    private static let uploadChunkSize = 1_048_576

    private struct AssetResponse: Decodable {
        let id: String
    }

    private struct CreateTaskRequest: Encodable {
        struct Target: Encodable {
            let model: String
            let formats: [String]
        }

        let assetId: String
        let targets: [Target]
    }

    private struct TaskResponse: Decodable {
        struct Target: Decodable {
            struct Output: Decodable {
                let name: String?
                let format: String?
                let link: String?
            }

            struct Failure: Decodable {
                let message: String?

                private enum CodingKeys: String, CodingKey {
                    case message
                }

                init(from decoder: Decoder) throws {
                    if let container = try? decoder.singleValueContainer(),
                       let message = try? container.decode(String.self) {
                        self.message = message
                        return
                    }
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    message = try container.decodeIfPresent(String.self, forKey: .message)
                }
            }

            let model: String
            let status: String
            let output: [Output]?
            let error: Failure?
        }

        let id: String
        let targets: [Target]?
    }

    private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let onProgress: @Sendable (Double) -> Void

        init(onProgress: @escaping @Sendable (Double) -> Void) {
            self.onProgress = onProgress
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didSendBodyData bytesSent: Int64,
            totalBytesSent: Int64,
            totalBytesExpectedToSend: Int64
        ) {
            guard totalBytesExpectedToSend > 0 else { return }
            onProgress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
        }
    }

    static func prepareSource(from sourceURL: URL) async throws -> StemSeparationSource {
        try await Task.detached(priority: .userInitiated) {
            let originalFileName = sourceURL.lastPathComponent
            let imported = try TrackStorage.importFile(at: sourceURL)
            let localURL = TrackStorage.url(forFileName: imported.storedName)
            let audioFile = try AVAudioFile(forReading: localURL)
            let sampleRate = audioFile.processingFormat.sampleRate
            guard sampleRate > 0 else { throw AudioShakeStemSeparatorError.unsupportedAudioFormat }
            let duration = TimeInterval(audioFile.length) / sampleRate
            guard duration > 0 else { throw AudioShakeStemSeparatorError.unsupportedAudioFormat }
            return StemSeparationSource(
                fileURL: localURL,
                originalFileName: originalFileName,
                duration: duration
            )
        }.value
    }

    static func separate(
        source: StemSeparationSource,
        targets: Set<AudioShakeStemTarget>,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async throws -> AudioShakeSeparationResult {
        guard let apiKey = ApiKeyManager.shared.get(key: apiKeyName), !apiKey.isEmpty else {
            throw AudioShakeStemSeparatorError.missingAPIKey
        }
        guard !targets.isEmpty else {
            throw AudioShakeStemSeparatorError.noResults("Choose at least one stem to separate.")
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: source.fileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize <= maximumUploadBytes else { throw AudioShakeStemSeparatorError.fileTooLarge }
        guard let mimeType = mimeType(for: source.fileURL.pathExtension) else {
            throw AudioShakeStemSeparatorError.unsupportedAudioFormat
        }

        progress("Preparing secure upload…", 0.02)
        let assetID = try await uploadAsset(
            from: source.fileURL,
            fileName: source.fileURL.lastPathComponent,
            mimeType: mimeType,
            apiKey: apiKey,
            progress: progress
        )

        progress("Starting AI separation…", 0.12)
        let requestBody = CreateTaskRequest(
            assetId: assetID,
            targets: targets.sorted { $0.rawValue < $1.rawValue }.map {
                CreateTaskRequest.Target(model: $0.modelName, formats: ["wav"])
            }
        )
        var createRequest = URLRequest(url: apiBaseURL.appendingPathComponent("tasks"))
        createRequest.httpMethod = "POST"
        createRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createRequest.httpBody = try JSONEncoder().encode(requestBody)
        createRequest.timeoutInterval = 60

        let initialTaskData = try await send(createRequest)
        var task = try JSONDecoder().decode(TaskResponse.self, from: initialTaskData)
        guard !task.id.isEmpty else { throw AudioShakeStemSeparatorError.invalidResponse }

        let taskStartedAt = Date()
        let taskTimeout: TimeInterval = 30 * 60
        while !allTargetsFinished(task.targets) {
            try Task.checkCancellation()
            guard Date().timeIntervalSince(taskStartedAt) < taskTimeout else {
                throw AudioShakeStemSeparatorError.taskTimedOut
            }
            let finishedCount = task.targets?.filter(isFinished).count ?? 0
            let targetCount = max(1, targets.count)
            progress(
                "AI separating · \(finishedCount) of \(targetCount) stems…",
                0.15 + 0.65 * Double(finishedCount) / Double(targetCount)
            )
            try await Task.sleep(for: .seconds(5))

            var pollRequest = URLRequest(url: apiBaseURL.appendingPathComponent("tasks/\(task.id)"))
            pollRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            pollRequest.timeoutInterval = 60
            task = try JSONDecoder().decode(TaskResponse.self, from: await send(pollRequest))
        }

        guard let finishedTargets = task.targets else { throw AudioShakeStemSeparatorError.invalidResponse }
        var stems: [ImportedStem] = []
        var failures: [String] = []
        let outputCount = max(1, finishedTargets.reduce(0) { $0 + ($1.output?.count ?? 0) })
        var downloadedCount = 0

        for target in finishedTargets {
            let targetName = AudioShakeStemTarget.displayName(model: target.model, outputName: nil)
            guard target.status.lowercased() == "completed" else {
                failures.append("\(targetName): \(target.error?.message ?? "Separation failed")")
                continue
            }
            guard let outputs = target.output, !outputs.isEmpty else {
                failures.append("\(targetName): AudioShake returned no output file")
                continue
            }

            for output in outputs {
                guard let link = output.link, let downloadURL = URL(string: link), downloadURL.scheme == "https" else {
                    failures.append("\(targetName): AudioShake returned an invalid download link")
                    continue
                }

                do {
                    var downloadRequest = URLRequest(url: downloadURL)
                    downloadRequest.timeoutInterval = 600
                    let (temporaryURL, response) = try await URLSession.shared.download(for: downloadRequest)
                    try validate(response: response, data: Data())
                    let displayName = AudioShakeStemTarget.displayName(model: target.model, outputName: output.name)
                    let destination = TrackStorage.uniqueStemURL(baseName: displayName, fileExtension: "wav")
                    try FileManager.default.moveItem(at: temporaryURL, to: destination)
                    stems.append(ImportedStem(name: displayName, storedName: destination.lastPathComponent))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failures.append("\(targetName): \(error.localizedDescription)")
                }

                downloadedCount += 1
                progress(
                    "Saving stems · \(downloadedCount) of \(outputCount)…",
                    0.82 + 0.16 * Double(downloadedCount) / Double(outputCount)
                )
            }
        }

        guard !stems.isEmpty else {
            throw AudioShakeStemSeparatorError.noResults(failures.joined(separator: "\n"))
        }
        progress("Stems ready.", 1)
        return AudioShakeSeparationResult(stems: stems, failures: failures)
    }

    private static func uploadAsset(
        from sourceURL: URL,
        fileName: String,
        mimeType: String,
        apiKey: String,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async throws -> String {
        let boundary = "AudioShakeBoundary-\(UUID().uuidString)"
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audioshake-upload-\(UUID().uuidString).multipart")
        guard FileManager.default.createFile(atPath: bodyURL.path, contents: nil) else {
            throw AudioShakeStemSeparatorError.requestFailed("The upload could not be prepared on this device.")
        }
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        let output = try FileHandle(forWritingTo: bodyURL)
        defer { try? output.close() }
        let safeFileName = fileName
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\"", with: "")
        let header = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFileName)\"\r\n"
            + "Content-Type: \(mimeType)\r\n\r\n"
        try output.write(contentsOf: Data(header.utf8))

        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: uploadChunkSize), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: apiBaseURL.appendingPathComponent("assets"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 * 60

        let uploadDelegate = UploadProgressDelegate { fraction in
            progress("Uploading song…", 0.02 + 0.10 * fraction)
        }
        let (data, response) = try await URLSession.shared.upload(
            for: request,
            fromFile: bodyURL,
            delegate: uploadDelegate
        )
        try validate(response: response, data: data)
        let asset = try JSONDecoder().decode(AssetResponse.self, from: data)
        guard !asset.id.isEmpty else { throw AudioShakeStemSeparatorError.invalidResponse }
        return asset.id
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let serviceMessage = errorMessage(from: data)
            throw AudioShakeStemSeparatorError.requestFailed(
                serviceMessage.isEmpty
                    ? "AudioShake request failed (HTTP \(status)). Check your API key and credits, then try again."
                    : serviceMessage
            )
        }
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if let message = object["message"] as? String { return message }
        if let detail = object["detail"] as? String { return detail }
        if let error = object["error"] as? String { return error }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return ""
    }

    private static func allTargetsFinished(_ targets: [TaskResponse.Target]?) -> Bool {
        guard let targets, !targets.isEmpty else { return false }
        return targets.allSatisfy(isFinished)
    }

    private static func isFinished(_ target: TaskResponse.Target) -> Bool {
        ["completed", "error"].contains(target.status.lowercased())
    }

    private static func mimeType(for fileExtension: String) -> String? {
        switch fileExtension.lowercased() {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "aac": return "audio/aac"
        case "aif", "aiff": return "audio/aiff"
        case "flac": return "audio/flac"
        default: return nil
        }
    }

}
