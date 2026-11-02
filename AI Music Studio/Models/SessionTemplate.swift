//
//  SessionTemplate.swift
//  AI Music Studio
//

import Foundation

/// A prepared track layout a session can be started from.
struct SessionTemplate: Identifiable, Codable, Equatable {
    /// One channel the template sets up, with its mixer settings already dialled in.
    struct TrackSlot: Identifiable, Codable, Equatable {
        let name: String
        /// Gain from 0 to 1.
        let volume: Float
        /// Stereo position from -1 (left) to 1 (right).
        let pan: Float
        let eqSettings: TrackEQSettings
        let compressorSettings: TrackCompressorSettings

        var id: String { name }

        init(
            name: String,
            volume: Float,
            pan: Float = 0,
            eqSettings: TrackEQSettings = TrackEQSettings(),
            compressorSettings: TrackCompressorSettings = TrackCompressorSettings()
        ) {
            self.name = name
            self.volume = volume
            self.pan = pan
            self.eqSettings = eqSettings
            self.compressorSettings = compressorSettings
        }
    }

    let id: String
    let name: String
    /// One line describing what the layout is for.
    let summary: String
    let symbolName: String
    let tempoBPM: Int
    /// Whether the studio suggests this layout first.
    let isSuggested: Bool
    let tracks: [TrackSlot]

    var trackCount: Int { tracks.count }
}

/// The layouts the studio offers when a session is started.
enum SessionTemplateCatalog {
    static let all: [SessionTemplate] = [
        .fourPieceBand,
        .electronicSetup,
        .vocalAndBacking
    ]

    static func template(id: String) -> SessionTemplate? {
        all.first { $0.id == id }
    }
}

extension SessionTemplate {
    static let fourPieceBand = SessionTemplate(
        id: "four-piece-band",
        name: "Four-Piece Band",
        summary: "Vocals, guitar, bass and drums, balanced for a live-band mix.",
        symbolName: "music.note.list",
        tempoBPM: 92,
        isSuggested: true,
        tracks: [
            TrackSlot(
                name: "Vocals",
                volume: 0.92,
                eqSettings: TrackEQSettings(lowGain: -2, midGain: 1.5, highGain: 2)
            ),
            TrackSlot(
                name: "Drums",
                volume: 0.9,
                eqSettings: TrackEQSettings(lowGain: 2, midGain: -1, highGain: 1.5),
                compressorSettings: TrackCompressorSettings(
                    isBypassed: false,
                    thresholdDB: -20,
                    ratio: 4,
                    attackMilliseconds: 6,
                    releaseMilliseconds: 140
                )
            ),
            TrackSlot(
                name: "Bass",
                volume: 0.86,
                eqSettings: TrackEQSettings(lowGain: 1.5, midGain: -0.5, highGain: 1),
                compressorSettings: TrackCompressorSettings(isBypassed: false, thresholdDB: -18, ratio: 3)
            ),
            TrackSlot(
                name: "Guitar",
                volume: 0.7,
                pan: 0.22,
                eqSettings: TrackEQSettings(lowFrequency: 180, lowGain: -2, midFrequency: 1_600, midGain: 1, highGain: 1)
            )
        ]
    )

    static let electronicSetup = SessionTemplate(
        id: "electronic-setup",
        name: "Electronic Setup",
        summary: "Drums, bass, synth and an FX return for club-ready productions.",
        symbolName: "pianokeys",
        tempoBPM: 124,
        isSuggested: false,
        tracks: [
            TrackSlot(
                name: "Drums",
                volume: 0.9,
                eqSettings: TrackEQSettings(lowGain: 2, midGain: -1, highGain: 1.5),
                compressorSettings: TrackCompressorSettings(
                    isBypassed: false,
                    thresholdDB: -20,
                    ratio: 4,
                    attackMilliseconds: 6,
                    releaseMilliseconds: 140
                )
            ),
            TrackSlot(
                name: "Bass",
                volume: 0.85,
                eqSettings: TrackEQSettings(lowGain: 1.5, midGain: -0.5, highGain: 1),
                compressorSettings: TrackCompressorSettings(isBypassed: false, thresholdDB: -18, ratio: 3)
            ),
            TrackSlot(
                name: "Synth",
                volume: 0.78,
                pan: -0.15,
                eqSettings: TrackEQSettings(lowGain: -1, midGain: 1.5, highGain: 0.5)
            ),
            TrackSlot(
                name: "FX",
                volume: 0.55,
                pan: 0.3,
                eqSettings: TrackEQSettings(lowGain: -3, midGain: 0, highGain: 2)
            )
        ]
    )

    static let vocalAndBacking = SessionTemplate(
        id: "vocal-and-backing",
        name: "Vocal and Backing",
        summary: "A lead vocal with a tucked-back double over a rhythm section.",
        symbolName: "music.mic",
        tempoBPM: 78,
        isSuggested: false,
        tracks: [
            TrackSlot(
                name: "Lead Vocal",
                volume: 0.95,
                eqSettings: TrackEQSettings(lowGain: -1.5, midGain: 2, highGain: 2.5),
                compressorSettings: TrackCompressorSettings(isBypassed: false, thresholdDB: -22, ratio: 3)
            ),
            TrackSlot(
                name: "Backing",
                volume: 0.62,
                pan: -0.25,
                eqSettings: TrackEQSettings(lowGain: -2, midGain: 0.5, highGain: 1)
            ),
            TrackSlot(
                name: "Drums",
                volume: 0.85,
                eqSettings: TrackEQSettings(lowGain: 2, midGain: -1, highGain: 1.5)
            ),
            TrackSlot(
                name: "Bass",
                volume: 0.82,
                eqSettings: TrackEQSettings(lowGain: 1.5, midGain: -0.5, highGain: 1)
            )
        ]
    )
}


extension SessionTemplate {
    /// Captures a session's track names, order and mixer settings as a
    /// template the user can start new sessions from.
    static func make(from session: StudioSession, name: String) -> SessionTemplate {
        let count = session.tracks.count
        let trackText = count == 1 ? "1 track" : "\(count) tracks"

        return SessionTemplate(
            id: UUID().uuidString,
            name: name,
            summary: "Captured from \(session.name): \(trackText) with their levels, pan, EQ and compression.",
            symbolName: "bookmark",
            tempoBPM: session.tempoBPM,
            isSuggested: false,
            tracks: session.tracks.map { track in
                TrackSlot(
                    name: track.name,
                    volume: track.volume,
                    pan: track.pan,
                    eqSettings: track.eqSettings,
                    compressorSettings: track.compressorSettings
                )
            }
        )
    }
}

/// Keeps the user's own templates on device, apart from the sessions they came from.
enum SessionTemplateStorage {
    private static let key = "studio.customSessionTemplates"

    static func load() -> [SessionTemplate] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let templates = try? JSONDecoder().decode([SessionTemplate].self, from: data) else {
            return []
        }
        return templates
    }

    static func save(_ templates: [SessionTemplate]) {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
