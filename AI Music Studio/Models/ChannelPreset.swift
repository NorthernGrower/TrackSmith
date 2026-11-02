//
//  ChannelPreset.swift
//  AI Music Studio
//

import Foundation

/// A saved channel strip: EQ, compressor, pan and level.
struct ChannelPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var sourceTrackName: String
    var createdAt: Date
    var volume: Float
    var pan: Float
    var eqSettings: TrackEQSettings
    var compressorSettings: TrackCompressorSettings

    init(
        id: UUID = UUID(),
        name: String,
        sourceTrackName: String,
        createdAt: Date = Date(),
        volume: Float,
        pan: Float,
        eqSettings: TrackEQSettings,
        compressorSettings: TrackCompressorSettings
    ) {
        self.id = id
        self.name = name
        self.sourceTrackName = sourceTrackName
        self.createdAt = createdAt
        self.volume = volume
        self.pan = pan
        self.eqSettings = eqSettings
        self.compressorSettings = compressorSettings
    }

    var summary: String {
        let compression = compressorSettings.isBypassed ? "NO COMP" : "COMP"
        return "FROM \(sourceTrackName.uppercased()) · 3 BANDS · \(compression)"
    }
}

/// Presets are kept on device, shared across sessions.
enum ChannelPresetStorage {
    private static let key = "studio.channelPresets"

    static func load() -> [ChannelPreset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let presets = try? JSONDecoder().decode([ChannelPreset].self, from: data) else {
            return []
        }
        return presets
    }

    static func save(_ presets: [ChannelPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
