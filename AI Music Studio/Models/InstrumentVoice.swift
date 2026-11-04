//
//  InstrumentVoice.swift
//  AI Music Studio
//

import Foundation

/// The instrument a track's piano-roll notes are played with.
enum TrackVoiceKind: String, Codable, CaseIterable, Identifiable {
    case synth
    case marleneVocal
    case acousticGuitar
    case electricGuitar
    case distortedGuitar
    case bassGuitar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .synth: return "Studio Synth"
        case .marleneVocal: return "Marlene Vocal"
        case .acousticGuitar: return "Acoustic Guitar"
        case .electricGuitar: return "Electric Guitar"
        case .distortedGuitar: return "Distorted Guitar"
        case .bassGuitar: return "Bass Guitar"
        }
    }

    var shortTitle: String {
        switch self {
        case .synth: return "Synth"
        case .marleneVocal: return "Marlene"
        case .acousticGuitar: return "Acoustic"
        case .electricGuitar: return "Electric"
        case .distortedGuitar: return "Distorted"
        case .bassGuitar: return "Bass"
        }
    }

    var systemImage: String {
        switch self {
        case .synth: return "pianokeys"
        case .marleneVocal: return "music.mic"
        case .acousticGuitar, .electricGuitar, .distortedGuitar: return "guitars"
        case .bassGuitar: return "guitars.fill"
        }
    }

    /// Extra audio rendered after the note's written length so voices and strings ring out.
    var releaseTail: TimeInterval {
        switch self {
        case .synth: return 0.28
        case .marleneVocal: return 0.32
        case .acousticGuitar: return 0.22
        case .electricGuitar: return 0.24
        case .distortedGuitar: return 0.26
        case .bassGuitar: return 0.22
        }
    }

    var isVocal: Bool { self == .marleneVocal }

    var isGuitar: Bool {
        self == .acousticGuitar || self == .electricGuitar || self == .distortedGuitar
    }
}

/// A drummer's kit, shaping the character of every synthesized drum voice.
enum DrumKit: String, Codable, CaseIterable, Identifiable {
    case studio808
    case acoustic
    case lofi
    case trap
    case electro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studio808: return "Studio 808"
        case .acoustic: return "Acoustic Kit"
        case .lofi: return "Lo-Fi Kit"
        case .trap: return "Trap 808"
        case .electro: return "Electro Kit"
        }
    }

    var subtitle: String {
        switch self {
        case .studio808: return "Deep sub kick and tight hats"
        case .acoustic: return "Natural shells and open cymbals"
        case .lofi: return "Dusty, short and warm"
        case .trap: return "Long boomy kick, snappy top"
        case .electro: return "Bright, punchy and dry"
        }
    }

    var systemImage: String {
        switch self {
        case .studio808: return "circle.hexagongrid.fill"
        case .acoustic: return "music.quarternote.3"
        case .lofi: return "cassette"
        case .trap: return "bolt.fill"
        case .electro: return "sparkles"
        }
    }

    /// Tuning multiplier applied to every hit.
    var tuning: Double {
        switch self {
        case .studio808: return 0.98
        case .acoustic: return 1.06
        case .lofi: return 0.94
        case .trap: return 0.90
        case .electro: return 1.12
        }
    }

    /// Decay multiplier applied to every hit.
    var decay: Double {
        switch self {
        case .studio808: return 1.1
        case .acoustic: return 0.95
        case .lofi: return 0.78
        case .trap: return 1.32
        case .electro: return 0.82
        }
    }

    /// Brightness of the noise component, from 0 to 1.
    var tone: Double {
        switch self {
        case .studio808: return 0.5
        case .acoustic: return 0.72
        case .lofi: return 0.42
        case .trap: return 0.55
        case .electro: return 0.86
        }
    }

    var level: Double {
        switch self {
        case .studio808: return 0.95
        case .acoustic: return 1.0
        case .lofi: return 0.9
        case .trap: return 0.98
        case .electro: return 0.92
        }
    }

    var defaultGuitar: GuitarStyle {
        switch self {
        case .acoustic: return .acoustic
        case .lofi: return .cleanElectric
        case .trap, .studio808: return .none
        case .electro: return .cleanElectric
        }
    }
}

/// The guitar a generated song is arranged with.
enum GuitarStyle: String, Codable, CaseIterable, Identifiable {
    case none
    case acoustic
    case cleanElectric
    case overdriven

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No Guitar"
        case .acoustic: return "Acoustic"
        case .cleanElectric: return "Clean Electric"
        case .overdriven: return "Overdriven"
        }
    }

    var subtitle: String {
        switch self {
        case .none: return "Keep the arrangement without a guitar"
        case .acoustic: return "Strummed steel strings with a warm body"
        case .cleanElectric: return "Rounded neck pickup, long sustain"
        case .overdriven: return "Saturated lead voice with bite"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "speaker.slash"
        case .acoustic, .cleanElectric, .overdriven: return "guitars"
        }
    }

    var voice: TrackVoiceKind? {
        switch self {
        case .none: return nil
        case .acoustic: return .acousticGuitar
        case .cleanElectric: return .electricGuitar
        case .overdriven: return .distortedGuitar
        }
    }

    var trackName: String {
        switch self {
        case .none: return "Guitar"
        case .acoustic: return "Acoustic Guitar"
        case .cleanElectric: return "Electric Guitar"
        case .overdriven: return "Lead Guitar"
        }
    }
}

/// Who sings the generated song.
enum VocalStyle: String, Codable, CaseIterable, Identifiable {
    case marleneLead
    case marleneDouble
    case instrumental

    var id: String { rawValue }

    var title: String {
        switch self {
        case .marleneLead: return "Marlene"
        case .marleneDouble: return "Marlene + Harmony"
        case .instrumental: return "Instrumental"
        }
    }

    var subtitle: String {
        switch self {
        case .marleneLead: return "Female lead vocal"
        case .marleneDouble: return "Female lead with a stacked harmony"
        case .instrumental: return "No vocal track"
        }
    }

    var systemImage: String {
        switch self {
        case .marleneLead: return "music.mic"
        case .marleneDouble: return "music.mic.circle"
        case .instrumental: return "waveform"
        }
    }

    var includesVocal: Bool { self != .instrumental }

    var harmonyCount: Int {
        switch self {
        case .marleneLead: return 1
        case .marleneDouble: return 2
        case .instrumental: return 0
        }
    }
}
