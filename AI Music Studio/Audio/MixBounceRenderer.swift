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
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let sampleRate = 44_100.0
        guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw RenderError.invalidFormat
        }

        let engine = AVAudioEngine()
        var queuedClips: [BounceClip] = []
        var duration: TimeInterval = 0
        let anySolo = tracks.contains { $0.isSoloed }

        for track in tracks {
            let trackMixer = AVAudioMixerNode()
            engine.attach(trackMixer)
            engine.connect(trackMixer, to: engine.mainMixerNode, format: outputFormat)
            let audible = !track.isMuted && (!anySolo || track.isSoloed)
            trackMixer.outputVolume = audible ? track.volume : 0

            for clip in track.clips {
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
        }

        guard !queuedClips.isEmpty, duration > 0 else { throw RenderError.noAudio }

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

        let maximumFrameCount: AVAudioFrameCount = 4096
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
}
