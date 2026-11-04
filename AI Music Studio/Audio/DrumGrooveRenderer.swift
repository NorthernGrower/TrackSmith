//
//  DrumGrooveRenderer.swift
//  AI Music Studio
//

import AVFoundation
import Foundation

/// Renders a whole drum performance of a generated song into one audio file,
/// using the chosen kit so the arrangement stays light on playback voices.
enum DrumGrooveRenderer {
    struct RenderedGroove {
        let fileName: String
        let duration: TimeInterval
    }

    private struct Voice {
        let pad: DrumPad
        let steps: [Int]
        let level: Double
        let maximumLength: TimeInterval
    }

    static func render(
        kit: DrumKit,
        groove: GenreGroove,
        bars: Int,
        tempo: Int,
        token: String
    ) -> RenderedGroove? {
        guard bars > 0 else { return nil }
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            return nil
        }

        let beat = 60.0 / Double(tempo)
        let stepDuration = beat / 4
        let grooveDuration = Double(bars) * beat * 4
        let totalFrames = max(1, Int((grooveDuration + 0.4) * sampleRate))

        guard let mix = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)),
              let mixChannels = mix.floatChannelData else { return nil }
        mix.frameLength = AVAudioFrameCount(totalFrames)

        let channelCount = Int(format.channelCount)
        for channel in 0..<channelCount {
            for frame in 0..<totalFrames {
                mixChannels[channel][frame] = 0
            }
        }

        let voices = [
            Voice(pad: .kick, steps: groove.kick, level: 0.92, maximumLength: 0.6),
            Voice(pad: .snare, steps: groove.snare, level: 0.7, maximumLength: 0.4),
            Voice(pad: .closedHat, steps: groove.closedHat, level: 0.34, maximumLength: 0.16),
            Voice(pad: .openHat, steps: groove.openHat, level: 0.3, maximumLength: 0.5),
            Voice(pad: .clap, steps: groove.clap, level: 0.44, maximumLength: 0.3),
        ]

        for voice in voices where !voice.steps.isEmpty {
            guard let hit = InstrumentSoundGenerator.drumHit(
                voice.pad,
                volume: voice.level * kit.level,
                tuning: kit.tuning,
                decay: kit.decay,
                tone: kit.tone,
                format: format
            ), let hitChannels = hit.floatChannelData else { continue }

            let hitFrames = Int(hit.frameLength)
            let maximumFrames = min(
                Int(voice.maximumLength * sampleRate),
                hitFrames
            )
            guard maximumFrames > 0 else { continue }

            for barIndex in 0..<bars {
                for step in voice.steps {
                    let startTime = (Double(barIndex) * 16 + Double(step)) * stepDuration
                    let startFrame = Int(startTime * sampleRate)
                    guard startFrame < totalFrames else { continue }

                    for frame in 0..<maximumFrames {
                        let target = startFrame + frame
                        guard target < totalFrames else { break }
                        let sample = hitChannels[0][frame]
                        for channel in 0..<channelCount {
                            mixChannels[channel][target] += sample
                        }
                    }
                }
            }
        }

        // Keep summed hits inside a safe ceiling.
        for channel in 0..<channelCount {
            for frame in 0..<totalFrames {
                mixChannels[channel][frame] = tanh(mixChannels[channel][frame] * 1.15)
            }
        }

        let safeToken = token
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let fileName = "groove-\(kit.rawValue)-\(safeToken)-\(tempo)bpm-\(bars)bars.wav"
        let url = TrackStorage.url(forFileName: fileName)
        try? FileManager.default.removeItem(at: url)

        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else {
            return nil
        }
        do {
            try file.write(from: mix)
        } catch {
            return nil
        }

        return RenderedGroove(fileName: fileName, duration: grooveDuration)
    }
}
