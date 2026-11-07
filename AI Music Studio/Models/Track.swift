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

struct TrackChorusSettings: Codable, Equatable {
    var isBypassed = true
    var rateHz = 0.8
    var depthMilliseconds = 5.0
    var mix = 0.25
}

struct TrackDistortionSettings: Codable, Equatable {
    var isBypassed = true
    var driveDB = 8.0
    var mix = 0.35
}

struct TrackStereoDelaySettings: Codable, Equatable {
    var isBypassed = true
    var timeBeats = 0.5
    var feedback = 0.3
    var mix = 0.25
}

struct TrackEffectsRack: Codable, Equatable {
    var chorus = TrackChorusSettings()
    var distortion = TrackDistortionSettings()
    var stereoDelay = TrackStereoDelaySettings()
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
    var effectsRack: TrackEffectsRack
    var volumeAutomationPoints: [VolumeAutomationPoint]
    var panAutomationPoints: [PanAutomationPoint]
    var notes: [SynthNote]
    /// Instrument the track's piano-roll notes are played with.
    var voice: TrackVoiceKind
    /// The preset the track's voice plays, or nil for the voice's default sound.
    var presetID: String?
    /// Amp and pickup tone applied to guitar and bass voices.
    var guitarTone = GuitarTone()
    /// Overrides the vocal preset's vibrato depth, from 0 to 1.
    var vocalVibrato: Double?
    /// Recorded passes on this track, each kept in the take lane.
    var takes: [TrackTake]
    /// The take currently placed on the timeline.
    var activeTakeID: UUID?
    /// Send level to aux bus A, from 0 to 1.
    var sendA: Float
    /// Send level to aux bus B, from 0 to 1.
    var sendB: Float
    /// Rendered audio of this track while it is frozen.
    var frozenFileName: String?
    var frozenDuration: TimeInterval
    /// Arpeggiator applied to this track's arrangement notes.
    var arpeggiator = ArpeggiatorSettings()
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
        effectsRack: TrackEffectsRack = TrackEffectsRack(),
        volumeAutomationPoints: [VolumeAutomationPoint] = [],
        panAutomationPoints: [PanAutomationPoint] = [],
        notes: [SynthNote] = [],
        voice: TrackVoiceKind = .synth,
        presetID: String? = nil,
        guitarTone: GuitarTone = GuitarTone(),
        takes: [TrackTake] = [],
        activeTakeID: UUID? = nil,
        sendA: Float = 0,
        sendB: Float = 0,
        frozenFileName: String? = nil,
        frozenDuration: TimeInterval = 0,
        arpeggiator: ArpeggiatorSettings = ArpeggiatorSettings()
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
        self.effectsRack = effectsRack
        self.volumeAutomationPoints = volumeAutomationPoints
        self.panAutomationPoints = panAutomationPoints
        self.notes = notes
        self.voice = voice
        self.presetID = presetID
        self.guitarTone = guitarTone
        self.takes = takes
        self.activeTakeID = activeTakeID
        self.sendA = min(1, max(0, sendA))
        self.sendB = min(1, max(0, sendB))
        self.frozenFileName = frozenFileName
        self.frozenDuration = frozenDuration
        self.arpeggiator = arpeggiator
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
        case effectsRack
        case volumeAutomationPoints
        case panAutomationPoints
        case notes
        case voice
        case presetID
        case guitarTone
        case vocalVibrato
        case takes
        case activeTakeID
        case sendA
        case sendB
        case frozenFileName
        case frozenDuration
        case arpeggiator
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
        effectsRack = try values.decodeIfPresent(TrackEffectsRack.self, forKey: .effectsRack) ?? TrackEffectsRack()
        volumeAutomationPoints = try values.decodeIfPresent([VolumeAutomationPoint].self, forKey: .volumeAutomationPoints) ?? []
        panAutomationPoints = try values.decodeIfPresent([PanAutomationPoint].self, forKey: .panAutomationPoints) ?? []
        notes = try values.decodeIfPresent([SynthNote].self, forKey: .notes) ?? []
        voice = try values.decodeIfPresent(TrackVoiceKind.self, forKey: .voice) ?? .synth
        presetID = try values.decodeIfPresent(String.self, forKey: .presetID)
        guitarTone = try values.decodeIfPresent(GuitarTone.self, forKey: .guitarTone) ?? GuitarTone()
        vocalVibrato = try values.decodeIfPresent(Double.self, forKey: .vocalVibrato)
        takes = try values.decodeIfPresent([TrackTake].self, forKey: .takes) ?? []
        activeTakeID = try values.decodeIfPresent(UUID.self, forKey: .activeTakeID)
        sendA = min(1, max(0, try values.decodeIfPresent(Float.self, forKey: .sendA) ?? 0))
        sendB = min(1, max(0, try values.decodeIfPresent(Float.self, forKey: .sendB) ?? 0))
        frozenFileName = try values.decodeIfPresent(String.self, forKey: .frozenFileName)
        frozenDuration = try values.decodeIfPresent(TimeInterval.self, forKey: .frozenDuration) ?? 0
        arpeggiator = try values.decodeIfPresent(ArpeggiatorSettings.self, forKey: .arpeggiator) ?? ArpeggiatorSettings()
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

