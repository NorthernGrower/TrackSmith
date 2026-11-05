//
//  StudioSession.swift
//  AI Music Studio
//

import Foundation

struct StudioSession: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    /// Id of the template the session was started from, when it came from one.
    var templateID: String?
    var tracks: [Track]
    /// Buses that link several tracks to one fader, mute and solo.
    var groups: [TrackGroup]
    var tempoBPM: Int
    var drumPattern: DrumPattern
    /// Kit that shapes the synthesized drum voices of this session.
    var drumKit: DrumKit
    /// Start of the timeline section that repeats during playback.
    var loopStart: TimeInterval
    /// End of the timeline section that repeats during playback.
    var loopEnd: TimeInterval
    var isLoopEnabled: Bool
    /// Overall output level of the master strip, from 0 to 1.
    var masterVolume: Float
    var masterEffects: MasterEffectsSettings
    /// Master EQ, bus compressor and limiter on the whole mix.
    var mastering: MasteringSettings
    /// Shared reverb send bus.
    var auxBusA: AuxBusSettings
    /// Shared delay send bus.
    var auxBusB: AuxBusSettings
    var sections: [SongSection]
    var isMetronomeEnabled: Bool
    /// First moment a punch recording captures.
    var punchIn: TimeInterval
    /// Last moment a punch recording captures.
    var punchOut: TimeInterval
    var isPunchEnabled: Bool
    /// The track a punch recording is armed on.
    var armedTrackID: UUID?
    /// Click level of the metronome and count-in, from 0 to 1.
    var metronomeLevel: Float
    var isCountInEnabled: Bool
    var lastEdited: Date

    init(
        id: UUID = UUID(),
        name: String,
        templateID: String? = nil,
        tracks: [Track] = [],
        groups: [TrackGroup] = [],
        tempoBPM: Int = 120,
        drumPattern: DrumPattern = DrumPattern(),
        drumKit: DrumKit = .studio808,
        loopStart: TimeInterval = 0,
        loopEnd: TimeInterval = 0,
        isLoopEnabled: Bool = false,
        masterVolume: Float = 1,
        masterEffects: MasterEffectsSettings = MasterEffectsSettings(),
        mastering: MasteringSettings = MasteringSettings(),
        auxBusA: AuxBusSettings = .busA,
        auxBusB: AuxBusSettings = .busB,
        sections: [SongSection] = [],
        isMetronomeEnabled: Bool = false,
        punchIn: TimeInterval = 0,
        punchOut: TimeInterval = 0,
        isPunchEnabled: Bool = false,
        armedTrackID: UUID? = nil,
        metronomeLevel: Float = 0.7,
        isCountInEnabled: Bool = false,
        lastEdited: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.templateID = templateID
        self.tracks = tracks
        self.groups = groups
        self.tempoBPM = tempoBPM
        self.drumPattern = drumPattern
        self.drumKit = drumKit
        self.loopStart = loopStart
        self.loopEnd = loopEnd
        self.isLoopEnabled = isLoopEnabled
        self.masterVolume = masterVolume
        self.masterEffects = masterEffects
        self.mastering = mastering
        self.auxBusA = auxBusA
        self.auxBusB = auxBusB
        self.sections = sections
        self.isMetronomeEnabled = isMetronomeEnabled
        self.punchIn = punchIn
        self.punchOut = punchOut
        self.isPunchEnabled = isPunchEnabled
        self.armedTrackID = armedTrackID
        self.metronomeLevel = metronomeLevel
        self.isCountInEnabled = isCountInEnabled
        self.lastEdited = lastEdited
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case templateID
        case tracks
        case groups
        case tempoBPM
        case drumPattern
        case drumKit
        case loopStart
        case loopEnd
        case isLoopEnabled
        case masterVolume
        case masterEffects
        case mastering
        case auxBusA
        case auxBusB
        case sections
        case isMetronomeEnabled
        case punchIn
        case punchOut
        case isPunchEnabled
        case armedTrackID
        case metronomeLevel
        case isCountInEnabled
        case lastEdited
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Session"
        templateID = try values.decodeIfPresent(String.self, forKey: .templateID)
        tracks = try values.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        groups = try values.decodeIfPresent([TrackGroup].self, forKey: .groups) ?? []
        tempoBPM = try values.decodeIfPresent(Int.self, forKey: .tempoBPM) ?? 120
        drumPattern = try values.decodeIfPresent(DrumPattern.self, forKey: .drumPattern) ?? DrumPattern()
        drumKit = try values.decodeIfPresent(DrumKit.self, forKey: .drumKit) ?? .studio808
        loopStart = try values.decodeIfPresent(TimeInterval.self, forKey: .loopStart) ?? 0
        loopEnd = try values.decodeIfPresent(TimeInterval.self, forKey: .loopEnd) ?? 0
        isLoopEnabled = try values.decodeIfPresent(Bool.self, forKey: .isLoopEnabled) ?? false
        masterVolume = try values.decodeIfPresent(Float.self, forKey: .masterVolume) ?? 1
        masterEffects = try values.decodeIfPresent(MasterEffectsSettings.self, forKey: .masterEffects) ?? MasterEffectsSettings()
        mastering = try values.decodeIfPresent(MasteringSettings.self, forKey: .mastering) ?? MasteringSettings()
        auxBusA = try values.decodeIfPresent(AuxBusSettings.self, forKey: .auxBusA) ?? .busA
        auxBusB = try values.decodeIfPresent(AuxBusSettings.self, forKey: .auxBusB) ?? .busB
        sections = try values.decodeIfPresent([SongSection].self, forKey: .sections) ?? []
        isMetronomeEnabled = try values.decodeIfPresent(Bool.self, forKey: .isMetronomeEnabled) ?? false
        punchIn = try values.decodeIfPresent(TimeInterval.self, forKey: .punchIn) ?? 0
        punchOut = try values.decodeIfPresent(TimeInterval.self, forKey: .punchOut) ?? 0
        isPunchEnabled = try values.decodeIfPresent(Bool.self, forKey: .isPunchEnabled) ?? false
        armedTrackID = try values.decodeIfPresent(UUID.self, forKey: .armedTrackID)
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
    private static let houseDemoSeededKey = "studio.houseDemoSeeded"

    static var hasSeededHouseDemo: Bool {
        UserDefaults.standard.bool(forKey: houseDemoSeededKey)
    }

    static func markHouseDemoSeeded() {
        UserDefaults.standard.set(true, forKey: houseDemoSeededKey)
    }

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
