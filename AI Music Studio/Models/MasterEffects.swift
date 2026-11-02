//
//  MasterEffects.swift
//  AI Music Studio
//

import Foundation

/// Reverb and delay applied to the whole master output.
struct MasterEffectsSettings: Codable, Equatable {
    var isBypassed = true
    var reverbMix = 0.32
    /// Reverb tail length in seconds.
    var reverbDecay = 1.8
    /// Delay time measured in beats (0.5 = one eighth note).
    var delayTimeBeats = 0.5
    var delayFeedback = 0.38
    var delayMix = 0.22

    static let reverbDecayRange = 0.3...5.0
    static let delayBeatsRange = 0.25...2.0
    static let delayBeatChoices: [Double] = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0]

    var reverbRoomName: String {
        switch reverbDecay {
        case ..<0.6: return "Small Room"
        case ..<1.2: return "Medium Room"
        case ..<2.0: return "Large Room"
        case ..<2.8: return "Medium Hall"
        case ..<3.8: return "Large Hall"
        default: return "Cathedral"
        }
    }

    var delayBeatLabel: String {
        let choice = Self.delayBeatChoices.min(by: { abs($0 - delayTimeBeats) < abs($1 - delayTimeBeats) })
            ?? delayTimeBeats
        switch choice {
        case 0.25: return "1/16"
        case 0.5: return "1/8"
        case 0.75: return "1/8."
        case 1.0: return "1/4"
        case 1.5: return "1/4."
        default: return "1/2"
        }
    }

    func delaySeconds(tempoBPM: Int) -> TimeInterval {
        let beat = 60.0 / Double(max(60, min(200, tempoBPM)))
        return min(2, max(0.01, delayTimeBeats * beat))
    }
}
