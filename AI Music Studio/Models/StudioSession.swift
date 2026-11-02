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
    /// Start of the timeline section that repeats during playback.
    var loopStart: TimeInterval
    /// End of the timeline section that repeats during playback.
    var loopEnd: TimeInterval
    var isLoopEnabled: Bool
    /// Overall output level of the master strip, from 0 to 1.
    var masterVolume: Float
    var masterEffects: MasterEffectsSettings
    var sections: [SongSection]
    var isMetronomeEnabled: Bool
    /// Click level of the metronome and count-in, from 0 to 1.
    var metronomeLevel: Float
    var isCountInEnabled: Bool
    var lastEdited: Date

    init(
        id: UUID = UUID(),
        name: String,
        tracks: [Track] = [],
        tempoBPM: Int = 120,
        drumPattern: DrumPattern = DrumPattern(),
        loopStart: TimeInterval = 0,
        loopEnd: TimeInterval = 0,
        isLoopEnabled: Bool = false,
        masterVolume: Float = 1,
        masterEffects: MasterEffectsSettings = MasterEffectsSettings(),
        sections: [SongSection] = [],
        isMetronomeEnabled: Bool = false,
        metronomeLevel: Float = 0.7,
        isCountInEnabled: Bool = false,
        lastEdited: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.tempoBPM = tempoBPM
        self.drumPattern = drumPattern
        self.loopStart = loopStart
        self.loopEnd = loopEnd
        self.isLoopEnabled = isLoopEnabled
        self.masterVolume = masterVolume
        self.masterEffects = masterEffects
        self.sections = sections
        self.isMetronomeEnabled = isMetronomeEnabled
        self.metronomeLevel = metronomeLevel
        self.isCountInEnabled = isCountInEnabled
        self.lastEdited = lastEdited
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case tracks
        case tempoBPM
        case drumPattern
        case loopStart
        case loopEnd
        case isLoopEnabled
        case masterVolume
        case masterEffects
        case sections
        case isMetronomeEnabled
        case metronomeLevel
        case isCountInEnabled
        case lastEdited
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Session"
        tracks = try values.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        tempoBPM = try values.decodeIfPresent(Int.self, forKey: .tempoBPM) ?? 120
        drumPattern = try values.decodeIfPresent(DrumPattern.self, forKey: .drumPattern) ?? DrumPattern()
        loopStart = try values.decodeIfPresent(TimeInterval.self, forKey: .loopStart) ?? 0
        loopEnd = try values.decodeIfPresent(TimeInterval.self, forKey: .loopEnd) ?? 0
        isLoopEnabled = try values.decodeIfPresent(Bool.self, forKey: .isLoopEnabled) ?? false
        masterVolume = try values.decodeIfPresent(Float.self, forKey: .masterVolume) ?? 1
        masterEffects = try values.decodeIfPresent(MasterEffectsSettings.self, forKey: .masterEffects) ?? MasterEffectsSettings()
        sections = try values.decodeIfPresent([SongSection].self, forKey: .sections) ?? []
        isMetronomeEnabled = try values.decodeIfPresent(Bool.self, forKey: .isMetronomeEnabled) ?? false
        metronomeLevel = try values.decodeIfPresent(Float.self, forKey: .metronomeLevel) ?? 0.7
        isCountInEnabled = try values.decodeIfPresent(Bool.self, forKey: .isCountInEnabled) ?? false
        lastEdited = try values.decodeIfPresent(Date.self, forKey: .lastEdited) ?? Date()
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
