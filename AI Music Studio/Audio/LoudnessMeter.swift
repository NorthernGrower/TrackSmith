//
//  LoudnessMeter.swift
//  AI Music Studio
//

import AVFoundation
import Foundation

/// The loudness numbers shown by the mastering meters.
struct LoudnessReading: Equatable {
    var integrated: Double?
    var shortTerm: Double?
    var truePeak: Double?
    var measuredSeconds: Double = 0
}

/// Measures the master output the way an EBU R128 loudness meter does:
/// K-weighted blocks of 400 ms, gated for the integrated value, plus a peak hold.
final class LoudnessMeter: @unchecked Sendable {
    private struct Biquad {
        var b0: Float = 1
        var b1: Float = 0
        var b2: Float = 0
        var a1: Float = 0
        var a2: Float = 0
        var x1: Float = 0
        var x2: Float = 0
        var y1: Float = 0
        var y2: Float = 0

        mutating func process(_ input: Float) -> Float {
            let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = input
            y2 = y1
            y1 = output
            return output
        }

        mutating func reset() {
            x1 = 0
            x2 = 0
            y1 = 0
            y2 = 0
        }
    }

    private struct ChannelFilter {
        var shelf = Biquad()
        var highPass = Biquad()
    }

    private static let blockDuration = 0.4
    private static let maximumBlocks = 4_500

    private let lock = NSLock()
    private var sampleRate: Double = 0
    private var filters: [ChannelFilter] = []
    private var blockSums: [Double] = []
    private var blockFrames = 0
    private var blockTarget = 0
    private var blocks: [Double] = []
    private var peak: Float = 0
    private var framesMeasured: Double = 0

    /// Feeds one buffer of the master output. Called from the render thread.
    func ingest(buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let channels = Int(buffer.format.channelCount)
        let rate = buffer.format.sampleRate
        guard channels > 0, rate > 0 else { return }

        lock.lock()
        defer { lock.unlock() }

        if rate != sampleRate || filters.count != channels {
            configure(sampleRate: rate, channels: channels)
        }

        let frames = Int(buffer.frameLength)
        for channel in 0..<channels {
            let samples = data[channel]
            var filter = filters[channel]
            var sum = blockSums[channel]
            var highest = peak

            for index in 0..<frames {
                let sample = samples[index]
                let magnitude = abs(sample)
                if magnitude > highest { highest = magnitude }
                let shelf = filter.shelf.process(sample)
                let weighted = filter.highPass.process(shelf)
                sum += Double(weighted * weighted)
            }

            filters[channel] = filter
            blockSums[channel] = sum
            peak = highest
        }

        blockFrames += frames
        framesMeasured += Double(frames)

        if blockFrames >= blockTarget {
            var energy: Double = 0
            for channel in 0..<channels {
                energy += blockSums[channel] / Double(blockFrames)
                blockSums[channel] = 0
            }
            blocks.append(energy)
            if blocks.count > Self.maximumBlocks {
                blocks.removeFirst(blocks.count - Self.maximumBlocks)
            }
            blockFrames = 0
        }
    }

    /// The current integrated, short-term and true peak values.
    func snapshot() -> LoudnessReading {
        lock.lock()
        defer { lock.unlock() }

        // -70 LUFS is the absolute gate of the R128 measurement.
        let absoluteGate = pow(10.0, (-70.0 + 0.691) / 10.0)
        let gated = blocks.filter { $0 >= absoluteGate }

        var integrated: Double?
        if !gated.isEmpty {
            let ungatedMean = gated.reduce(0, +) / Double(gated.count)
            let relativeGate = ungatedMean * pow(10.0, -10.0 / 10.0)
            let above = gated.filter { $0 >= relativeGate }
            let mean = above.isEmpty ? ungatedMean : above.reduce(0, +) / Double(above.count)
            integrated = -0.691 + 10 * log10(max(mean, 1e-12))
        }

        let recent = blocks.suffix(8)
        var shortTerm: Double?
        if !recent.isEmpty {
            let mean = recent.reduce(0, +) / Double(recent.count)
            shortTerm = -0.691 + 10 * log10(max(mean, 1e-12))
        }

        let truePeak = peak > 0 ? 20 * log10(Double(peak)) : nil
        let seconds = sampleRate > 0 ? framesMeasured / sampleRate : 0
        return LoudnessReading(integrated: integrated, shortTerm: shortTerm, truePeak: truePeak, measuredSeconds: seconds)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        blocks.removeAll()
        blockSums = Array(repeating: 0, count: max(1, blockSums.count))
        blockFrames = 0
        peak = 0
        framesMeasured = 0
        for index in filters.indices {
            filters[index].shelf.reset()
            filters[index].highPass.reset()
        }
    }

    // MARK: - Filters

    private func configure(sampleRate rate: Double, channels: Int) {
        sampleRate = rate
        let shelf = Self.highShelf(
            sampleRate: rate,
            frequency: 1_681.974_507_615_453,
            gainDB: 4,
            q: 0.707_175_236_955_419_6
        )
        let highPass = Self.highPass(
            sampleRate: rate,
            frequency: 38.135_470_876_024_44,
            q: 0.500_327_037_323_877_3
        )
        filters = (0..<channels).map { _ in ChannelFilter(shelf: shelf, highPass: highPass) }
        blockSums = Array(repeating: 0, count: channels)
        blockTarget = max(1, Int((rate * Self.blockDuration).rounded()))
        blockFrames = 0
    }

    /// The +4 dB high shelf of the K-weighting curve.
    private static func highShelf(sampleRate: Double, frequency: Double, gainDB: Double, q: Double) -> Biquad {
        let a = pow(10.0, gainDB / 40.0)
        let w0 = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosW0 = cos(w0)
        let beta = 2 * sqrt(a) * alpha
        let a0 = (a + 1) - (a - 1) * cosW0 + beta

        var filter = Biquad()
        filter.b0 = Float(a * ((a + 1) + (a - 1) * cosW0 + beta) / a0)
        filter.b1 = Float(-2 * a * ((a - 1) + (a + 1) * cosW0) / a0)
        filter.b2 = Float(a * ((a + 1) + (a - 1) * cosW0 - beta) / a0)
        filter.a1 = Float(2 * ((a - 1) - (a + 1) * cosW0) / a0)
        filter.a2 = Float(((a + 1) - (a - 1) * cosW0 - beta) / a0)
        return filter
    }

    /// The 38 Hz high pass of the K-weighting curve.
    private static func highPass(sampleRate: Double, frequency: Double, q: Double) -> Biquad {
        let w0 = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosW0 = cos(w0)
        let a0 = 1 + alpha

        var filter = Biquad()
        filter.b0 = Float((1 + cosW0) / 2 / a0)
        filter.b1 = Float(-(1 + cosW0) / a0)
        filter.b2 = filter.b0
        filter.a1 = Float(-2 * cosW0 / a0)
        filter.a2 = Float((1 - alpha) / a0)
        return filter
    }
}
