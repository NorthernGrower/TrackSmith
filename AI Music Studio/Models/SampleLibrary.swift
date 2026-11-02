//
//  SampleLibrary.swift
//  AI Music Studio
//

import AVFoundation
import Foundation

/// One audio file stored in the app's own sample folder.
struct SampleLibraryItem: Identifiable, Equatable, Sendable {
    /// The stored file name, unique inside the app's audio folder.
    let id: String
    let name: String
    let url: URL
    let duration: TimeInterval

    var formatLabel: String {
        let extensionName = url.pathExtension.uppercased()
        return extensionName.isEmpty ? "AUDIO" : extensionName
    }
}

/// Finds the audio the app keeps on device for the sample library.
enum SampleLibrary {
    private static let audioExtensions: Set<String> = ["wav", "caf", "aif", "aiff", "m4a", "mp3"]

    /// Every audio file in the app's sample folder, sorted by name.
    static func scan(directory: URL = TrackStorage.stemsDirectory) -> [SampleLibraryItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .map { url in
                SampleLibraryItem(
                    id: url.lastPathComponent,
                    name: displayName(forFileName: url.lastPathComponent),
                    url: url,
                    duration: duration(of: url)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Reads a sound's length without loading its audio.
    private static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url),
              file.processingFormat.sampleRate > 0 else { return 0 }
        return TimeInterval(file.length) / file.processingFormat.sampleRate
    }

    /// Turns a stored file name into a readable sound name.
    static func displayName(forFileName fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        var name = base

        if base.hasPrefix("stem-") {
            let rest = base.dropFirst("stem-".count)
            if let dash = rest.firstIndex(of: "-") {
                name = String(rest[rest.index(after: dash)...])
            } else {
                name = String(rest)
            }
        }

        name = strippingImportPrefix(from: name)
        name = name.replacingOccurrences(of: "-", with: " ")
        name = name.replacingOccurrences(of: "_", with: " ")
        name = name.trimmingCharacters(in: .whitespaces)
        while name.contains("  ") {
            name = name.replacingOccurrences(of: "  ", with: " ")
        }

        guard !name.isEmpty else { return "Untitled Sound" }
        return name == name.lowercased() ? name.capitalized : name
    }

    /// Drops the identifier the importer adds when a file name is already taken.
    private static func strippingImportPrefix(from name: String) -> String {
        guard name.count > 9 else { return name }
        let separator = name[name.index(name.startIndex, offsetBy: 8)]
        guard separator == "_" || separator == "-" else { return name }

        let prefix = name.prefix(8)
        guard prefix.allSatisfy({ $0.isHexDigit }) else { return name }
        return String(name.dropFirst(9))
    }
}
