//
//  MixExportStorage.swift
//  AI Music Studio
//

import AVFoundation
import Foundation

struct MixExport: Identifiable, Equatable {
    let url: URL
    let createdAt: Date
    let duration: TimeInterval

    var id: String { url.path }

    var name: String {
        url.deletingPathExtension().lastPathComponent
    }
}

enum MixExportStorage {
    static var exportsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("Mix Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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

    static func loadExports() -> [MixExport] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: exportsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard ["wav", "m4a"].contains(url.pathExtension.lowercased()),
                  let file = try? AVAudioFile(forReading: url),
                  file.processingFormat.sampleRate > 0 else { return nil }
            let attributes = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let date = attributes?.contentModificationDate ?? .distantPast
            let duration = TimeInterval(file.length) / file.processingFormat.sampleRate
            return MixExport(url: url, createdAt: date, duration: duration)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }
}
