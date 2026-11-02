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

struct TrackCompressorSettings: Codable, Equatable {
    var isBypassed = true
    var thresholdDB = -18.0
    var ratio = 4.0
    var attackMilliseconds = 10.0
    var releaseMilliseconds = 120.0
}

struct VolumeAutomationPoint: Identifiable, Codable, Equatable {
    var id: UUID
    var time: TimeInterval
    var gain: Float

    init(id: UUID = UUID(), time: TimeInterval, gain: Float) {
        self.id = id
        self.time = time
        self.gain = gain
    }
}

struct PanAutomationPoint: Identifiable, Codable, Equatable {
    var id: UUID
    var time: TimeInterval
    var pan: Float

    init(id: UUID = UUID(), time: TimeInterval, pan: Float) {
        self.id = id
        self.time = time
        self.pan = pan
    }
}

/// One layer of the session (a stem such as vocals, drums or bass).
struct Track: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    /// Legacy reference to the track's originally imported audio.
    var fileName: String
    /// Gain from 0 to 1.
    var volume: Float
    /// Stereo position from -1 (left) to 1 (right).
    var pan: Float
    var isMuted: Bool
    var isSoloed: Bool
    var clips: [AudioClip]
    var eqSettings: TrackEQSettings
    var compressorSettings: TrackCompressorSettings
    var volumeAutomationPoints: [VolumeAutomationPoint]
    var panAutomationPoints: [PanAutomationPoint]
    var notes: [SynthNote]
    /// Rendered audio of this track while it is frozen.
    var frozenFileName: String?
    var frozenDuration: TimeInterval
    private var clipLayoutInitialized: Bool

    init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        volume: Float = 1.0,
        pan: Float = 0,
        isMuted: Bool = false,
        isSoloed: Bool = false,
        clips: [AudioClip]? = nil,
        eqSettings: TrackEQSettings = TrackEQSettings(),
        compressorSettings: TrackCompressorSettings = TrackCompressorSettings(),
        volumeAutomationPoints: [VolumeAutomationPoint] = [],
        panAutomationPoints: [PanAutomationPoint] = [],
        notes: [SynthNote] = [],
        frozenFileName: String? = nil,
        frozenDuration: TimeInterval = 0
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.volume = volume
        self.pan = pan
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
        self.compressorSettings = compressorSettings
        self.volumeAutomationPoints = volumeAutomationPoints
        self.panAutomationPoints = panAutomationPoints
        self.notes = notes
        self.frozenFileName = frozenFileName
        self.frozenDuration = frozenDuration
        clipLayoutInitialized = true
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fileName
        case volume
        case pan
        case isMuted
        case isSoloed
        case clips
        case eqSettings
        case compressorSettings
        case volumeAutomationPoints
        case panAutomationPoints
        case notes
        case frozenFileName
        case frozenDuration
        case clipLayoutInitialized
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        fileName = try values.decode(String.self, forKey: .fileName)
        volume = try values.decodeIfPresent(Float.self, forKey: .volume) ?? 1.0
        pan = try values.decodeIfPresent(Float.self, forKey: .pan) ?? 0
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
        compressorSettings = try values.decodeIfPresent(TrackCompressorSettings.self, forKey: .compressorSettings) ?? TrackCompressorSettings()
        volumeAutomationPoints = try values.decodeIfPresent([VolumeAutomationPoint].self, forKey: .volumeAutomationPoints) ?? []
        panAutomationPoints = try values.decodeIfPresent([PanAutomationPoint].self, forKey: .panAutomationPoints) ?? []
        notes = try values.decodeIfPresent([SynthNote].self, forKey: .notes) ?? []
        frozenFileName = try values.decodeIfPresent(String.self, forKey: .frozenFileName)
        frozenDuration = try values.decodeIfPresent(TimeInterval.self, forKey: .frozenDuration) ?? 0
        clipLayoutInitialized = true
    }

    /// Whether the track currently plays rendered audio instead of its source material.
    var isFrozen: Bool {
        frozenFileName != nil
    }

    /// The clips the engine plays: one frozen clip while the track is frozen.
    var playbackClips: [AudioClip] {
        if let frozenFileName, frozenDuration > 0 {
            return [AudioClip(
                id: id,
                name: "\(name) (Frozen)",
                fileName: frozenFileName,
                startTime: 0,
                duration: frozenDuration,
                sourceStartTime: 0,
                sourceDuration: frozenDuration,
                isOriginal: true
            )]
        }
        return clips
    }

    /// Arrangement notes stay silent while the track is frozen.
    var sequencedNotes: [SynthNote] {
        isFrozen ? [] : notes
    }

    func automationGain(at time: TimeInterval) -> Float {
        let points = volumeAutomationPoints.sorted { $0.time < $1.time }
        guard let first = points.first else { return 1 }
        if time <= first.time { return min(1, max(0, first.gain)) }

        for index in 1..<points.count {
            let left = points[index - 1]
            let right = points[index]
            guard time <= right.time else { continue }
            let span = right.time - left.time
            guard span > 0 else { return min(1, max(0, right.gain)) }
            let progress = Float(min(1, max(0, (time - left.time) / span)))
            let eased = progress * progress * (3 - 2 * progress)
            let startGain = min(1, max(0, left.gain))
            let endGain = min(1, max(0, right.gain))
            return startGain + (endGain - startGain) * eased
        }

        return min(1, max(0, points[points.count - 1].gain))
    }

    /// The track's pan at a moment in time, following its pan automation when it has any.
    func panAutomationValue(at time: TimeInterval) -> Float {
        let points = panAutomationPoints.sorted { $0.time < $1.time }
        guard let first = points.first else { return pan }
        if time <= first.time { return min(1, max(-1, first.pan)) }

        for index in 1..<points.count {
            let left = points[index - 1]
            let right = points[index]
            guard time <= right.time else { continue }
            let span = right.time - left.time
            guard span > 0 else { return min(1, max(-1, right.pan)) }
            let progress = Float(min(1, max(0, (time - left.time) / span)))
            let eased = progress * progress * (3 - 2 * progress)
            let startPan = min(1, max(-1, left.pan))
            let endPan = min(1, max(-1, right.pan))
            return startPan + (endPan - startPan) * eased
        }

        return min(1, max(-1, points[points.count - 1].pan))
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