    /// The notes as they actually play, after the track's arpeggiator.
    func playedNotes(tempoBPM: Int) -> [SynthNote] {
        Arpeggiator.expanded(notes: sequencedNotes, settings: arpeggiator, tempoBPM: tempoBPM)
    }

    /// The preset sound this track plays, falling back to its voice's default.
    var soundPreset: InstrumentPreset {
        InstrumentPresetLibrary.preset(id: presetID) ?? InstrumentPresetLibrary.defaultPreset(for: voice)
    }

    /// The preset the notes are actually rendered with, including a vocal vibrato override.
    var renderPreset: InstrumentPreset {
        var preset = soundPreset
        if voice == .marleneVocal, let vocalVibrato {
            preset.vibrato = min(0.03, max(0, vocalVibrato))
        }
        return preset
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
    /// Selected length in source-audio seconds.
    var duration: TimeInterval
    /// Read offset into the original audio file, used for non-destructive trims and splits.
    var sourceStartTime: TimeInterval
    /// Full length of the underlying source file.
    var sourceDuration: TimeInterval
    var isOriginal: Bool
    /// The recorded take this clip represents, when it came from the take lane.
    var takeID: UUID?
    /// Fade lengths in timeline seconds.
    var fadeIn: TimeInterval
    var fadeOut: TimeInterval
    /// Original tempo used to sync this clip to the session; nil keeps its natural timing.
    var sourceTempoBPM: Double?
    /// Pitch adjustment in semitones, limited to one octave in either direction.
    var transposeSemitones: Int

    init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        startTime: TimeInterval,
        duration: TimeInterval,
        sourceStartTime: TimeInterval = 0,
        sourceDuration: TimeInterval? = nil,
        isOriginal: Bool = false,
        takeID: UUID? = nil,
        fadeIn: TimeInterval = 0,
        fadeOut: TimeInterval = 0,
        sourceTempoBPM: Double? = nil,
        transposeSemitones: Int = 0
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.startTime = startTime
        self.duration = duration
        self.sourceStartTime = sourceStartTime
        self.sourceDuration = sourceDuration ?? duration
        self.isOriginal = isOriginal
        self.takeID = takeID
        self.fadeIn = max(0, fadeIn)
        self.fadeOut = max(0, fadeOut)
        self.sourceTempoBPM = sourceTempoBPM.map { min(200, max(60, $0)) }
        self.transposeSemitones = min(12, max(-12, transposeSemitones))
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
        case takeID
        case fadeIn
        case fadeOut
        case sourceTempoBPM
        case transposeSemitones
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
        takeID = try values.decodeIfPresent(UUID.self, forKey: .takeID)
        fadeIn = max(0, try values.decodeIfPresent(TimeInterval.self, forKey: .fadeIn) ?? 0)
        fadeOut = max(0, try values.decodeIfPresent(TimeInterval.self, forKey: .fadeOut) ?? 0)
        sourceTempoBPM = try values.decodeIfPresent(Double.self, forKey: .sourceTempoBPM).map { min(200, max(60, $0)) }
        transposeSemitones = min(12, max(-12, try values.decodeIfPresent(Int.self, forKey: .transposeSemitones) ?? 0))
    }

    /// Source playback speed needed to follow the session tempo.
    func playbackRate(tempoBPM: Int) -> Double {
        guard let sourceTempoBPM else { return 1 }
        return min(4, max(0.25, Double(min(200, max(60, tempoBPM))) / sourceTempoBPM))
    }

    /// Visible length on the timeline after tempo sync.
    func timelineDuration(tempoBPM: Int) -> TimeInterval {
        min(duration, max(0, sourceDuration - sourceStartTime)) / playbackRate(tempoBPM: tempoBPM)
    }

    /// Source offset corresponding to an offset measured on the timeline.
    func sourceOffset(forTimelineOffset offset: TimeInterval, tempoBPM: Int) -> TimeInterval {
        max(0, offset) * playbackRate(tempoBPM: tempoBPM)
    }

    /// Gain at an absolute timeline moment, including fades and clip crossfades.
    func gain(at time: TimeInterval, in track: Track, tempoBPM: Int = 120) -> Float {
        let length = timelineDuration(tempoBPM: tempoBPM)
        let local = time - startTime
        guard local >= 0, local <= length else { return 0 }
        var gain = 1.0
        if local < fadeIn, fadeIn > 0 {
            gain *= local / fadeIn
        }
        if local > length - fadeOut, fadeOut > 0 {
            gain *= (length - local) / fadeOut
        }

        let others = track.playbackClips.filter { $0.id != id }.sorted { $0.startTime < $1.startTime }
        if let previous = others.last(where: { $0.startTime <= startTime }),
           previous.startTime + previous.timelineDuration(tempoBPM: tempoBPM) > startTime {
            let overlap = previous.startTime + previous.timelineDuration(tempoBPM: tempoBPM) - startTime
            if local < overlap, overlap > 0 {
                gain *= 0.5 + 0.5 * (local / overlap)
            }
        }
        if let next = others.first(where: { $0.startTime > startTime }),
           next.startTime < startTime + length {
            let overlap = startTime + length - next.startTime
            let remaining = length - local
            if remaining < overlap, overlap > 0 {
                gain *= 0.5 + 0.5 * (remaining / overlap)
            }
        }
        return Float(min(1, max(0, gain)))
    }
}
