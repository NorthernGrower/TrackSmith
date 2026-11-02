//
//  SynthNote.swift
//  AI Music Studio
//

import Foundation

/// A synth note placed on a track's piano roll.
struct SynthNote: Identifiable, Codable, Equatable {
    var id: UUID
    var pitch: Int
    var startTime: TimeInterval
    var duration: TimeInterval

    init(id: UUID = UUID(), pitch: Int, startTime: TimeInterval, duration: TimeInterval) {
        self.id = id
        self.pitch = pitch
        self.startTime = startTime
        self.duration = duration
    }

    var endTime: TimeInterval {
        startTime + duration
    }

    static func frequency(for pitch: Int) -> Double {
        440 * pow(2, Double(pitch - 69) / 12)
    }

    static func name(for pitch: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return names[((pitch % 12) + 12) % 12] + "\(pitch / 12 - 1)"
    }

    static func isBlackKey(_ pitch: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(((pitch % 12) + 12) % 12)
    }

    /// Two octaves shown by the piano roll, C3 to B4.
    static let lowestPitch = 48
    static let highestPitch = 71
}

/// The synth voice the piano roll plays notes with.
enum SynthNoteVoice {
    static let waveform: SynthWaveform = .saw
    static let cutoff = 6_500.0
    static let attack = 0.02
    static let release = 0.28
}
