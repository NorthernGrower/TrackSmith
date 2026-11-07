//
//  BounceSettings.swift
//  AI Music Studio
//

import Foundation

enum BounceRange: String, CaseIterable, Codable {
    case entireSession
    case loopRange

    var title: String {
        switch self {
        case .entireSession: return "Entire Session"
        case .loopRange: return "Loop Range"
        }
    }
}

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
    var range: BounceRange = .entireSession
    var format: BounceFormat = .wav
    var sampleRate: BounceSampleRate = .hz44100
    /// Only used by WAV files; M4A is always encoded as AAC.
    var bitDepth: BounceBitDepth = .bit24
    /// Raises the render so its loudest peak sits at -1 dBFS.
    var normalize = false
    /// Base name of the exported file, without the extension.
    var fileName = "Mix"

    private enum CodingKeys: String, CodingKey {
        case range, format, sampleRate, bitDepth, normalize, fileName
    }

    init(
        range: BounceRange = .entireSession,
        format: BounceFormat = .wav,
        sampleRate: BounceSampleRate = .hz44100,
        bitDepth: BounceBitDepth = .bit24,
        normalize: Bool = false,
        fileName: String = "Mix"
    ) {
        self.range = range
        self.format = format
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.normalize = normalize
        self.fileName = fileName
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        range = try values.decodeIfPresent(BounceRange.self, forKey: .range) ?? .entireSession
        format = try values.decodeIfPresent(BounceFormat.self, forKey: .format) ?? .wav
        sampleRate = try values.decodeIfPresent(BounceSampleRate.self, forKey: .sampleRate) ?? .hz44100
        bitDepth = try values.decodeIfPresent(BounceBitDepth.self, forKey: .bitDepth) ?? .bit24
        normalize = try values.decodeIfPresent(Bool.self, forKey: .normalize) ?? false
        fileName = try values.decodeIfPresent(String.self, forKey: .fileName) ?? "Mix"
    }

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



/// A reusable set of render options, independent of the last-used bounce settings.
struct BouncePreset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var range: BounceRange
    var format: BounceFormat
    var sampleRate: BounceSampleRate
    var bitDepth: BounceBitDepth
    var normalize: Bool

    init(id: UUID = UUID(), name: String, settings: BounceSettings) {
        self.id = id
        self.name = name
        range = settings.range
        format = settings.format
        sampleRate = settings.sampleRate
        bitDepth = settings.bitDepth
        normalize = settings.normalize
    }

    func applying(to current: BounceSettings, hasLoopRange: Bool) -> BounceSettings {
        var result = current
        result.range = range == .loopRange && !hasLoopRange ? .entireSession : range
        result.format = format
        result.sampleRate = sampleRate
        result.bitDepth = bitDepth
        result.normalize = normalize
        return result
    }
}

/// Presets are stored separately so saving or choosing one never changes the last-used settings.
enum BouncePresetStorage {
    private static let key = "studio.bouncePresets"

    static func load() -> [BouncePreset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let presets = try? JSONDecoder().decode([BouncePreset].self, from: data) else {
            return []
        }
        return presets
    }

    static func save(_ presets: [BouncePreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
