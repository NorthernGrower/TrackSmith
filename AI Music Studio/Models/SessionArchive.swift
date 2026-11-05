//
//  SessionArchive.swift
//  AI Music Studio
//

import Foundation

/// One audio file carried inside a session backup.
struct SessionArchiveFile: Codable, Equatable {
    /// Stored name inside the app's Stems folder.
    var fileName: String
    var byteCount: Int
}

/// What a session backup holds: the session itself plus its audio files.
struct SessionArchiveManifest: Codable {
    var formatVersion = 1
    var appName = "AI Music Studio"
    var exportedAt = Date()
    var session: StudioSession
    var files: [SessionArchiveFile]
}

/// A quick look at a backup before importing it.
struct SessionArchiveSummary {
    let sessionName: String
    let trackCount: Int
    let fileCount: Int
    let byteCount: Int
    let exportedAt: Date
}

enum SessionArchiveError: LocalizedError {
    case notAnArchive
    case unsupportedVersion
    case corrupt

    var errorDescription: String? {
        switch self {
        case .notAnArchive:
            return "That file is not an AI Music Studio session backup."
        case .unsupportedVersion:
            return "This backup was made by a newer version of the studio."
        case .corrupt:
            return "The session backup is damaged and could not be opened."
        }
    }
}

/// Packs a whole session and its audio into one portable `.aimsession` file
/// and restores it again on this or another device.
enum SessionArchive {
    static let fileExtension = "aimsession"
    private static let magic = Data("AIMSESSION1".utf8)
    private static let headerLengthSize = 8

    static var backupsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("Session Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A readable file name for a session backup.
    static func suggestedFileName(for sessionName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let safe = sessionName
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: allowed.inverted)
            .joined()
        let base = safe.isEmpty ? "Session" : safe

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = formatter.string(from: Date())
        return "\(base)-\(stamp).\(fileExtension)"
    }

    static func exportURL(for sessionName: String) -> URL {
        backupsDirectory.appendingPathComponent(suggestedFileName(for: sessionName))
    }

    /// Reads only the header, so a name collision can be checked before importing.
    static func summary(at url: URL) throws -> SessionArchiveSummary {
        let header = try readHeader(at: url)
        return SessionArchiveSummary(
            sessionName: header.manifest.session.name,
            trackCount: header.manifest.session.tracks.count,
            fileCount: header.manifest.files.count,
            byteCount: header.manifest.files.reduce(0) { $0 + $1.byteCount },
            exportedAt: header.manifest.exportedAt
        )
    }

    /// Writes the session and every audio file it references to one archive.
    static func export(
        session: StudioSession,
        to url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let names = audioFileNames(in: session)
        var entries: [(name: String, url: URL, size: Int)] = []

        for name in names {
            let fileURL = TrackStorage.url(forFileName: name)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let size = (attributes[.size] as? NSNumber)?.intValue,
                  size > 0 else { continue }
            entries.append((name, fileURL, size))
        }

        let files = entries.map { SessionArchiveFile(fileName: $0.name, byteCount: $0.size) }
        let manifest = SessionArchiveManifest(exportedAt: Date(), session: session, files: files)
        let header = try JSONEncoder().encode(manifest)
        let totalBytes = max(1, entries.reduce(0) { $0 + $1.size })

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close() }

        try output.write(contentsOf: magic)
        var length = UInt64(header.count).littleEndian
        try output.write(contentsOf: withUnsafeBytes(of: &length) { Data($0) })
        try output.write(contentsOf: header)

        var written = 0
        progress(0)

