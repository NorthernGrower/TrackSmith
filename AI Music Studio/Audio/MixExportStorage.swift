//
//  MixExportStorage.swift
//  AI Music Studio
//

import AVFoundation
import Foundation

enum MixExportKind: String, Codable, CaseIterable, Hashable {
    case mix
    case stem
    case stemArchive
    case unclassified

    var title: String {
        switch self {
        case .mix: return "Mix"
        case .stem: return "Stem"
        case .stemArchive: return "Stem Archive"
        case .unclassified: return "Audio Export"
        }
    }
}

private struct MixExportMetadata: Codable {
    let kind: MixExportKind
    let sessionName: String
}

struct MixExport: Identifiable, Equatable {
    let url: URL
    let createdAt: Date
    let duration: TimeInterval
    let kind: MixExportKind
    let sessionName: String?

    var id: String { url.path }

    var name: String {
        url.deletingPathExtension().lastPathComponent
    }
}

struct MixExportArchive: Identifiable, Equatable {
    let url: URL
    let createdAt: Date
    let sessionName: String?

    var id: String { url.path }

    var name: String {
        url.deletingPathExtension().lastPathComponent
    }
}

enum MixExportStorageError: LocalizedError {
    case archiveNotFound
    case invalidArchiveName
    case archiveNameInUse

    var errorDescription: String? {
        switch self {
        case .archiveNotFound:
            return "This stem archive could not be found."
        case .invalidArchiveName:
            return "Enter a valid archive name."
        case .archiveNameInUse:
            return "An archive with that name already exists. Choose another name."
        }
    }
}

enum MixExportStorage {
    private static let metadataFileName = ".export-metadata.json"

    static var exportsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("Mix Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var metadataURL: URL {
        exportsDirectory.appendingPathComponent(metadataFileName)
    }

    /// A unique export file named after the session or stem, safe for the file system.
    static func exportURL(name: String? = nil, fileExtension: String) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let safeName = (name ?? "Mix")
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: allowed.inverted)
            .joined()
        let base = safeName.isEmpty ? "Mix" : safeName

        return exportsDirectory.appendingPathComponent("\(base)-\(timestamp)-\(UUID().uuidString.prefix(6)).\(fileExtension)")
    }

    /// Persists the export's type and originating session beside the files it describes.
    static func registerExport(at url: URL, kind: MixExportKind, sessionName: String) {
        var metadata = loadMetadata()
        metadata[url.lastPathComponent] = MixExportMetadata(kind: kind, sessionName: sessionName)
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    static func loadExports() -> [MixExport] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: exportsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let metadata = loadMetadata()
        return urls.compactMap { url in
            guard ["wav", "m4a"].contains(url.pathExtension.lowercased()),
                  let file = try? AVAudioFile(forReading: url),
                  file.processingFormat.sampleRate > 0 else { return nil }
            let attributes = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let date = attributes?.contentModificationDate ?? .distantPast
            let duration = TimeInterval(file.length) / file.processingFormat.sampleRate
            let record = metadata[url.lastPathComponent]
            return MixExport(
                url: url,
                createdAt: date,
                duration: duration,
                kind: record?.kind ?? .unclassified,
                sessionName: record?.sessionName
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    static func loadStemArchives() -> [MixExportArchive] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: exportsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let metadata = loadMetadata()
        return urls.compactMap { url in
            guard url.pathExtension.lowercased() == "zip" else { return nil }
            let attributes = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return MixExportArchive(
                url: url,
                createdAt: attributes?.contentModificationDate ?? .distantPast,
                sessionName: metadata[url.lastPathComponent]?.sessionName
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    static func renameStemArchive(_ archive: MixExportArchive, to proposedName: String) throws -> MixExportArchive {
        guard archive.url.pathExtension.lowercased() == "zip" else {
            throw MixExportStorageError.archiveNotFound
        }

        var baseName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        while baseName.lowercased().hasSuffix(".zip") {
            baseName = String(baseName.dropLast(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        baseName = baseName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .components(separatedBy: .controlCharacters)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let safeBaseName = String(baseName.prefix(120))
        guard !safeBaseName.isEmpty else { throw MixExportStorageError.invalidArchiveName }

        let fileManager = FileManager.default
        let sourceURL = archive.url.standardizedFileURL
        let destinationURL = exportsDirectory
            .appendingPathComponent("\(safeBaseName).zip", isDirectory: false)
            .standardizedFileURL
        guard sourceURL.deletingLastPathComponent() == exportsDirectory.standardizedFileURL,
              fileManager.fileExists(atPath: sourceURL.path) else {
            throw MixExportStorageError.archiveNotFound
        }
        if sourceURL.path == destinationURL.path { return archive }

        let isCaseOnlyRename = sourceURL.path.caseInsensitiveCompare(destinationURL.path) == .orderedSame
        if fileManager.fileExists(atPath: destinationURL.path) && !isCaseOnlyRename {
            throw MixExportStorageError.archiveNameInUse
        }

        var metadata = loadMetadata()
        let existingMetadata = metadata.removeValue(forKey: sourceURL.lastPathComponent)
        if let existingMetadata {
            metadata[destinationURL.lastPathComponent] = existingMetadata
        }

        try moveArchiveFile(from: sourceURL, to: destinationURL, caseOnly: isCaseOnlyRename)
        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            try? moveArchiveFile(from: destinationURL, to: sourceURL, caseOnly: isCaseOnlyRename)
            throw error
        }

        return MixExportArchive(
            url: destinationURL,
            createdAt: archive.createdAt,
            sessionName: archive.sessionName
        )
    }

    private static func moveArchiveFile(from sourceURL: URL, to destinationURL: URL, caseOnly: Bool) throws {
        let fileManager = FileManager.default
        guard caseOnly else {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            return
        }

        let temporaryURL = exportsDirectory.appendingPathComponent("archive-rename-\(UUID().uuidString).tmp")
        try fileManager.moveItem(at: sourceURL, to: temporaryURL)
        do {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? fileManager.moveItem(at: temporaryURL, to: sourceURL)
            throw error
        }
    }

    private static func loadMetadata() -> [String: MixExportMetadata] {
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode([String: MixExportMetadata].self, from: data) else {
            return [:]
        }
        return metadata
    }
}
