//
//  OnDeviceStemSeparator.swift
//  AI Music Studio
//

import AVFoundation
import Foundation

struct ImportedStem: Sendable {
    let name: String
    let storedName: String
}

enum SeparationError: LocalizedError {
    case cannotReadFile
    case cannotWriteFile

    var errorDescription: String? {
        switch self {
        case .cannotReadFile:
            return "The song couldn't be read as audio."
        case .cannotWriteFile:
            return "The stems couldn't be written."
        }
    }
}

/// One section of a Linkwitz-Riley crossover (second-order Butterworth).
struct Biquad {
    enum Kind {
        case lowpass
        case highpass
    }

    private var b0: Float = 0
    private var b1: Float = 0
    private var b2: Float = 0
    private var a1: Float = 0
    private var a2: Float = 0

    private var x1: Float = 0
    private var x2: Float = 0
    private var y1: Float = 0
    private var y2: Float = 0

    init(kind: Kind, cutoff: Float, sampleRate: Float) {
        let w = 2 * .pi * min(cutoff, sampleRate * 0.45) / max(sampleRate, 1)
        let cosW = cos(w)
        let alpha = sin(w) / (2 * 0.7071)

        let a0 = 1 + alpha
        switch kind {
        case .lowpass:
            b0 = (1 - cosW) / 2 / a0
            b1 = (1 - cosW) / a0
            b2 = b0
        case .highpass:
            b0 = (1 + cosW) / 2 / a0
            b1 = -(1 + cosW) / a0
            b2 = b0
        }
        a1 = -2 * cosW / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
}

/// Four-way Linkwitz-Riley crossover: bass below 150 Hz, vocals 150-2500 Hz,
/// drums 2500-9000 Hz, other above 9 kHz. Each pair of outputs sums flat.
struct CrossoverChain {
    private var bassLP1: Biquad
    private var bassLP2: Biquad
    private var midHP1: Biquad
    private var midHP2: Biquad

    private var vocalsLP1: Biquad
    private var vocalsLP2: Biquad
    private var highsHP1: Biquad
    private var highsHP2: Biquad

    private var drumsLP1: Biquad
    private var drumsLP2: Biquad
    private var otherHP1: Biquad
    private var otherHP2: Biquad

    init(sampleRate: Float) {
        bassLP1 = Biquad(kind: .lowpass, cutoff: 150, sampleRate: sampleRate)
        bassLP2 = Biquad(kind: .lowpass, cutoff: 150, sampleRate: sampleRate)
        midHP1 = Biquad(kind: .highpass, cutoff: 150, sampleRate: sampleRate)
        midHP2 = Biquad(kind: .highpass, cutoff: 150, sampleRate: sampleRate)

        vocalsLP1 = Biquad(kind: .lowpass, cutoff: 2500, sampleRate: sampleRate)
        vocalsLP2 = Biquad(kind: .lowpass, cutoff: 2500, sampleRate: sampleRate)
        highsHP1 = Biquad(kind: .highpass, cutoff: 2500, sampleRate: sampleRate)
        highsHP2 = Biquad(kind: .highpass, cutoff: 2500, sampleRate: sampleRate)

        drumsLP1 = Biquad(kind: .lowpass, cutoff: 9000, sampleRate: sampleRate)
        drumsLP2 = Biquad(kind: .lowpass, cutoff: 9000, sampleRate: sampleRate)
        otherHP1 = Biquad(kind: .highpass, cutoff: 9000, sampleRate: sampleRate)
        otherHP2 = Biquad(kind: .highpass, cutoff: 9000, sampleRate: sampleRate)
    }

