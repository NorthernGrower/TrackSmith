//
//  InstrumentSoundGenerator.swift
//  AI Music Studio
//

import AVFoundation
import Foundation

enum SynthWaveform: String, CaseIterable, Identifiable {
    case sine
    case triangle
    case saw
    case square

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sine: return "Sine"
        case .triangle: return "Tri"
        case .saw: return "Saw"
        case .square: return "Square"
        }
    }
}

enum TB303Waveform: String, CaseIterable, Identifiable {
    case saw
    case square

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }
}

enum DrumPad: String, CaseIterable, Identifiable, Codable, Hashable {
    case kick
    case snare
    case lowTom
    case midTom
    case highTom
    case rimshot
    case clap
    case cowbell
    case closedHat
    case openHat
    case cymbal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kick: return "Bass Drum"
        case .snare: return "Snare"
        case .lowTom: return "Low Tom"
        case .midTom: return "Mid Tom"
        case .highTom: return "Hi Tom"
        case .rimshot: return "Rimshot"
        case .clap: return "Clap"
        case .cowbell: return "Cowbell"
        case .closedHat: return "Closed Hat"
        case .openHat: return "Open Hat"
        case .cymbal: return "Cymbal"
        }
    }

    var systemImage: String {
        switch self {
        case .kick, .lowTom, .midTom, .highTom: return "circle.fill"
        case .snare: return "circle.dashed"
        case .rimshot: return "circle.lefthalf.filled"
        case .clap: return "hand.clap.fill"
        case .cowbell: return "bell.fill"
        case .closedHat: return "triangle.fill"
        case .openHat: return "triangle"
        case .cymbal: return "sparkle"
        }
    }
}

struct DrumStep: Codable, Hashable {
    let pad: DrumPad
    let index: Int
}

struct DrumPattern: Codable, Equatable {
    static let stepCount = 16
    private(set) var activeSteps: Set<DrumStep> = []

    func contains(_ pad: DrumPad, step: Int) -> Bool {
        activeSteps.contains(DrumStep(pad: pad, index: step))
    }

    mutating func toggle(_ pad: DrumPad, step: Int) {
        let cell = DrumStep(pad: pad, index: step)
        if activeSteps.contains(cell) {
            activeSteps.remove(cell)
        } else {
            activeSteps.insert(cell)
        }
    }
}

enum InstrumentSoundGenerator {
    static func synthNote(
        frequency: Double,
        waveform: SynthWaveform,
        cutoff: Double,
        attack: Double,
        release: Double,
        duration: Double = 0.9,
        velocity: Float = 1,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let noteDuration = min(6, max(0.15, duration))
        let frameCount = max(1, Int(sampleRate * noteDuration))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let channels = buffer.floatChannelData else { return nil }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channelCount = Int(format.channelCount)
        let safeCutoff = min(max(100, cutoff), sampleRate * 0.46)
        let filterCoefficient = 1 - exp(-2 * Double.pi * safeCutoff / sampleRate)
        let safeAttack = min(max(0.005, attack), noteDuration * 0.8)
        let safeRelease = min(max(0.02, release), noteDuration * 0.8)
        let releaseStart = max(safeAttack, noteDuration - safeRelease)

        for channel in 0..<channelCount {
            var filteredSample = 0.0
            for frame in 0..<frameCount {
                let time = Double(frame) / sampleRate
                let phase = (time * frequency).truncatingRemainder(dividingBy: 1)
                let rawSample: Double
                switch waveform {
                case .sine:
                    rawSample = sin(2 * Double.pi * phase)
                case .triangle:
                    rawSample = 2 * asin(sin(2 * Double.pi * phase)) / Double.pi
                case .saw:
                    rawSample = 2 * phase - 1
                case .square:
                    rawSample = phase < 0.5 ? 1 : -1
                }

                let envelope: Double
                if time < safeAttack {
                    envelope = time / safeAttack
                } else if time > releaseStart {
                    envelope = max(0, (noteDuration - time) / max(0.001, noteDuration - releaseStart))
                } else {
                    envelope = 1
                }

                filteredSample += filterCoefficient * (rawSample - filteredSample)
                channels[channel][frame] = Float(filteredSample * envelope * 0.22 * Double(min(1, max(0, velocity))))
            }
        }

        return buffer
    }

