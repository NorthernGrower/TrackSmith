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
        tuning: Double = 1,
        level: Double = 1,
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
        let safeTuning = min(1.5, max(0.5, tuning))
        let safeLevel = min(1, max(0, level))

        for channel in 0..<channelCount {
            var integratorOne = 0.0
            var integratorTwo = 0.0

            for frame in 0..<frameCount {
                let time = Double(frame) / sampleRate
                let phase = (time * frequency * safeTuning).truncatingRemainder(dividingBy: 1)
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
                channels[channel][frame] = Float(driven * ampEnvelope * accentGain * 0.27 * safeLevel)
            }
        }

        return buffer
    }

    static func drumHit(
        _ pad: DrumPad,
        volume: Double = 1,
        tuning: Double = 1,
        decay: Double = 1,
        tone: Double = 0.6,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let safeVolume = min(1, max(0, volume))
        let safeTuning = min(1.5, max(0.5, tuning))
        let safeDecay = min(2, max(0.4, decay))
        let safeTone = min(1, max(0, tone))
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

        let frameCount = max(1, Int(sampleRate * duration * safeDecay))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let channelCount = Int(format.channelCount)
        let metallicPartials = [2_050.0, 2_740.0, 3_180.0, 3_710.0, 4_250.0, 4_900.0]
        let brightness = 0.55 + safeTone * 0.9
        var previousNoise = 0.0
        for frame in 0..<frameCount {
            let time = Double(frame) / sampleRate
            let envelopeTime = time / safeDecay
            let phaseTime = time * safeTuning
            let noise = Double.random(in: -1...1)
            let highNoise = (noise - previousNoise) * brightness
            let sample: Double

            switch pad {
            case .kick:
                let phase = 50 * phaseTime + (118 / 18) * (1 - exp(-18 * phaseTime))
                let body = sin(2 * Double.pi * phase) * exp(-envelopeTime * 5.8)
                let sub = sin(2 * Double.pi * 48 * phaseTime) * exp(-envelopeTime * 4.5)
                let click = noise * exp(-envelopeTime * 150) * 0.09 * brightness
                sample = body * 0.72 + sub * 0.25 + click
            case .snare:
                let body = sin(2 * Double.pi * 185 * phaseTime) * exp(-envelopeTime * 14)
                let rattle = highNoise * exp(-envelopeTime * 10)
                sample = body * 0.42 + rattle * 0.7
            case .lowTom, .midTom, .highTom:
                let base: Double
                let sweep: Double
                switch pad {
                case .lowTom: base = 70; sweep = 105
                case .midTom: base = 105; sweep = 145
                default: base = 155; sweep = 185
                }
                let phase = base * phaseTime + (sweep / 10) * (1 - exp(-10 * phaseTime))
                sample = sin(2 * Double.pi * phase) * exp(-envelopeTime * 6.5)
            case .rimshot:
                let hitTone = sin(2 * Double.pi * 1_640 * phaseTime) + 0.55 * sin(2 * Double.pi * 2_180 * phaseTime)
                sample = hitTone * exp(-envelopeTime * 31) + noise * exp(-envelopeTime * 105) * 0.12 * brightness
            case .clap:
                let burstTimes = [0.0, 0.026, 0.053, 0.082]
                let burst = burstTimes.reduce(0.0) { value, start in
                    value + (time >= start ? exp(-((time - start) / safeDecay) * 95) : 0)
                }
                sample = noise * burst * exp(-envelopeTime * 4.8) * brightness
            case .cowbell:
                let metal = sin(2 * Double.pi * 562 * phaseTime) + 0.8 * sin(2 * Double.pi * 845 * phaseTime)
                sample = metal * exp(-envelopeTime * 5.5)
            case .closedHat, .openHat, .cymbal:
                let hatDecay: Double
                let noiseMix: Double
                switch pad {
                case .closedHat: hatDecay = 24; noiseMix = 0.48
                case .openHat: hatDecay = 5.2; noiseMix = 0.42
                default: hatDecay = 2.6; noiseMix = 0.35
                }
                let metallic = metallicPartials.reduce(0.0) { sum, partial in
                    sum + sin(2 * Double.pi * partial * brightness * phaseTime)
                } / Double(metallicPartials.count)
                sample = (metallic * (1 - noiseMix) + highNoise * noiseMix) * exp(-envelopeTime * hatDecay)
            }

            previousNoise = noise
            let value = Float(tanh(sample * 1.7) * 0.34 * safeVolume)
            for channel in 0..<channelCount {
                channels[channel][frame] = value
            }
        }

        return buffer
    }

    // MARK: - Voiced instruments

    /// Plays a note with the voice a track was arranged for.
    static func voicedNote(
        frequency: Double,
        voice: TrackVoiceKind,
        duration: Double,
        velocity: Float = 1,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        switch voice {
        case .synth:
            return synthNote(
                frequency: frequency,
                waveform: SynthNoteVoice.waveform,
                cutoff: SynthNoteVoice.cutoff,
                attack: SynthNoteVoice.attack,
                release: SynthNoteVoice.release,
                duration: duration,
                velocity: velocity,
                format: format
            )
        case .marleneVocal:
            return vocalNote(
                frequency: frequency,
                duration: duration,
                velocity: velocity,
                format: format
            )
        case .acousticGuitar, .electricGuitar, .distortedGuitar, .bassGuitar:
            return pluckedNote(
                frequency: frequency,
                voice: voice,
                duration: duration,
                velocity: velocity,
                format: format
            )
        }
    }

    /// A sung vowel note: a glottal saw shaped by three formants with a slow vibrato.
    static func vocalNote(
        frequency: Double,
        duration: Double,
        velocity: Float = 1,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let noteDuration = min(6, max(0.2, duration))
        let frameCount = max(1, Int(sampleRate * noteDuration))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let channelCount = Int(format.channelCount)
        // Formant centres and bandwidths for a female "ah" vowel.
        let formants: [(frequency: Double, bandwidth: Double, gain: Double)] = [
            (880, 90, 1.0),
            (1_260, 110, 0.6),
            (2_860, 170, 0.28),
        ]
        let attack = min(0.06, noteDuration * 0.3)
        let release = min(0.26, noteDuration * 0.4)
        let releaseStart = max(attack, noteDuration - release)
        let safeVelocity = Double(min(1, max(0, velocity)))

        for channel in 0..<channelCount {
            var resonators = formants.map {
                FormantResonator(frequency: $0.frequency, bandwidth: $0.bandwidth, sampleRate: sampleRate)
            }
            var phase = 0.0
            var breath = 0.0

            for frame in 0..<frameCount {
                let time = Double(frame) / sampleRate
                let vibrato = 1
                    + 0.011 * sin(2 * Double.pi * 5.1 * time)
                    + 0.004 * sin(2 * Double.pi * 0.7 * time)
                phase += frequency * vibrato / sampleRate
                phase -= phase.rounded(.down)

                let glottal = 2 * phase - 1
                let shaped = glottal * 0.75 + sin(2 * Double.pi * phase * 2) * 0.12
                var sample = 0.0
                for index in resonators.indices {
                    sample += resonators[index].process(shaped) * formants[index].gain
                }

                let noise = Double.random(in: -1...1)
                breath += 0.05 * (noise - breath)
                sample += breath * 0.07

                let envelope: Double
                if time < attack {
                    envelope = time / attack
                } else if time > releaseStart {
                    envelope = max(0, (noteDuration - time) / max(0.001, noteDuration - releaseStart))
                } else {
                    envelope = 1
                }

                channels[channel][frame] = Float(sample * envelope * 0.20 * safeVelocity)
            }
        }

        return buffer
    }

    /// A plucked string rendered with a Karplus-Strong delay line.
    static func pluckedNote(
        frequency: Double,
        voice: TrackVoiceKind,
        duration: Double,
        velocity: Float = 1,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let safeFrequency = min(sampleRate * 0.4, max(30, frequency))

        let decay: Double
        let brightness: Double
        let drive: Double
        let level: Double
        switch voice {
        case .acousticGuitar:
            decay = 1.6
            brightness = 3_400
            drive = 1.5
            level = 0.32
        case .electricGuitar:
            decay = 2.1
            brightness = 2_500
            drive = 2.0
            level = 0.29
        case .distortedGuitar:
            decay = 2.7
            brightness = 2_000
            drive = 5.2
            level = 0.25
        case .bassGuitar:
            decay = 1.9
            brightness = 900
            drive = 1.8
            level = 0.36
        default:
            decay = 1.5
            brightness = 2_600
            drive = 1.6
            level = 0.3
        }

        let noteDuration = min(2.4, max(0.15, duration))
        let frameCount = max(1, Int(sampleRate * noteDuration))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let delayLength = max(2, Int(sampleRate / safeFrequency))
        var delay = [Double](repeating: 0, count: delayLength)
        let excitationCutoff = min(brightness, sampleRate * 0.4)
        let excitationCoefficient = 1 - exp(-2 * Double.pi * excitationCutoff / sampleRate)
        var filteredNoise = 0.0
        var excitationMean = 0.0
        for index in delay.indices {
            let noise = Double.random(in: -1...1)
            filteredNoise += excitationCoefficient * (noise - filteredNoise)
            delay[index] = filteredNoise
            excitationMean += filteredNoise
        }
        excitationMean /= Double(delayLength)
        for index in delay.indices {
            delay[index] -= excitationMean
        }

        let damping = pow(10, -3.0 / (decay * sampleRate))
        let toneCoefficient = 1 - exp(-2 * Double.pi * min(brightness, 6_000) / sampleRate)
        let releaseStart = noteDuration * 0.7
        let safeVelocity = Double(min(1, max(0, velocity)))

        var index = 0
        var lowpassed = 0.0
        var output = [Double](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            let current = delay[index]
            lowpassed += toneCoefficient * (current - lowpassed)

            let next = (delay[index] + delay[(index + 1) % delayLength]) * 0.5 * damping
            delay[index] = next
            index = (index + 1) % delayLength

            let time = Double(frame) / sampleRate
            let envelope = time > releaseStart
                ? max(0, (noteDuration - time) / max(0.001, noteDuration - releaseStart))
                : 1

            output[frame] = tanh(lowpassed * drive * 2.4) * envelope
        }

        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<frameCount {
                channels[channel][frame] = Float(output[frame] * level * safeVelocity)
            }
        }

        return buffer
    }
}

/// Two-pole band-pass resonator used to shape the vocal formants.
private struct FormantResonator {
    private let b0: Double
    private let b2: Double
    private let a1: Double
    private let a2: Double
    private var z1 = 0.0
    private var z2 = 0.0

    init(frequency: Double, bandwidth: Double, sampleRate: Double) {
        let safeFrequency = min(max(60, frequency), sampleRate * 0.45)
        let w0 = 2 * Double.pi * safeFrequency / sampleRate
        let alpha = sin(w0) * bandwidth / (2 * safeFrequency)
        let a0 = 1 + alpha
        b0 = alpha / a0
        b2 = -alpha / a0
        a1 = (-2 * cos(w0)) / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ input: Double) -> Double {
        let output = b0 * input + z1
        z1 = -a1 * output + z2
        z2 = b2 * input - a2 * output
        return output
    }
}
