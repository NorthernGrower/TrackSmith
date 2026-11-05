//
//  PunchTakeRenderer.swift
//  AI Music Studio
//

import AVFoundation
import Foundation

/// Cuts the punched region out of a recording and bakes short fades into its
/// edges, so it can be crossfaded into the audio already on the track.
enum PunchTakeRenderer {
    static func render(
        sourceURL: URL,
        offset: TimeInterval,
        duration: TimeInterval,
        crossFade: TimeInterval
    ) -> (url: URL, duration: TimeInterval)? {
        guard duration > 0,
              let input = try? AVAudioFile(forReading: sourceURL) else { return nil }

        let format = input.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return nil }

        let startFrame = AVAudioFramePosition(max(0, offset) * sampleRate)
        guard startFrame >= 0, input.length > startFrame else { return nil }

        let wantedFrames = AVAudioFrameCount(min(
            Double(input.length - startFrame),
            max(64, duration * sampleRate)
        ))
        guard wantedFrames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: wantedFrames) else {
            return nil
        }

        do {
            try input.read(into: buffer)
        } catch {
            return nil
        }

        let frames = Int(buffer.frameLength)
        guard frames > 0, let channels = buffer.floatChannelData else { return nil }

        let fadeFrames = max(1, min(
            Int(crossFade * sampleRate),
            max(1, frames / 4)
        ))
        let lastFrame = Double(max(0, frames - 1))

        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<frames {
                var gain = 1.0
                if frame < fadeFrames {
                    gain = Double(frame) / Double(crossFade <= 0 ? 1 : fadeFrames)
                } else if frame >= frames - fadeFrames {
                    gain = (lastFrame - Double(frame)) / Double(crossFade <= 0 ? 1 : fadeFrames)
                }
                channels[channel][frame] *= Float(min(1, max(0, gain)))
            }
        }

        let extensionName = sourceURL.pathExtension.isEmpty ? "caf" : sourceURL.pathExtension
        let outputURL = TrackStorage.uniqueStemURL(baseName: "punch-take", fileExtension: extensionName)

        guard let output = try? AVAudioFile(forWriting: outputURL, settings: format.settings) else {
            return nil
        }
        do {
            try output.write(from: buffer)
        } catch {
            return nil
        }

        return (outputURL, Double(frames) / sampleRate)
    }
}