    mutating func process(_ x: Float) -> (bass: Float, vocals: Float, drums: Float, other: Float) {
        let bass = bassLP2.process(bassLP1.process(x))
        let mid = midHP2.process(midHP1.process(x))
        let vocals = vocalsLP2.process(vocalsLP1.process(mid))
        let highs = highsHP2.process(highsHP1.process(mid))
        let drums = drumsLP2.process(drumsLP1.process(highs))
        let other = otherHP2.process(otherHP1.process(highs))
        return (bass, vocals, drums, other)
    }
}

/// Splits a full song into four stems entirely on device, with no external service.
///
/// This is a frequency-band crossover split, not neural source separation: each
/// stem is the band of the original song between the crossover frequencies.
enum OnDeviceStemSeparator {

    static func separate(
        fileAt songURL: URL,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async throws -> [ImportedStem] {
        try await Task.detached {
            progress("Reading song…", 0)

            let scoped = songURL.startAccessingSecurityScopedResource()
            defer { if scoped { songURL.stopAccessingSecurityScopedResource() } }

            let file = try AVAudioFile(forReading: songURL)
            guard let input = try? AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  input.frameLength > 0 else {
                throw SeparationError.cannotReadFile
            }
            try file.read(into: input)

            let sampleRate = Float(file.processingFormat.sampleRate)
            let channelCount = Int(file.processingFormat.channelCount)
            let frameCount = Int(input.frameLength)

            progress("Splitting into stems…", 0.05)

            // bandOutputs[stem][channel][sample], stems ordered Vocals, Drums, Bass, Other.
            var bandOutputs = Array(repeating: [[Float]](), count: 4)
            let reportInterval = max(1, frameCount / 100)

            for channel in 0..<channelCount {
                guard let channelData = input.floatChannelData else {
                    throw SeparationError.cannotReadFile
                }
                let samples = channelData[channel]

                var bass = [Float](repeating: 0, count: frameCount)
                var vocals = [Float](repeating: 0, count: frameCount)
                var drums = [Float](repeating: 0, count: frameCount)
                var other = [Float](repeating: 0, count: frameCount)

                var chain = CrossoverChain(sampleRate: sampleRate)
                for i in 0..<frameCount {
                    let bands = chain.process(samples[i])
                    bass[i] = bands.bass
                    vocals[i] = bands.vocals
                    drums[i] = bands.drums
                    other[i] = bands.other

                    if i % reportInterval == 0 {
                        let fraction = 0.05 + 0.9 * Double(channel * frameCount + i) / Double(max(1, channelCount * frameCount))
                        progress("Splitting into stems…", fraction)
                    }
                }

                bandOutputs[0].append(vocals)
                bandOutputs[1].append(drums)
                bandOutputs[2].append(bass)
                bandOutputs[3].append(other)
            }

            progress("Writing stems…", 0.97)

            let stemNames: [(key: String, display: String)] = [
                ("vocals", "Vocals"),
                ("drums", "Drums"),
                ("bass", "Bass"),
                ("other", "Other"),
            ]

            var imported: [ImportedStem] = []
            for (stemIndex, stem) in stemNames.enumerated() {
                let storedName = "stem-\(UUID().uuidString.prefix(8))-\(stem.key).wav"
                let url = TrackStorage.url(forFileName: storedName)

                guard let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: Double(sampleRate),
                    channels: AVAudioChannelCount(channelCount),
                    interleaved: true
                ) else {
                    throw SeparationError.cannotWriteFile
                }

                guard let buffer = try? AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
                    throw SeparationError.cannotWriteFile
                }
                buffer.frameLength = AVAudioFrameCount(frameCount)
                guard let destination = buffer.floatChannelData else {
                    throw SeparationError.cannotWriteFile
                }

                for frame in 0..<frameCount {
                    for channel in 0..<channelCount {
                        destination[0][frame * channelCount + channel] = bandOutputs[stemIndex][channel][frame]
                    }
                }

                let audioFile = try AVAudioFile(
                    forWriting: url,
                    settings: format.settings,
                    commonFormat: .pcmFormatFloat32,
                    interleaved: true
                )
                try audioFile.write(from: buffer)
                imported.append(ImportedStem(name: stem.display, storedName: storedName))
            }

            progress("Stems ready.", 1)
            return imported
        }.value
    }
}
