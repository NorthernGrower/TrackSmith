//
//  SongSection.swift
//  AI Music Studio
//

import Foundation

/// A named part of the song marked on the timeline ruler.
struct SongSection: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var time: TimeInterval

    init(id: UUID = UUID(), name: String, time: TimeInterval) {
        self.id = id
        self.name = name
        self.time = time
    }

    static func suggestedName(existing: [SongSection]) -> String {
        let base = ["Intro", "Verse", "Chorus", "Bridge", "Outro"]
        let used = Set(existing.map { $0.name.lowercased() })

        if let free = base.first(where: { !used.contains($0.lowercased()) }) {
            return free
        }

        var index = existing.count + 1
        while used.contains("section \(index)") {
            index += 1
        }
        return "Section \(index)"
    }
}
