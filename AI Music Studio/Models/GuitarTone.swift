//
//  GuitarTone.swift
//  AI Music Studio
//

import Foundation

/// The amp and pickup voice a guitar or bass track is played through.
struct GuitarTone: Codable, Equatable, Hashable {
    /// Drive into the amplifier, from 0 (clean) to 1 (fully saturated).
    var gain: Double = 0.5
    /// Tone control, from 0 (dark) to 1 (bright).
    var brightness: Double = 0.5
    /// Pickup position, from 0 (neck) to 1 (bridge).
    var pickup: Double = 0.5

    init(gain: Double = 0.5, brightness: Double = 0.5, pickup: Double = 0.5) {
        self.gain = min(1, max(0, gain))
        self.brightness = min(1, max(0, brightness))
        self.pickup = min(1, max(0, pickup))
    }

    private enum CodingKeys: String, CodingKey {
        case gain
        case brightness
        case pickup
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            gain: try values.decodeIfPresent(Double.self, forKey: .gain) ?? 0.5,
            brightness: try values.decodeIfPresent(Double.self, forKey: .brightness) ?? 0.5,
            pickup: try values.decodeIfPresent(Double.self, forKey: .pickup) ?? 0.5
        )
    }

    /// Multiplier applied to the amp's drive; 0.5 on the knob is the neutral sound.
    var driveScale: Double {
        0.5 + min(1, max(0, gain))
    }

    /// Multiplier applied to the note's tone; 0.5 on the knob is the neutral sound.
    var brightnessScale: Double {
        (0.5 + min(1, max(0, brightness))) * (0.7 + 0.6 * min(1, max(0, pickup)))
    }

    /// The named preset these values match, when they match one.
    var matchedPreset: GuitarTonePreset? {
        GuitarTonePresets.all.first { preset in
            abs(preset.tone.gain - gain) < 0.01
                && abs(preset.tone.brightness - brightness) < 0.01
                && abs(preset.tone.pickup - pickup) < 0.01
        }
    }
}

/// One named amp setting for guitar tracks.
struct GuitarTonePreset: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let tone: GuitarTone
}

enum GuitarTonePresets {
    static let all: [GuitarTonePreset] = [
        GuitarTonePreset(
            id: "clean", name: "Clean",
            detail: "Neck pickup, low gain, plenty of headroom",
            tone: GuitarTone(gain: 0.3, brightness: 0.55, pickup: 0.3)
        ),
        GuitarTonePreset(
            id: "crunch", name: "Crunch",
            detail: "Mildly broken up rhythm tone",
            tone: GuitarTone(gain: 0.62, brightness: 0.5, pickup: 0.6)
        ),
        GuitarTonePreset(
            id: "lead", name: "Lead",
            detail: "Saturated bridge tone that sings",
            tone: GuitarTone(gain: 0.86, brightness: 0.75, pickup: 0.85)
        ),
        GuitarTonePreset(
            id: "fingerpicked", name: "Fingerpicked",
            detail: "Soft, dark and dynamic for picking",
            tone: GuitarTone(gain: 0.18, brightness: 0.38, pickup: 0.2)
        ),
    ]

    static func preset(id: String) -> GuitarTonePreset? {
        all.first { $0.id == id }
    }
}
