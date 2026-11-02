//
//  BounceSettings.swift
//  AI Music Studio
//

import Foundation

enum BounceFormat: String, CaseIterable, Codable {
    case wav
    case m4a

    var title: String {
        switch self {
        case .wav: return "WAV"
        case .m4a: return "M4A"
        }
    }

    var fileExtension: String { rawValue }
}

enum BounceSampleRate: Int, CaseIterable, Codable {
    case hz44100 = 44_100
    case hz48000 = 48_000

    var title: String {
        switch self {
        case .hz44100: return "44.1 kHz"
        case .hz48000: return "48 kHz"
        }
    }
}

enum BounceBitDepth: Int, CaseIterable, Codable {
    case bit16 = 16
    case bit24 = 24

    var title: String { "\(rawValue)-bit" }
}

/// How a mix or stem render is written to disk.
struct BounceSettings: Codable, Equatable {
    var format: BounceFormat = .wav
    var sampleRate: BounceSampleRate = .hz44100
    /// Only used by WAV files; M4A is always encoded as AAC.
    var bitDepth: BounceBitDepth = .bit24
    /// Raises the render so its loudest peak sits at -1 dBFS.
    var normalize = false
    /// Base name of the exported file, without the extension.
    var fileName = "Mix"

    var fileExtension: String { format.fileExtension }

    /// Rough size of one rendered file for a given length.
    func estimatedBytes(duration: TimeInterval) -> Int64 {
        let seconds = max(0, duration)
        switch format {
        case .wav:
            let samples = Int64(seconds * Double(sampleRate.rawValue))
            return samples * 2 * Int64(bitDepth.rawValue / 8)
        case .m4a:
            // About 256 kbps AAC.
            return Int64(seconds * 32_000)
        }
    }
}

/// Remembers the last settings used for a bounce.
enum BounceSettingsStorage {
    private static let key = "studio.bounceSettings"

    static func load() -> BounceSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(BounceSettings.self, from: data) else {
            return BounceSettings()
        }
        return settings
    }

    static func save(_ settings: BounceSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
