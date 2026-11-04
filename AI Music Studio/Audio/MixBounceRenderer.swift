//
//  MixBounceRenderer.swift
//  AI Music Studio
//

import AVFoundation
import Foundation

private struct BounceClip {
    let file: AVAudioFile
    let clip: AudioClip
    let player: AVAudioPlayerNode
}

private struct BounceNote {
    let buffer: AVAudioPCMBuffer
    let note: SynthNote
    let player: AVAudioPlayerNode
}

enum MixBounceRenderer {
    enum RenderError: LocalizedError {
        case noAudio
        case invalidFormat
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .noAudio:
                return "There are no playable clips in this session to bounce."
            case .invalidFormat:
                return "The mix could not be prepared in a supported audio format."
            case .renderFailed:
                return "The audio engine could not finish rendering the mix."
            }
        }
    }

    static func render(
        tracks: [Track],
        groups: [TrackGroup] = [],
        masterVolume: Float = 1,
        masterEffects: MasterEffectsSettings = MasterEffectsSettings(),
        tempoBPM: Int = 120,
        applyMuteSolo: Bool = true,
        settings: BounceSettings = BounceSettings(),
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let sampleRate = Double(settings.sampleRate.rawValue)
        guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw RenderError.invalidFormat
        }

        let engine = AVAudioEngine()
        var queuedClips: [BounceClip] = []
        var queuedNotes: [BounceNote] = []
        var trackMixers: [UUID: AVAudioMixerNode] = [:]
        var duration: TimeInterval = 0
        let mutedTrackIDs = Set(groups.filter(\.isMuted).flatMap(\.trackIDs))
        let soloedTrackIDs = Set(groups.filter(\.isSoloed).flatMap(\.trackIDs))
        let anySolo = tracks.contains { $0.isSoloed || soloedTrackIDs.contains($0.id) }

        let masterBus = AVAudioMixerNode()
        let reverb = AVAudioUnitReverb()
        let delay = AVAudioUnitDelay()
        engine.attach(masterBus)
        engine.attach(reverb)
        engine.attach(delay)
        engine.connect(masterBus, to: reverb, format: outputFormat)
        engine.connect(reverb, to: delay, format: outputFormat)
        engine.connect(delay, to: engine.mainMixerNode, format: outputFormat)
        applyMasterEffects(masterEffects, tempoBPM: tempoBPM, reverb: reverb, delay: delay)

        for track in tracks {
            let trackMixer = AVAudioMixerNode()
            let compressor = TrackCompressorUnit.make()
            engine.attach(trackMixer)
            engine.attach(compressor)
            engine.connect(trackMixer, to: compressor, format: outputFormat)
            engine.connect(compressor, to: masterBus, format: outputFormat)
            let audible = !applyMuteSolo
                || (!(track.isMuted || mutedTrackIDs.contains(track.id))
                    && (!anySolo || track.isSoloed || soloedTrackIDs.contains(track.id)))
            trackMixer.outputVolume = audible
                ? track.volume * groupGain(for: track.id, groups: groups) * track.automationGain(at: 0)
                : 0
            trackMixer.pan = min(1, max(-1, track.panAutomationValue(at: 0)))
            trackMixers[track.id] = trackMixer
            var compressorSettings = track.compressorSettings
            if track.isFrozen {
                compressorSettings.isBypassed = true
            }
            TrackCompressorUnit.configure(compressor, settings: compressorSettings)

            for clip in track.playbackClips {
                let sourceURL = TrackStorage.url(forFileName: clip.fileName)
                guard let file = try? AVAudioFile(forReading: sourceURL),
                      file.processingFormat.sampleRate > 0 else { continue }
                let sourceDuration = TimeInterval(file.length) / file.processingFormat.sampleRate
                let playableSourceDuration = min(
                    clip.duration,
                    max(0, min(clip.sourceDuration, sourceDuration) - clip.sourceStartTime)
                )
                guard playableSourceDuration > 0 else { continue }

                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: trackMixer, format: file.processingFormat)
                queuedClips.append(BounceClip(file: file, clip: clip, player: player))
                duration = max(duration, clip.startTime + playableSourceDuration)
            }

            for note in track.sequencedNotes {
                let noteDuration = note.duration
                    + (track.voice == .synth ? SynthNoteVoice.release : track.voice.releaseTail)
                guard let buffer = InstrumentSoundGenerator.voicedNote(
                    frequency: SynthNote.frequency(for: note.pitch),
                    voice: track.voice,
                    duration: noteDuration,
                    velocity: note.velocity,
                    format: outputFormat
                ) else { continue }

                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: trackMixer, format: outputFormat)
                queuedNotes.append(BounceNote(buffer: buffer, note: note, player: player))
                duration = max(duration, note.endTime)
            }
        }

        guard !queuedClips.isEmpty || !queuedNotes.isEmpty, duration > 0 else { throw RenderError.noAudio }

        for queued in queuedClips {
            let sourceRate = queued.file.processingFormat.sampleRate
            let sourceStart = AVAudioFramePosition(queued.clip.sourceStartTime * sourceRate)
            let availableFrames = queued.file.length - sourceStart
            let requestedFrames = AVAudioFramePosition(
                min(queued.clip.duration, queued.clip.sourceDuration - queued.clip.sourceStartTime) * sourceRate
            )
            let frameCount = min(availableFrames, requestedFrames)
            guard sourceStart >= 0, frameCount > 0 else { continue }

            let startSample = AVAudioFramePosition(max(0, queued.clip.startTime) * sampleRate)
            let startTime = AVAudioTime(sampleTime: startSample, atRate: sampleRate)
            queued.player.scheduleSegment(
                queued.file,
                startingFrame: sourceStart,
                frameCount: AVAudioFrameCount(min(frameCount, Int64(UInt32.max))),
                at: startTime
            )
            queued.player.play()
        }

        for queued in queuedNotes {
            let startSample = AVAudioFramePosition(max(0, queued.note.startTime) * sampleRate)
            let startTime = AVAudioTime(sampleTime: startSample, atRate: sampleRate)
            queued.player.scheduleBuffer(queued.buffer, at: startTime, options: [])
            queued.player.play()
        }

        let maximumFrameCount: AVAudioFrameCount = 512
        engine.mainMixerNode.outputVolume = min(1, max(0, masterVolume))
        try engine.enableManualRenderingMode(.offline, format: outputFormat, maximumFrameCount: maximumFrameCount)
        engine.prepare()
        try engine.start()
        defer { engine.stop() }

        // The mix is rendered as float audio first so it can be normalized, then
        // written in the chosen format and bit depth.
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MixBounce-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        var renderFile: AVAudioFile? = try AVAudioFile(forWriting: temporaryURL, settings: outputFormat.settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: maximumFrameCount) else {
            throw RenderError.invalidFormat
        }

        let totalFrames = AVAudioFramePosition(ceil(duration * sampleRate))
        var framesRendered: AVAudioFramePosition = 0
        progress(0)

        while framesRendered < totalFrames {
            let framesRemaining = totalFrames - framesRendered
            let framesToRender = AVAudioFrameCount(min(Int64(maximumFrameCount), framesRemaining))
            let automationTime = Double(framesRendered) / sampleRate
            for track in tracks {
                let audible = !applyMuteSolo
                    || (!(track.isMuted || mutedTrackIDs.contains(track.id))
                        && (!anySolo || track.isSoloed || soloedTrackIDs.contains(track.id)))
                let automatedVolume = track.volume
                    * groupGain(for: track.id, groups: groups)
                    * track.automationGain(at: automationTime)
                trackMixers[track.id]?.outputVolume = audible ? automatedVolume : 0
                trackMixers[track.id]?.pan = min(1, max(-1, track.panAutomationValue(at: automationTime)))
            }
            let status = try engine.renderOffline(framesToRender, to: buffer)

            switch status {
            case .success:
                guard buffer.frameLength > 0 else { throw RenderError.renderFailed }
                try renderFile?.write(from: buffer)
                framesRendered += AVAudioFramePosition(buffer.frameLength)
                progress(0.8 * min(1, Double(framesRendered) / Double(totalFrames)))
            case .cannotDoInCurrentContext:
                Thread.sleep(forTimeInterval: 0.001)
            case .insufficientDataFromInputNode:
                guard let channels = buffer.floatChannelData else { throw RenderError.renderFailed }
                for channel in 0..<Int(outputFormat.channelCount) {
                    for frame in 0..<Int(framesToRender) {
                        channels[channel][frame] = 0
                    }
                }
                buffer.frameLength = framesToRender
                try renderFile?.write(from: buffer)
                framesRendered += AVAudioFramePosition(framesToRender)
                progress(0.8 * min(1, Double(framesRendered) / Double(totalFrames)))
            case .error:
                throw RenderError.renderFailed
            @unknown default:
                throw RenderError.renderFailed
            }
        }

        renderFile = nil
        try writeExport(from: temporaryURL, to: outputURL, settings: settings) { fraction in
            progress(0.8 + 0.2 * fraction)
        }

        progress(1)
    }

    /// Renders one track on its own, with its mixer settings but without mute or solo.
    static func renderStem(
        track: Track,
        groups: [TrackGroup] = [],
        masterVolume: Float = 1,
        masterEffects: MasterEffectsSettings = MasterEffectsSettings(),
        tempoBPM: Int = 120,
        settings: BounceSettings = BounceSettings(),
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        try render(
            tracks: [track],
            groups: groups,
            masterVolume: masterVolume,
            masterEffects: masterEffects,
            tempoBPM: tempoBPM,
            applyMuteSolo: false,
            settings: settings,
            to: outputURL,
            progress: progress
        )
    }

    /// The gain of the group a track belongs to, or 1 when it is not grouped.
    private static func groupGain(for trackID: UUID, groups: [TrackGroup]) -> Float {
        guard let group = groups.first(where: { $0.trackIDs.contains(trackID) }) else { return 1 }
        return min(1, max(0, group.volume))
    }

    /// Writes the rendered float mix in the chosen format, bit depth and level.
    private static func writeExport(
        from sourceURL: URL,
        to outputURL: URL,
        settings: BounceSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let source = try AVAudioFile(forReading: sourceURL)
        let format = source.processingFormat
        let gain = settings.normalize ? normalizationGain(for: source) : 1

        source.framePosition = 0
        let output = try AVAudioFile(
            forWriting: outputURL,
            settings: exportSettings(for: settings, sampleRate: format.sampleRate),
            commonFormat: .pcmFormatFloat32,
            interleaved: true
        )

        let chunk: AVAudioFrameCount = 8_192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw RenderError.invalidFormat
        }

        let total = max(1, source.length)
        var written: AVAudioFramePosition = 0
        progress(0)

        while written < source.length {
            try source.read(into: buffer, frameCount: chunk)
            guard buffer.frameLength > 0 else { break }

            applyGain(gain, to: buffer)
            try output.write(from: buffer)

            written += AVAudioFramePosition(buffer.frameLength)
            progress(min(1, Double(written) / Double(total)))
        }
    }

    /// The container settings a bounce file is written with.
    private static func exportSettings(for settings: BounceSettings, sampleRate: Double) -> [String: Any] {
        switch settings.format {
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: settings.bitDepth.rawValue,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        case .m4a:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 256_000
            ]
        }
    }

    /// A gain that brings the loudest peak of a render to -1 dBFS.
    private static func normalizationGain(for file: AVAudioFile) -> Float {
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_192) else { return 1 }

        var peak: Float = 0
        file.framePosition = 0
        while true {
            do {
                try file.read(into: buffer, frameCount: 8_192)
            } catch {
                break
            }
            guard buffer.frameLength > 0, let data = buffer.floatChannelData else { break }

            for channel in 0..<Int(format.channelCount) {
                let samples = data[channel]
                for index in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(samples[index]))
                }
            }
        }
        file.framePosition = 0

        guard peak > 0.0001 else { return 1 }
        let target: Float = 0.891
        return min(8, target / peak)
    }

    private static func applyGain(_ gain: Float, to buffer: AVAudioPCMBuffer) {
        guard abs(gain - 1) > 0.0001, let data = buffer.floatChannelData else { return }

        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = data[channel]
            for index in 0..<Int(buffer.frameLength) {
                samples[index] *= gain
            }
        }
    }

    private static func applyMasterEffects(
        _ settings: MasterEffectsSettings,
        tempoBPM: Int,
        reverb: AVAudioUnitReverb,
        delay: AVAudioUnitDelay
    ) {
        let bypassed = settings.isBypassed

        switch settings.reverbDecay {
        case ..<0.6: reverb.loadFactoryPreset(.smallRoom)
        case ..<1.2: reverb.loadFactoryPreset(.mediumRoom)
        case ..<2.0: reverb.loadFactoryPreset(.largeRoom)
        case ..<2.8: reverb.loadFactoryPreset(.mediumHall)
        case ..<3.8: reverb.loadFactoryPreset(.largeHall)
        default: reverb.loadFactoryPreset(.cathedral)
        }
        reverb.wetDryMix = bypassed ? 0 : Float(min(1, max(0, settings.reverbMix)) * 100)

        delay.delayTime = settings.delaySeconds(tempoBPM: tempoBPM)
        delay.feedback = bypassed ? 0 : Float(min(0.9, max(0, settings.delayFeedback)) * 100)
        delay.wetDryMix = bypassed ? 0 : Float(min(1, max(0, settings.delayMix)) * 100)
    }

}