        for entry in entries {
            let input = try FileHandle(forReadingFrom: entry.url)
            defer { try? input.close() }

            while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
                written += chunk.count
                progress(Double(written) / Double(totalBytes))
            }
        }

        progress(1)
    }

    /// Unpacks an archive, copying its audio into the app's audio folder under
    /// fresh names and remapping every clip, take and frozen track to them.
    static func importSession(
        from url: URL,
        renameTo name: String,
        progress: @escaping @Sendable (Double) -> Void
    ) throws -> StudioSession {
        let header = try readHeader(at: url)
        guard header.manifest.formatVersion <= 1 else { throw SessionArchiveError.unsupportedVersion }

        let manifest = header.manifest
        let totalBytes = max(1, manifest.files.reduce(0) { $0 + $1.byteCount })
        var mapping: [String: String] = [:]
        var created: [URL] = []

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: header.payloadOffset)

        var written = 0
        progress(0)

        do {
            for file in manifest.files {
                let newName = uniqueStoredName(for: file.fileName)
                let destination = TrackStorage.url(forFileName: newName)
                FileManager.default.createFile(atPath: destination.path, contents: nil)
                created.append(destination)

                let output = try FileHandle(forWritingTo: destination)
                defer { try? output.close() }

                var remaining = file.byteCount
                while remaining > 0 {
                    let chunkSize = min(1_048_576, remaining)
                    guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                        throw SessionArchiveError.corrupt
                    }
                    try output.write(contentsOf: chunk)
                    remaining -= chunk.count
                    written += chunk.count
                    progress(Double(written) / Double(totalBytes))
                }

                mapping[file.fileName] = newName
            }
        } catch {
            for url in created { try? FileManager.default.removeItem(at: url) }
            throw error
        }

        var session = manifest.session
        session.id = UUID()
        session.name = name
        session.lastEdited = Date()

        for index in session.tracks.indices {
            var track = session.tracks[index]
            if let mapped = mapping[track.fileName] {
                track.fileName = mapped
            }
            if let frozen = track.frozenFileName, let mapped = mapping[frozen] {
                track.frozenFileName = mapped
            }
            for clipIndex in track.clips.indices {
                if let mapped = mapping[track.clips[clipIndex].fileName] {
                    track.clips[clipIndex].fileName = mapped
                }
            }
            for takeIndex in track.takes.indices {
                if let mapped = mapping[track.takes[takeIndex].fileName] {
                    track.takes[takeIndex].fileName = mapped
                }
            }
            session.tracks[index] = track
        }

        progress(1)
        return session
    }

    // MARK: - Internals

    private struct Header {
        let manifest: SessionArchiveManifest
        let payloadOffset: UInt64
    }

    private static func readHeader(at url: URL) throws -> Header {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let magicData = try handle.read(upToCount: magic.count),
              magicData == magic else {
            throw SessionArchiveError.notAnArchive
        }
        guard let lengthData = try handle.read(upToCount: headerLengthSize),
              lengthData.count == headerLengthSize else {
            throw SessionArchiveError.corrupt
        }

        var headerLength: UInt64 = 0
        for (index, byte) in lengthData.enumerated() {
            headerLength |= UInt64(byte) << (8 * UInt64(index))
        }
        guard headerLength > 0, headerLength < 50_000_000 else {
            throw SessionArchiveError.corrupt
        }
        guard let headerData = try handle.read(upToCount: Int(headerLength)),
              headerData.count == Int(headerLength) else {
            throw SessionArchiveError.corrupt
        }

        let manifest: SessionArchiveManifest
        do {
            manifest = try JSONDecoder().decode(SessionArchiveManifest.self, from: headerData)
        } catch {
            throw SessionArchiveError.corrupt
        }

        let offset = UInt64(magic.count + headerLengthSize) + headerLength
        return Header(manifest: manifest, payloadOffset: offset)
    }

    private static func audioFileNames(in session: StudioSession) -> [String] {
        var names = Set<String>()
        for track in session.tracks {
            if !track.fileName.isEmpty { names.insert(track.fileName) }
            if let frozen = track.frozenFileName { names.insert(frozen) }
            for clip in track.clips where !clip.fileName.isEmpty { names.insert(clip.fileName) }
            for take in track.takes where !take.fileName.isEmpty { names.insert(take.fileName) }
        }
        return names.sorted()
    }

    private static func uniqueStoredName(for name: String) -> String {
        let fallback = name.isEmpty ? "Audio-\(UUID().uuidString.prefix(8)).wav" : name
        var candidate = fallback
        while FileManager.default.fileExists(atPath: TrackStorage.url(forFileName: candidate).path) {
            candidate = "\(UUID().uuidString.prefix(8))_\(fallback)"
        }
        return candidate
    }
}
