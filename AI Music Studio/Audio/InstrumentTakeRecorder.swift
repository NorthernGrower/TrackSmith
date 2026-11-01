//
//  InstrumentTakeRecorder.swift
//  AI Music Studio
//

import AVFoundation
import Foundation

struct RecordedInstrumentTake {
    let trackID: UUID
    let url: URL
    let duration: TimeInterval
}

enum InstrumentRecordingError: LocalizedError {
    case alreadyRecording
    case destinationUnavailable
    case fileCreationFailed
    case noAudioCaptured
    case engineUnavailable
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "An instrument take is already recording."
        case .destinationUnavailable:
            return "Choose an available session track as the recording destination."
        case .fileCreationFailed:
            return "The recording file could not be created. Check available storage and try again."
        case .noAudioCaptured:
            return "No audio was captured. Check the input and try recording again."
        case .engineUnavailable:
            return "Audio playback could not start, so the take was not recorded."
        case .microphoneUnavailable:
            return "Microphone input could not be started. Check microphone access in Settings."
        }
    }
}

/// Writes the instrument-only mixer tap to a session audio file.
final class InstrumentTakeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let sampleRate: Double
    private var file: AVAudioFile?
    private var framesWritten: Int64 = 0
    private var writeFailed = false

    init(url: URL, format: AVAudioFormat) throws {
        sampleRate = format.sampleRate
        file = try AVAudioFile(forWriting: url, settings: format.settings)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let file, !writeFailed else { return }

        do {
            try file.write(from: buffer)
            framesWritten += Int64(buffer.frameLength)
        } catch {
            writeFailed = true
        }
    }

    func finish() -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        file = nil
        guard !writeFailed, framesWritten > 0, sampleRate > 0 else { return nil }
        return Double(framesWritten) / sampleRate
    }
}
