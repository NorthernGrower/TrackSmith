//
//  VocalSettings.swift
//  AI Music Studio
//

import Foundation

/// How high Marlene sings the generated melody.
enum VocalRange: String, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var subtitle: String {
        switch self {
        case .low: return "Chest voice, deeper and warmer"
        case .medium: return "Her natural mid register"
        case .high: return "Airy top register"
        }
    }

    /// Semitones the written melody is moved for this range.
    var semitoneOffset: Int {
        switch self {
        case .low: return -5
        case .medium: return 0
        case .high: return 5
        }
    }
}

/// The character Marlene sings with.
enum VocalDelivery: String, CaseIterable, Identifiable {
    case breathy
    case clear
    case powerful

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breathy: return "Breathy"
        case .clear: return "Clear"
        case .powerful: return "Powerful"
        }
    }

    var subtitle: String {
        switch self {
        case .breathy: return "Airy and intimate"
        case .clear: return "Focused and steady"
        case .powerful: return "Open and loud"
        }
    }

    var systemImage: String {
        switch self {
        case .breathy: return "wind"
        case .clear: return "music.mic"
        case .powerful: return "bolt.fill"
        }
    }

    /// The vocal preset that renders this delivery.
    var presetID: String {
        switch self {
        case .breathy: return "vocal-breathy"
        case .clear: return "vocal-clear"
        case .powerful: return "vocal-powerful"
        }
    }

    var preset: InstrumentPreset {
        InstrumentPresetLibrary.preset(id: presetID)
            ?? InstrumentPresetLibrary.defaultPreset(for: .marleneVocal)
    }
}

/// Marlene's voice as chosen in the AI songwriter.
struct VocalSettings: Equatable {
    var range: VocalRange = .medium
    var delivery: VocalDelivery = .clear
    /// Vibrato amount, from 0 to 1.
    var vibrato: Double = 0.4
    /// Vocal parts, lead included, from 1 to 3.
    var harmonyCount: Int = 1

    /// Vibrato depth in the range the vocal renderer understands.
    var vibratoDepth: Double {
        min(0.03, max(0, vibrato * 0.03))
    }

    /// Total vocal parts, lead plus harmonies.
    var partCount: Int {
        min(3, max(1, harmonyCount))
    }
}
