//
//  MasteringSettings.swift
//  AI Music Studio
//

import Foundation

/// Three bands of EQ applied to the whole master bus.
struct MasterEQSettings: Codable, Equatable {
    var isBypassed = false
    var lowGain = 0.0
    var midFrequency = 1_000.0
    var midGain = 0.0
    var highGain = 0.0

    static let gainRange = -12.0...12.0
    static let midFrequencyRange = 200.0...6_000.0
}

/// Glue compressor across the master bus.
struct MasterCompressorSettings: Codable, Equatable {
    var isBypassed = false
    var thresholdDB = -18.0
    var ratio = 2.0
    var attackMilliseconds = 30.0
    var releaseMilliseconds = 250.0

    static let thresholdRange = -40.0...0.0
    static let ratioRange = 1.0...8.0
    static let attackRange = 1.0...100.0
    static let releaseRange = 50.0...1_000.0
}

/// Peak limiter that catches the last transients and sets the output ceiling.
struct MasterLimiterSettings: Codable, Equatable {
    var isBypassed = false
    var driveDB = 0.0
    var ceilingDB = -1.0
    var releaseMilliseconds = 80.0

    static let driveRange = -12.0...12.0
    static let ceilingRange = -6.0...0.0
    static let releaseRange = 20.0...500.0
}

/// Streaming services, podcasts and clubs aim at different loudness.
enum MasteringTarget: String, Codable, CaseIterable, Identifiable {
    case streaming
    case podcast
    case club

    var id: String { rawValue }

    var title: String {
        switch self {
        case .streaming: return "Streaming"
        case .podcast: return "Podcast"
        case .club: return "Club"
        }
    }

    /// Integrated loudness the target aims for, in LUFS.
    var loudness: Double {
        switch self {
        case .streaming: return -14
        case .podcast: return -16
        case .club: return -9
        }
    }

    /// True peak ceiling the target aims for, in dBTP.
    var truePeakCeiling: Double {
        switch self {
        case .streaming: return -1
        case .podcast: return -1
        case .club: return -0.1
        }
    }

    var detail: String {
        switch self {
        case .streaming: return "Spotify, Apple Music"
        case .podcast: return "Spoken word"
        case .club: return "Loud club master"
        }
    }

    var summary: String {
        String(format: "Aiming for %.0f LUFS · %.1f dBTP", loudness, truePeakCeiling)
    }
}

/// Master EQ, bus compressor and limiter applied to the whole mix.
struct MasteringSettings: Codable, Equatable {
    var isBypassed = true
    var eq = MasterEQSettings()
    var compressor = MasterCompressorSettings()
    var limiter = MasterLimiterSettings()
    var target: MasteringTarget = .streaming
}
