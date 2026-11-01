//
//  StudioSession.swift
//  AI Music Studio
//

import Foundation

struct StudioSession: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var tracks: [Track]
    var tempoBPM: Int
    var drumPattern: DrumPattern
    var lastEdited: Date

    init(
        id: UUID = UUID(),
        name: String,
        tracks: [Track] = [],
        tempoBPM: Int = 120,
        drumPattern: DrumPattern = DrumPattern(),
        lastEdited: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.tempoBPM = tempoBPM
        self.drumPattern = drumPattern
        self.lastEdited = lastEdited
    }
}

struct StudioSessionStore: Equatable {
    let sessions: [StudioSession]
    let activeSessionID: UUID
}

enum StudioSessionStorage {
    private static let sessionsKey = "studio.sessions"
    private static let activeSessionKey = "studio.activeSessionID"

    static func load() -> StudioSessionStore {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: sessionsKey),
           let sessions = try? JSONDecoder().decode([StudioSession].self, from: data),
           !sessions.isEmpty {
            let savedID = defaults.string(forKey: activeSessionKey).flatMap(UUID.init(uuidString:))
            let activeID = sessions.first(where: { $0.id == savedID })?.id ?? sessions[0].id
            return StudioSessionStore(sessions: sessions, activeSessionID: activeID)
        }

        let legacyTracks = TrackStorage.loadTracks()
        let legacyTempo = defaults.object(forKey: "studio.sessionTempoBPM") as? Int ?? 120
        let legacyPattern: DrumPattern
        if let data = defaults.data(forKey: "studio.808DrumPattern"),
           let decoded = try? JSONDecoder().decode(DrumPattern.self, from: data) {
            legacyPattern = decoded
        } else {
            legacyPattern = DrumPattern()
        }

        let migrated = StudioSession(
            name: "Untitled Session",
            tracks: legacyTracks,
            tempoBPM: min(200, max(60, legacyTempo)),
            drumPattern: legacyPattern
        )
        save(sessions: [migrated], activeSessionID: migrated.id)
        return StudioSessionStore(sessions: [migrated], activeSessionID: migrated.id)
    }

    static func save(sessions: [StudioSession], activeSessionID: UUID) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: sessionsKey)
        UserDefaults.standard.set(activeSessionID.uuidString, forKey: activeSessionKey)
    }
}
