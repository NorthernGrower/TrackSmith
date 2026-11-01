//
//  Track.swift
//  AI Music Studio
//

import Foundation

struct TrackEQSettings: Codable, Equatable {
    var isBypassed = false
    var lowFrequency = 120.0
    var lowGain = 0.0
    var midFrequency = 1_000.0
    var midGain = 0.0
    var highFrequency = 8_000.0
    var highGain = 0.0
}

/// One layer of the session (a stem such as vocals, drums or bass).
struct Track: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    /// Legacy reference to the track's originally imported audio.
    var fileName: String
    /// Gain from 0 to 1.
    var volume: Float
    var isMuted: Bool
    var isSoloed: Bool
    var clips: [AudioClip]
    var eqSettings: TrackEQSettings
    private var clipLayoutInitialized: Bool

    init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        volume: Float = 1.0,
        isMuted: Bool = false,
        isSoloed: Bool = false,
        clips: [AudioClip]? = nil,
        eqSettings: TrackEQSettings = TrackEQSettings()
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.volume = volume
        self.isMuted = isMuted
        self.isSoloed = isSoloed
        self.clips = clips ?? [AudioClip(
            id: id,
            name: name,
            fileName: fileName,
            startTime: 0,
            duration: 0,
            sourceStartTime: 0,
            sourceDuration: 0,
            isOriginal: true
        )]
        self.eqSettings = eqSettings
        clipLayoutInitialized = true
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fileName
        case volume
        case isMuted
        case isSoloed
        case clips
        case eqSettings
        case clipLayoutInitialized
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        fileName = try values.decode(String.self, forKey: .fileName)
        volume = try values.decodeIfPresent(Float.self, forKey: .volume) ?? 1.0
        isMuted = try values.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isSoloed = try values.decodeIfPresent(Bool.self, forKey: .isSoloed) ?? false
        let storedClips = try values.decodeIfPresent([AudioClip].self, forKey: .clips) ?? []
        let hasClipLayout = try values.decodeIfPresent(Bool.self, forKey: .clipLayoutInitialized) ?? false

        if hasClipLayout {
            clips = storedClips
        } else {
            let sourceClip = AudioClip(
                id: id,
                name: name,
                fileName: fileName,
                startTime: 0,
                duration: 0,
                sourceStartTime: 0,
                sourceDuration: 0,
                isOriginal: true
            )
            clips = [sourceClip] + storedClips
        }
        eqSettings = try values.decodeIfPresent(TrackEQSettings.self, forKey: .eqSettings) ?? TrackEQSettings()
        clipLayoutInitialized = true
    }
}

struct AudioClip: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var fileName: String
    /// Placement of the clip in the session timeline.
    var startTime: TimeInterval
    /// Visible playback length of this region.
    var duration: TimeInterval
    /// Read offset into the original audio file, used for non-destructive trims and splits.
    var sourceStartTime: TimeInterval
    /// Full length of the underlying source file.
    var sourceDuration: TimeInterval
    var isOriginal: Bool

    init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        startTime: TimeInterval,
        duration: TimeInterval,
        sourceStartTime: TimeInterval = 0,
        sourceDuration: TimeInterval? = nil,
        isOriginal: Bool = false
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.startTime = startTime
        self.duration = duration
        self.sourceStartTime = sourceStartTime
        self.sourceDuration = sourceDuration ?? duration
        self.isOriginal = isOriginal
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fileName
        case startTime
        case duration
        case sourceStartTime
        case sourceDuration
        case isOriginal
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        fileName = try values.decode(String.self, forKey: .fileName)
        startTime = try values.decodeIfPresent(TimeInterval.self, forKey: .startTime) ?? 0
        duration = try values.decode(TimeInterval.self, forKey: .duration)
        sourceStartTime = try values.decodeIfPresent(TimeInterval.self, forKey: .sourceStartTime) ?? 0
        sourceDuration = try values.decodeIfPresent(TimeInterval.self, forKey: .sourceDuration) ?? duration
        isOriginal = try values.decodeIfPresent(Bool.self, forKey: .isOriginal) ?? false
    }
}
