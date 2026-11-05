//
//  Arpeggiator.swift
//  AI Music Studio
//

import Foundation

/// The order an arpeggiator walks through the held notes.
enum ArpeggiatorPattern: String, Codable, CaseIterable, Identifiable {
    case up
    case down
    case upDown
    case random

    var id: String { rawValue }

    var title: String {
        switch self {
        case .up: return "Up"
        case .down: return "Down"
        case .upDown: return "Up-Down"
        case .random: return "Random"
        }
    }
}

/// How fast the arpeggiator steps.
enum ArpeggiatorRate: String, Codable, CaseIterable, Identifiable {
    case eighth = "1/8"
    case sixteenth = "1/16"
    case thirtySecond = "1/32"

    var id: String { rawValue }
    var title: String { rawValue }

    /// Length of one step in beats.
    var beats: Double {
        switch self {
        case .eighth: return 0.5
        case .sixteenth: return 0.25
        case .thirtySecond: return 0.125
        }
    }
}

/// The arpeggiator settings saved with one track.
struct ArpeggiatorSettings: Codable, Equatable {
    var isEnabled = false
    var pattern: ArpeggiatorPattern = .up
    var rate: ArpeggiatorRate = .sixteenth
    /// How many octaves the held notes are spread across, 1 to 4.
    var octaveRange = 1
    /// How much of each step the note sounds for, 0.05 to 1.
    var gate = 0.7
    /// Delay applied to every second step, as a fraction of the step.
    var swing = 0.0

    static let octaveRangeRange = 1...4
    static let gateRange = 0.05...1.0
    static let swingRange = 0.0...0.4

    func stepDuration(tempoBPM: Int) -> TimeInterval {
        let tempo = Double(min(200, max(60, tempoBPM)))
        return 60.0 / tempo * rate.beats
    }
}

/// Turns held notes into arpeggios for playback, freezing and bouncing.
enum Arpeggiator {
    static func expanded(
        notes: [SynthNote],
        settings: ArpeggiatorSettings,
        tempoBPM: Int
    ) -> [SynthNote] {
        guard settings.isEnabled, !notes.isEmpty else { return notes }

        let step = max(0.01, settings.stepDuration(tempoBPM: tempoBPM))
        let tolerance = step * 0.5
        let sorted = notes.sorted { $0.startTime < $1.startTime }

        // Group notes that start together into one held chord.
        var clusters: [[SynthNote]] = []
        for note in sorted {
            if let lastIndex = clusters.indices.last,
               let clusterStart = clusters[lastIndex].map(\.startTime).min(),
               abs(note.startTime - clusterStart) <= tolerance {
                clusters[lastIndex].append(note)
            } else {
                clusters.append([note])
            }
        }

        var result: [SynthNote] = []
        for (clusterIndex, cluster) in clusters.enumerated() {
            let start = cluster.map(\.startTime).min() ?? 0
            let end = cluster.map(\.endTime).max() ?? (start + step)
            let velocity = cluster.map(\.velocity).max() ?? 0.8
            let basePitches = Array(Set(cluster.map(\.pitch))).sorted()
            guard !basePitches.isEmpty else { continue }

            var pitches: [Int] = []
            let octaves = min(ArpeggiatorSettings.octaveRangeRange.upperBound,
                              max(ArpeggiatorSettings.octaveRangeRange.lowerBound, settings.octaveRange))
            for octave in 0..<octaves {
                pitches.append(contentsOf: basePitches.map { $0 + 12 * octave })
            }

            let order: [Int]
            switch settings.pattern {
            case .up:
                order = pitches
            case .down:
                order = Array(pitches.reversed())
            case .upDown:
                if pitches.count > 2 {
                    order = pitches + Array(pitches.dropFirst().dropLast().reversed())
                } else {
                    order = pitches
                }
            case .random:
                order = shuffled(pitches, seed: clusterIndex)
            }
            guard !order.isEmpty else { continue }

            var stepIndex = 0
            var time = start
            while time < end - 0.001 {
                let swingOffset = indexIsOdd(stepIndex) ? settings.swing * step : 0
                let noteStart = time + swingOffset
                let noteDuration = min(step * settings.gate, end - noteStart)
                if noteDuration >= 0.02 {
                    result.append(SynthNote(
                        pitch: order[stepIndex % order.count],
                        startTime: max(0, noteStart),
                        duration: noteDuration,
                        velocity: velocity
                    ))
                }
                stepIndex += 1
                time += step
            }
        }

        return result.sorted { $0.startTime < $1.startTime }
    }

    private static func indexIsOdd(_ index: Int) -> Bool {
        index % 2 == 1
    }

    /// A repeatable shuffle so playback, freezing and the bounce all match.
    private static func shuffled(_ pitches: [Int], seed: Int) -> [Int] {
        var values = pitches
        var state = UInt64(truncatingIfNeeded: seed) &* 6_364_136_223_846_793_005 &+ 1
        guard values.count > 1 else { return values }

        for index in stride(from: values.count - 1, through: 1, by: -1) {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let target = Int(state % UInt64(index + 1))
            values.swapAt(index, target)
        }
        return values
    }
}