    static func tb303Note(
        frequency: Double,
        waveform: TB303Waveform,
        cutoff: Double,
        resonance: Double,
        envelopeAmount: Double,
        decay: Double,
        accent: Bool,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let noteDecay = min(max(0.16, decay), 1.2)
        let duration = noteDecay + 0.12
        let frameCount = max(1, Int(sampleRate * duration))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let channelCount = Int(format.channelCount)
        let q = 0.72 + min(max(0, resonance), 1) * 11.5
        let baseCutoff = min(max(90, cutoff), sampleRate * 0.38)
        let sweep = min(max(0, envelopeAmount), 1) * 7_200
        let accentGain = accent ? 1.45 : 1.0

        for channel in 0..<channelCount {
            var integratorOne = 0.0
            var integratorTwo = 0.0

            for frame in 0..<frameCount {
                let time = Double(frame) / sampleRate
                let phase = (time * frequency).truncatingRemainder(dividingBy: 1)
                let oscillator: Double
                switch waveform {
                case .saw:
                    oscillator = 2 * phase - 1
                case .square:
                    oscillator = phase < 0.5 ? 1 : -1
                }

                let filterEnvelope = sweep * exp(-time / max(0.06, noteDecay * 0.42))
                let filterCutoff = min(sampleRate * 0.42, baseCutoff + filterEnvelope)
                let g = tan(Double.pi * filterCutoff / sampleRate)
                let k = 1 / q
                let a1 = 1 / (1 + g * (g + k))
                let a2 = g * a1
                let a3 = g * a2
                let v3 = oscillator - integratorTwo
                let v1 = a1 * integratorOne + a2 * v3
                let v2 = integratorTwo + a2 * integratorOne + a3 * v3
                integratorOne = 2 * v1 - integratorOne
                integratorTwo = 2 * v2 - integratorTwo

                let ampEnvelope = exp(-time / max(0.08, noteDecay * 0.85))
                let driven = tanh(v2 * (accent ? 3.8 : 2.5))
                channels[channel][frame] = Float(driven * ampEnvelope * accentGain * 0.27)
            }
        }

        return buffer
    }

    static func drumHit(_ pad: DrumPad, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let duration: Double
        switch pad {
        case .kick: duration = 0.72
        case .snare: duration = 0.52
        case .lowTom, .midTom, .highTom: duration = 0.55
        case .rimshot: duration = 0.2
        case .clap: duration = 0.48
        case .cowbell: duration = 0.42
        case .closedHat: duration = 0.18
        case .openHat: duration = 0.72
        case .cymbal: duration = 1.25
        }

        let frameCount = max(1, Int(sampleRate * duration))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let channelCount = Int(format.channelCount)
        let metallicPartials = [2_050.0, 2_740.0, 3_180.0, 3_710.0, 4_250.0, 4_900.0]
        var previousNoise = 0.0
        for frame in 0..<frameCount {
            let time = Double(frame) / sampleRate
            let noise = Double.random(in: -1...1)
            let highNoise = noise - previousNoise
            let sample: Double

            switch pad {
            case .kick:
                let phase = 50 * time + (118 / 18) * (1 - exp(-18 * time))
                let body = sin(2 * Double.pi * phase) * exp(-time * 5.8)
                let sub = sin(2 * Double.pi * 48 * time) * exp(-time * 4.5)
                let click = noise * exp(-time * 150) * 0.09
                sample = body * 0.72 + sub * 0.25 + click
            case .snare:
                let body = sin(2 * Double.pi * 185 * time) * exp(-time * 14)
                let rattle = highNoise * exp(-time * 10)
                sample = body * 0.42 + rattle * 0.7
            case .lowTom, .midTom, .highTom:
                let base: Double
                let sweep: Double
                switch pad {
                case .lowTom: base = 70; sweep = 105
                case .midTom: base = 105; sweep = 145
                default: base = 155; sweep = 185
                }
                let phase = base * time + (sweep / 10) * (1 - exp(-10 * time))
                sample = sin(2 * Double.pi * phase) * exp(-time * 6.5)
            case .rimshot:
                let tone = sin(2 * Double.pi * 1_640 * time) + 0.55 * sin(2 * Double.pi * 2_180 * time)
                sample = tone * exp(-time * 31) + noise * exp(-time * 105) * 0.12
            case .clap:
                let burstTimes = [0.0, 0.026, 0.053, 0.082]
                let burst = burstTimes.reduce(0.0) { value, start in
                    value + (time >= start ? exp(-(time - start) * 95) : 0)
                }
                sample = noise * burst * exp(-time * 4.8)
            case .cowbell:
                let metal = sin(2 * Double.pi * 562 * time) + 0.8 * sin(2 * Double.pi * 845 * time)
                sample = metal * exp(-time * 5.5)
            case .closedHat, .openHat, .cymbal:
                let decay: Double
                let noiseMix: Double
                switch pad {
                case .closedHat: decay = 24; noiseMix = 0.48
                case .openHat: decay = 5.2; noiseMix = 0.42
                default: decay = 2.6; noiseMix = 0.35
                }
                let metallic = metallicPartials.reduce(0.0) { sum, partial in
                    sum + sin(2 * Double.pi * partial * time)
                } / Double(metallicPartials.count)
                sample = (metallic * (1 - noiseMix) + highNoise * noiseMix) * exp(-time * decay)
            }

            previousNoise = noise
            let value = Float(tanh(sample * 1.7) * 0.34)
            for channel in 0..<channelCount {
                channels[channel][frame] = value
            }
        }

        return buffer
    }
}
