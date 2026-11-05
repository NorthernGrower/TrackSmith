//
//  TrackFreezeRenderer.swift
//  AI Music Studio
//

import AVFoundation
import Foundation

/// Renders one track's clips and arrangement notes into a single audio file.
enum TrackFreezeRenderer {
    enum FreezeError: LocalizedError {
        case noMaterial
        case invalidFormat
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .noMaterial:
                return "This track has no audio or notes to freeze yet."
            case .invalidFormat:
                return "The track could not be prepared in a supported audio format."
            case .renderFailed:
                return "The audio engine could not finish freezing this track."
            }
        }
    }

    static func render(track: Track, tempoBPM: Int = 120, to outputURL: URL) throws -> TimeInterval {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw FreezeError.invalidFormat
        }

        let engine = AVAudioEngine()
        let mixer = AVAudioMixerNode()
        let equalizer = AVAudioUnitEQ(numberOfBands: 3)
        let compressor = TrackCompressorUnit.make()

        engine.attach(mixer)
        engine.attach(equalizer)
        engine.attach(compressor)
        engine.connect(mixer, to: equalizer, format: format)
        engine.connect(equalizer, to: compressor, format: format)
        engine.connect(compressor, to: engine.mainMixerNode, format: format)
        mixer.outputVolume = 1
        mixer.pan = 0
        configure(equalizer, settings: track.eqSettings)
        TrackCompressorUnit.configure(compressor, settings: track.compressorSettings)

        var queuedClips: [(file: AVAudioFile, player: AVAudioPlayerNode, mixer: AVAudioMixerNode, clip: AudioClip)] = []
        var queuedNotes: [(buffer: AVAudioPCMBuffer, player: AVAudioPlayerNode, start: TimeInterval)] = []
        var span: TimeInterval = 0

        for clip in track.clips {
            let sourceURL = TrackStorage.url(forFileName: clip.fileName)
            guard let file = try? AVAudioFile(forReading: sourceURL),
                  file.processingFormat.sampleRate > 0 else { continue }

            let playableDuration = min(
                clip.duration,
                max(0, clip.sourceDuration - clip.sourceStartTime)
            )
            guard playableDuration > 0 else { continue }

            let player = AVAudioPlayerNode()
            let clipMixer = AVAudioMixerNode()
            engine.attach(player)
            engine.attach(clipMixer)
            engine.connect(player, to: clipMixer, format: file.processingFormat)
            engine.connect(clipMixer, to: mixer, format: file.processingFormat)
            queuedClips.append((file, player, clipMixer, clip))
            span = max(span, clip.startTime + playableDuration)
        }

        for note in track.playedNotes(tempoBPM: tempoBPM) {
            let noteDuration = note.duration
                + (track.voice == .synth ? SynthNoteVoice.release : track.voice.releaseTail)
            guard let buffer = InstrumentSoundGenerator.voicedNote(
                frequency: SynthNote.frequency(for: note.pitch),
                voice: track.voice,
                duration: noteDuration,
                velocity: note.velocity,
                format: format
            ) else { continue }

            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mixer, format: format)
            queuedNotes.append((buffer, player, note.startTime))
            span = max(span, note.endTime)
        }

        guard span > 0, !queuedClips.isEmpty || !queuedNotes.isEmpty else {
            throw FreezeError.noMaterial
        }

        for queued in queuedClips {
            let sourceRate = queued.file.processingFormat.sampleRate
            let startFrame = AVAudioFramePosition(queued.clip.sourceStartTime * sourceRate)
            let requestedFrames = AVAudioFramePosition(
                min(queued.clip.duration, queued.clip.sourceDuration - queued.clip.sourceStartTime) * sourceRate
            )
            let frames = min(queued.file.length - startFrame, requestedFrames)
            guard startFrame >= 0, frames > 0 else { continue }

            let startSample = AVAudioFramePosition(max(0, queued.clip.startTime) * sampleRate)
            queued.player.scheduleSegment(
                queued.file,
                startingFrame: startFrame,
                frameCount: AVAudioFrameCount(min(frames, Int64(UInt32.max))),
                at: AVAudioTime(sampleTime: startSample, atRate: sampleRate)
            )
            queued.player.play()
        }

        for queued in queuedNotes {
            let startSample = AVAudioFramePosition(max(0, queued.start) * sampleRate)
            queued.player.scheduleBuffer(
                queued.buffer,
                at: AVAudioTime(sampleTime: startSample, atRate: sampleRate),
                options: []
            )
            queued.player.play()
        }

        let maximumFrameCount: AVAudioFrameCount = 512
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maximumFrameCount)
        engine.prepare()
        try engine.start()
        defer { engine.stop() }

        let output = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFrameCount) else {
            throw FreezeError.invalidFormat
        }

        let totalFrames = AVAudioFramePosition(ceil(span * sampleRate))
        var framesRendered: AVAudioFramePosition = 0

        while framesRendered < totalFrames {
            let framesToRender = AVAudioFrameCount(min(Int64(maximumFrameCount), totalFrames - framesRendered))
            let renderTime = Double(framesRendered) / sampleRate
            for queued in queuedClips {
                queued.mixer.outputVolume = queued.clip.gain(at: renderTime, in: track)
            }
            let status = try engine.renderOffline(framesToRender, to: buffer)

            switch status {
            case .success:
                guard buffer.frameLength > 0 else { throw FreezeError.renderFailed }
                try output.write(from: buffer)
                framesRendered += AVAudioFramePosition(buffer.frameLength)
            case .cannotDoInCurrentContext:
                Thread.sleep(forTimeInterval: 0.001)
            case .insufficientDataFromInputNode:
                guard let channels = buffer.floatChannelData else { throw FreezeError.renderFailed }
                for channel in 0..<Int(format.channelCount) {
                    for frame in 0..<Int(framesToRender) {
                        channels[channel][frame] = 0
                    }
                }
                buffer.frameLength = framesToRender
                try output.write(from: buffer)
                framesRendered += AVAudioFramePosition(framesToRender)
            case .error:
                throw FreezeError.renderFailed
            @unknown default:
                throw FreezeError.renderFailed
            }
        }

        return span
    }

    private static func configure(_ equalizer: AVAudioUnitEQ, settings: TrackEQSettings) {
        guard equalizer.bands.count >= 3 else { return }

        let low = equalizer.bands[0]
        low.filterType = .lowShelf
        low.frequency = Float(settings.lowFrequency)
        low.gain = Float(settings.lowGain)
        low.bypass = settings.isBypassed

        let mid = equalizer.bands[1]
        mid.filterType = .parametric
        mid.frequency = Float(settings.midFrequency)
        mid.bandwidth = 1
        mid.gain = Float(settings.midGain)
        mid.bypass = settings.isBypassed

        let high = equalizer.bands[2]
        high.filterType = .highShelf
        high.frequency = Float(settings.highFrequency)
        high.gain = Float(settings.highGain)
        high.bypass = settings.isBypassed
    }
}
