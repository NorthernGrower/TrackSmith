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
        masterVolume: Float = 1,
        masterEffects: MasterEffectsSettings = MasterEffectsSettings(),
        tempoBPM: Int = 120,
        applyMuteSolo: Bool = true,
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let sampleRate = 44_100.0
        guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw RenderError.invalidFormat
        }

        let engine = AVAudioEngine()
        var queuedClips: [BounceClip] = []
        var queuedNotes: [BounceNote] = []
        var trackMixers: [UUID: AVAudioMixerNode] = [:]
        var duration: TimeInterval = 0
        let anySolo = tracks.contains { $0.isSoloed }

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
            let audible = !applyMuteSolo || (!track.isMuted && (!anySolo || track.isSoloed))
            trackMixer.outputVolume = audible ? track.volume * track.automationGain(at: 0) : 0
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
                guard let buffer = InstrumentSoundGenerator.synthNote(
                    frequency: SynthNote.frequency(for: note.pitch),
                    waveform: SynthNoteVoice.waveform,
                    cutoff: SynthNoteVoice.cutoff,
                    attack: SynthNoteVoice.attack,
                    release: SynthNoteVoice.release,
                    duration: note.duration + SynthNoteVoice.release,
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

        let output = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings)
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
                let audible = !applyMuteSolo || (!track.isMuted && (!anySolo || track.isSoloed))
                let automatedVolume = track.volume * track.automationGain(at: automationTime)
                trackMixers[track.id]?.outputVolume = audible ? automatedVolume : 0
                trackMixers[track.id]?.pan = min(1, max(-1, track.panAutomationValue(at: automationTime)))
            }
            let status = try engine.renderOffline(framesToRender, to: buffer)

            switch status {
            case .success:
                guard buffer.frameLength > 0 else { throw RenderError.renderFailed }
                try output.write(from: buffer)
                framesRendered += AVAudioFramePosition(buffer.frameLength)
                progress(min(1, Double(framesRendered) / Double(totalFrames)))
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
                try output.write(from: buffer)
                framesRendered += AVAudioFramePosition(framesToRender)
                progress(min(1, Double(framesRendered) / Double(totalFrames)))
            case .error:
                throw RenderError.renderFailed
            @unknown default:
                throw RenderError.renderFailed
            }
        }

        progress(1)
    }

    /// Renders one track on its own, with its mixer settings but without mute or solo.
    static func renderStem(
        track: Track,
        masterVolume: Float = 1,
        masterEffects: MasterEffectsSettings = MasterEffectsSettings(),
        tempoBPM: Int = 120,
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        try render(
            tracks: [track],
            masterVolume: masterVolume,
            masterEffects: masterEffects,
            tempoBPM: tempoBPM,
            applyMuteSolo: false,
            to: outputURL,
            progress: progress
        )
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
