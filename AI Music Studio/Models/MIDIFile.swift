//
//  MIDIFile.swift
//  AI Music Studio
//

import Foundation

/// Reads and writes Standard MIDI Files for a track's sequenced notes.
enum MIDIFile {
    struct Imported {
        var notes: [SynthNote]
        var name: String?
        var tempoBPM: Int?
    }

    enum MIDIError: LocalizedError {
        case invalid

        var errorDescription: String? {
            "That file is not a readable MIDI file."
        }
    }

    private static let ticksPerQuarter = 480

    /// Where exported MIDI files are written so they can be shared.
    static var exportsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("MIDI Exports", isDirectory: true)
    }

    /// A share-friendly file name built from a track name.
    static func suggestedFileName(for trackName: String) -> String {
        let trimmed = trackName.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = trimmed
            .components(separatedBy: invalid)
            .joined(separator: "-")
        let base = cleaned.isEmpty ? "Track" : cleaned
        return "\(base).mid"
    }

    // MARK: - Writing

    /// A format 0 MIDI file carrying the tempo, the track name and every note.
    static func export(track: Track, tempoBPM: Int) -> Data {
        let tempo = min(200, max(60, tempoBPM))
        let beat = 60.0 / Double(tempo)

        func tick(_ seconds: TimeInterval) -> Int {
            max(0, Int((max(0, seconds) / beat * Double(ticksPerQuarter)).rounded()))
        }

        var events: [(tick: Int, order: Int, bytes: [UInt8])] = []

        let microseconds = UInt32(60_000_000 / tempo)
        events.append((
            0, 0,
            [
                0xFF, 0x51, 0x03,
                UInt8((microseconds >> 16) & 0xFF),
                UInt8((microseconds >> 8) & 0xFF),
                UInt8(microseconds & 0xFF)
            ]
        ))

        let nameBytes = Array(track.name.utf8.prefix(127))
        if !nameBytes.isEmpty {
            events.append((0, 1, [0xFF, 0x03, UInt8(nameBytes.count)] + nameBytes))
        }

        for note in track.notes {
            let pitch = UInt8(min(127, max(0, note.pitch)))
            let velocity = UInt8(min(127, max(1, Int((note.velocity * 127).rounded()))))
            let startTick = tick(note.startTime)
            let endTick = max(startTick + 1, tick(note.startTime + note.duration))
            events.append((startTick, 2, [0x90, pitch, velocity]))
            events.append((endTick, 0, [0x80, pitch, 0]))
        }

        var trackData: [UInt8] = []
        var lastTick = 0
        for event in events.sorted(by: {
            $0.tick == $1.tick ? $0.order < $1.order : $0.tick < $1.tick
        }) {
            trackData += variableLength(max(0, event.tick - lastTick))
            trackData += event.bytes
            lastTick = event.tick
        }
        trackData += [0x00, 0xFF, 0x2F, 0x00]

        var data = Array("MThd".utf8)
        data += uint32(6)
        data += uint16(0)
        data += uint16(1)
        data += uint16(ticksPerQuarter)
        data += Array("MTrk".utf8)
        data += uint32(trackData.count)
        data += trackData
        return Data(data)
    }

    // MARK: - Reading

    static func importFile(at url: URL) throws -> Imported {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw MIDIError.invalid }
        return try parse(data: data, fallbackName: url.deletingPathExtension().lastPathComponent)
    }

    static func parse(data: Data, fallbackName: String? = nil) throws -> Imported {
        var reader = Reader(bytes: [UInt8](data))

        guard try reader.matches("MThd") else { throw MIDIError.invalid }
        _ = try reader.u32()
        _ = try reader.u16() // format
        let trackCount = try reader.u16()
        let division = try reader.u16()
        guard division > 0, division & 0x8000 == 0 else { throw MIDIError.invalid }

        var tempoMicroseconds = 500_000
        var tempoFound = false
        var name: String?
        var rawNotes: [(pitch: Int, startTick: Int, endTick: Int, velocity: Int)] = []

        for _ in 0..<max(0, trackCount) {
            guard try reader.matches("MTrk") else { throw MIDIError.invalid }
            let length = try reader.u32()
            let endIndex = min(reader.bytes.count, reader.index + length)

            var absoluteTick = 0
            var runningStatus: UInt8 = 0
            var open: [Int: [(start: Int, velocity: Int)]] = [:]

            while reader.index < endIndex {
                absoluteTick += try reader.variableLength()
                guard let status = reader.peek() else { break }

                if status == 0xFF {
                    reader.index += 1
                    let type = try reader.u8()
                    let metaLength = try reader.variableLength()
                    let payload = reader.take(min(metaLength, max(0, endIndex - reader.index))) ?? []

                    if type == 0x51, payload.count >= 3 {
                        let value = (Int(payload[0]) << 16) | (Int(payload[1]) << 8) | Int(payload[2])
                        if value > 0, !tempoFound {
                            tempoMicroseconds = value
                            tempoFound = true
                        }
                    } else if type == 0x03, name == nil {
                        let text = String(bytes: payload, encoding: .utf8) ?? ""
                        if !text.isEmpty { name = text }
                    } else if type == 0x2F {
                        break
                    }
                    continue
                }

                var eventStatus = status
                if status < 0x80 {
                    eventStatus = runningStatus
                } else if status < 0xF0 {
                    runningStatus = status
                    reader.index += 1
                } else if status == 0xF0 || status == 0xF7 {
                    reader.index += 1
                    let length = try reader.variableLength()
                    reader.index = min(endIndex, reader.index + length)
                    continue
                } else {
                    reader.index += 1
                    continue
                }

                let kind = eventStatus & 0xF0
                switch kind {
                case 0x80, 0x90:
                    let pitch = Int(try reader.u8())
                    let velocity = Int(try reader.u8())
                    if kind == 0x90 && velocity > 0 {
                        open[pitch, default: []].append((absoluteTick, velocity))
                    } else {
                        if var stack = open[pitch], let started = stack.popLast() {
                            open[pitch] = stack
                            rawNotes.append((pitch, started.start, absoluteTick, started.velocity))
                        }
                    }
                case 0xA0, 0xB0, 0xE0:
                    _ = try reader.u8()
                    _ = try reader.u8()
                case 0xC0, 0xD0:
                    _ = try reader.u8()
                default:
                    _ = try reader.u8()
                }
            }

            for (pitch, stack) in open {
                for started in stack {
                    rawNotes.append((pitch, started.start, absoluteTick, started.velocity))
                }
            }

            reader.index = endIndex
        }

        let secondsPerTick = (Double(tempoMicroseconds) / 1_000_000.0) / Double(division)
        let notes = rawNotes.map { raw in
            let start = Double(raw.startTick) * secondsPerTick
            let end = Double(raw.endTick) * secondsPerTick
            return SynthNote(
                pitch: raw.pitch,
                startTime: max(0, start),
                duration: max(0.05, end - start),
                velocity: Float(min(1, max(0.05, Double(raw.velocity) / 127.0)))
            )
        }
        .sorted { $0.startTime < $1.startTime }

        guard !notes.isEmpty else { throw MIDIError.invalid }

        let bpm = max(60, min(200, Int((60_000_000.0 / Double(tempoMicroseconds)).rounded())))
        return Imported(notes: notes, name: name ?? fallbackName, tempoBPM: bpm)
    }

    // MARK: - Bytes

    private static func variableLength(_ value: Int) -> [UInt8] {
        var buffer = [UInt8(value & 0x7F)]
        var remaining = value >> 7
        while remaining > 0 {
            buffer.insert(UInt8((remaining & 0x7F) | 0x80), at: 0)
            remaining >>= 7
        }
        return buffer
    }

    private static func uint16(_ value: Int) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func uint32(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
    }

    private struct Reader {
        let bytes: [UInt8]
        var index = 0

        func peek() -> UInt8? {
            index < bytes.count ? bytes[index] : nil
        }

        mutating func matches(_ text: String) throws -> Bool {
            let expected = Array(text.utf8)
            guard index + expected.count <= bytes.count else { return false }
            guard Array(bytes[index..<(index + expected.count)]) == expected else { return false }
            index += expected.count
            return true
        }

        mutating func u8() throws -> UInt8 {
            guard index < bytes.count else { throw MIDIError.invalid }
            defer { index += 1 }
            return bytes[index]
        }

        mutating func u16() throws -> Int {
            let high = Int(try u8())
            let low = Int(try u8())
            return (high << 8) | low
        }

        mutating func u32() throws -> Int {
            let a = Int(try u8())
            let b = Int(try u8())
            let c = Int(try u8())
            let d = Int(try u8())
            return (a << 24) | (b << 16) | (c << 8) | d
        }

        mutating func variableLength() throws -> Int {
            var value = 0
            for _ in 0..<4 {
                let byte = try u8()
                value = (value << 7) | Int(byte & 0x7F)
                if byte & 0x80 == 0 { return value }
            }
            return value
        }

        mutating func take(_ count: Int) -> [UInt8]? {
            guard count >= 0, index + count <= bytes.count else { return nil }
            defer { index += count }
            return Array(bytes[index..<(index + count)])
        }
    }
}
