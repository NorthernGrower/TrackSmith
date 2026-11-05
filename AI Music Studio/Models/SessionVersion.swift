//
//  SessionVersion.swift
//  AI Music Studio
//

import Foundation

/// An autosaved snapshot of a session, kept on device so earlier work can be
/// previewed, restored or opened as a copy.
struct SessionVersion: Identifiable, Codable, Equatable {
    var id: UUID
    var sessionID: UUID
    var createdAt: Date
    var name: String
    var trackCount: Int
    var duration: TimeInterval
    var tempoBPM: Int
    var sectionCount: Int
    var session: StudioSession
}

enum SessionVersionStore {
    /// How many snapshots are kept for each session before the oldest go.
    static let maximumPerSession = 30

    private static var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("Session Versions", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("versions.json")
    }

    static func load() -> [SessionVersion] {
        guard let data = try? Data(contentsOf: fileURL),
              let versions = try? JSONDecoder().decode([SessionVersion].self, from: data) else {
            return []
        }
        return versions.sorted { $0.createdAt > $1.createdAt }
    }

    static func save(_ versions: [SessionVersion]) {
        guard let data = try? JSONEncoder().encode(versions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension StudioSession {
    /// The last moment anything in the arrangement plays.
    var arrangementDuration: TimeInterval {
        var end: TimeInterval = 0
        for track in tracks {
            for clip in track.playbackClips {
                let playable = min(clip.duration, max(0, clip.sourceDuration - clip.sourceStartTime))
                end = max(end, clip.startTime + playable)
            }
            for note in track.playedNotes(tempoBPM: tempoBPM) {
                end = max(end, note.endTime)
            }
        }
        return end
    }
}
