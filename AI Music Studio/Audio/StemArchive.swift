//
//  StemArchive.swift
//  AI Music Studio
//

import AVFoundation
import Foundation

struct StemArchiveAudio: Sendable {
    let trackName: String
    let fileURL: URL
    let duration: TimeInterval
}

struct StemArchiveVerificationFailure: Identifiable, Sendable {
    let entryIndex: Int
    let entryName: String
    let reason: String

    var id: Int { entryIndex }
}

struct StemArchiveVerificationResult: Sendable {
    let entryCount: Int
    let verifiedEntryCount: Int
    let failures: [StemArchiveVerificationFailure]

    var isIntact: Bool { entryCount > 0 && failures.isEmpty && verifiedEntryCount == entryCount }
}

struct StemArchiveManifest: Codable {
    struct Stem: Codable, Identifiable {
        let trackName: String
        let fileName: String
        let duration: TimeInterval
        let format: String

        private enum CodingKeys: String, CodingKey {
            case trackName, fileName, duration, format
        }

        init(trackName: String, fileName: String, duration: TimeInterval, format: String) {
            self.trackName = trackName
            self.fileName = fileName
            self.duration = duration
            self.format = format
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            fileName = try values.decode(String.self, forKey: .fileName)
            trackName = try values.decodeIfPresent(String.self, forKey: .trackName) ?? ""
            duration = try values.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
            format = try values.decodeIfPresent(String.self, forKey: .format)
                ?? URL(fileURLWithPath: fileName).pathExtension.uppercased()
        }

        var id: String { fileName }
    }

    struct BounceSettings: Codable {
        let range: BounceRange
        let loopStart: TimeInterval?
        let loopEnd: TimeInterval?
        let sampleRate: BounceSampleRate
        let bitDepth: BounceBitDepth?
        let normalize: Bool
    }

    let sessionName: String
    let sessionTempoBPM: Int
    let stems: [Stem]
    let bounceSettings: BounceSettings?
}

private struct StemZipEntry {
    let name: String
    let fileURL: URL?
    let data: Data?
    let nameData: Data
    let size: UInt32
    let checksum: UInt32
    let dosTime: UInt16
    let dosDate: UInt16
}

private struct StemArchiveVerificationEntry {
    let name: String
    let nameData: Data
    let flags: UInt16
    let compression: UInt16
    let checksum: UInt32
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let localHeaderOffset: UInt32
}

private enum StemArchiveEntryVerificationError: LocalizedError {
    case invalidHeader
    case encrypted
    case unsupportedCompression(UInt16)
    case sizeMismatch
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .invalidHeader:
            return "The ZIP entry header is invalid."
        case .encrypted:
            return "Encrypted entries cannot be verified."
        case .unsupportedCompression(let method):
            return "ZIP compression method \(method) is not supported for verification."
        case .sizeMismatch:
            return "The declared entry size does not match its data."
        case .checksumMismatch:
            return "The entry checksum does not match."
        }
    }
}

enum StemArchiveError: LocalizedError {
    case unsupportedArchiveSize
    case invalidArchive
    case manifestNotFound
    case stemNotFound
    case unsupportedCompression
    case unsupportedStemCompression
    case unsupportedAudioFormat(String)
    case unsupportedStemCompressionForStem(String)
    case unreadableStem(String)
    case couldNotStoreStem(String)
    case duplicateStemEntry(String)
    case manifestContainsNoStems
    case noStemsSelected

    var errorDescription: String? {
        switch self {
        case .unsupportedArchiveSize:
            return "The stems are too large to fit in a standard ZIP archive."
        case .invalidArchive:
            return "This stem archive could not be read."
        case .manifestNotFound:
            return "This archive does not contain a stem manifest."
        case .stemNotFound:
            return "This stem could not be found in the archive."
        case .unsupportedCompression:
            return "The stem manifest uses an unsupported compression format."
        case .unsupportedStemCompression:
            return "This stem uses an unsupported compression format."
        case .unsupportedAudioFormat(let name):
            return "\(name) uses an unsupported audio format. Choose WAV, M4A, MP3, AIFF, or CAF stems. No stems were imported."
        case .unsupportedStemCompressionForStem(let name):
            return "\(name) uses ZIP compression that this app cannot read. No stems were imported."
        case .unreadableStem(let name):
            return "\(name) contains unreadable audio. No stems were imported."
        case .couldNotStoreStem(let name):
            return "\(name) could not be copied into the session. No stems were imported."
        case .duplicateStemEntry(let name):
            return "The manifest refers to \(name) more than once. No stems were imported."
        case .manifestContainsNoStems:
            return "This archive manifest does not list any stems."
        case .noStemsSelected:
            return "Select at least one stem to import."
        }
    }
}

/// Writes an uncompressed ZIP archive containing the rendered stems and a JSON manifest.
enum StemArchive {
    private static let utf8Flag: UInt16 = 0x0800
    private static let supportedAudioExtensions: Set<String> = ["wav", "m4a", "mp3", "aif", "aiff", "caf"]
    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
        }
        return crc
    }

    static func readManifest(from url: URL) throws -> StemArchiveManifest {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }

        let fileSize = try file.seekToEnd()
        guard fileSize >= 22 else { throw StemArchiveError.invalidArchive }
        let tailSize = Int(min(fileSize, 65_557))
        try file.seek(toOffset: fileSize - UInt64(tailSize))
        let tail = try readExactly(tailSize, from: file)

        let endRecordOffset = stride(from: tail.count - 22, through: 0, by: -1).first { offset in
            guard readUInt32(tail, at: offset) == 0x06054B50,
                  let commentLength = readUInt16(tail, at: offset + 20) else { return false }
            return offset + 22 + Int(commentLength) <= tail.count
        }
        guard let endRecordOffset,
              readUInt16(tail, at: endRecordOffset + 4) == 0,
              readUInt16(tail, at: endRecordOffset + 6) == 0,
              let diskEntryCount = readUInt16(tail, at: endRecordOffset + 8),
              let entryCount = readUInt16(tail, at: endRecordOffset + 10),
              diskEntryCount == entryCount,
              let centralDirectorySize = readUInt32(tail, at: endRecordOffset + 12),
              let centralDirectoryOffset = readUInt32(tail, at: endRecordOffset + 16) else {
            throw StemArchiveError.invalidArchive
        }

        let centralEnd = UInt64(centralDirectoryOffset) + UInt64(centralDirectorySize)
        guard centralEnd <= fileSize else { throw StemArchiveError.invalidArchive }
        try file.seek(toOffset: UInt64(centralDirectoryOffset))

        var cursor: UInt64 = 0
        var manifestLocation: (offset: UInt32, size: UInt32, compression: UInt16)?
        for _ in 0..<entryCount {
            guard cursor + 46 <= UInt64(centralDirectorySize) else { throw StemArchiveError.invalidArchive }
            let header = try readExactly(46, from: file)
            guard readUInt32(header, at: 0) == 0x02014B50,
                  let compression = readUInt16(header, at: 10),
                  let compressedSize = readUInt32(header, at: 20),
                  let nameLength = readUInt16(header, at: 28),
                  let extraLength = readUInt16(header, at: 30),
                  let commentLength = readUInt16(header, at: 32),
                  let localHeaderOffset = readUInt32(header, at: 42) else {
                throw StemArchiveError.invalidArchive
            }

            let recordLength = 46 + Int(nameLength) + Int(extraLength) + Int(commentLength)
            guard cursor + UInt64(recordLength) <= UInt64(centralDirectorySize) else {
                throw StemArchiveError.invalidArchive
            }
            let name = try readExactly(Int(nameLength), from: file)
            if String(data: name, encoding: .utf8) == "manifest.json" {
                manifestLocation = (localHeaderOffset, compressedSize, compression)
            }
            let skippedLength = Int(extraLength) + Int(commentLength)
            if skippedLength > 0 {
                _ = try readExactly(skippedLength, from: file)
            }
            cursor += UInt64(recordLength)
        }

        guard let manifestLocation else { throw StemArchiveError.manifestNotFound }
        guard manifestLocation.compression == 0 else { throw StemArchiveError.unsupportedCompression }

        try file.seek(toOffset: UInt64(manifestLocation.offset))
        let localHeader = try readExactly(30, from: file)
        guard readUInt32(localHeader, at: 0) == 0x04034B50,
              let localNameLength = readUInt16(localHeader, at: 26),
              let localExtraLength = readUInt16(localHeader, at: 28) else {
            throw StemArchiveError.invalidArchive
        }

        let manifestDataOffset = UInt64(manifestLocation.offset) + 30
            + UInt64(localNameLength) + UInt64(localExtraLength)
        guard manifestDataOffset + UInt64(manifestLocation.size) <= fileSize else {
            throw StemArchiveError.invalidArchive
        }
        try file.seek(toOffset: manifestDataOffset)
        let manifestData = try readExactly(Int(manifestLocation.size), from: file)
        return try JSONDecoder().decode(StemArchiveManifest.self, from: manifestData)
    }

    /// Streams every stored ZIP entry to validate its declared length and CRC-32.
    /// Compressed or encrypted entries are reported as unverifiable rather than
    /// being treated as intact.
    static func verifyArchive(
        at url: URL,
        progress: @Sendable (_ fraction: Double, _ entryName: String) -> Void
    ) throws -> StemArchiveVerificationResult {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }

        let fileSize = try file.seekToEnd()
        guard fileSize >= 22 else { throw StemArchiveError.invalidArchive }
        let tailSize = Int(min(fileSize, 65_557))
        try file.seek(toOffset: fileSize - UInt64(tailSize))
        let tail = try readExactly(tailSize, from: file)

        let endRecordOffset = stride(from: tail.count - 22, through: 0, by: -1).first { offset in
            guard readUInt32(tail, at: offset) == 0x06054B50,
                  let commentLength = readUInt16(tail, at: offset + 20) else { return false }
            return offset + 22 + Int(commentLength) <= tail.count
        }
        guard let endRecordOffset,
              readUInt16(tail, at: endRecordOffset + 4) == 0,
              readUInt16(tail, at: endRecordOffset + 6) == 0,
              let diskEntryCount = readUInt16(tail, at: endRecordOffset + 8),
              let entryCount = readUInt16(tail, at: endRecordOffset + 10),
              diskEntryCount == entryCount,
              entryCount > 0,
              let centralDirectorySize = readUInt32(tail, at: endRecordOffset + 12),
              let centralDirectoryOffset = readUInt32(tail, at: endRecordOffset + 16) else {
            throw StemArchiveError.invalidArchive
        }

        let absoluteEndRecordOffset = fileSize - UInt64(tailSize) + UInt64(endRecordOffset)
        let centralEnd = UInt64(centralDirectoryOffset) + UInt64(centralDirectorySize)
        guard centralEnd <= absoluteEndRecordOffset else { throw StemArchiveError.invalidArchive }
        try file.seek(toOffset: UInt64(centralDirectoryOffset))

        var entries: [StemArchiveVerificationEntry] = []
        var cursor: UInt64 = 0
        var totalUncompressedBytes: UInt64 = 0
        for index in 0..<entryCount {
            guard cursor + 46 <= UInt64(centralDirectorySize) else { throw StemArchiveError.invalidArchive }
            let header = try readExactly(46, from: file)
            guard readUInt32(header, at: 0) == 0x02014B50,
                  let flags = readUInt16(header, at: 8),
                  let compression = readUInt16(header, at: 10),
                  let checksum = readUInt32(header, at: 16),
                  let compressedSize = readUInt32(header, at: 20),
                  let uncompressedSize = readUInt32(header, at: 24),
                  let nameLength = readUInt16(header, at: 28),
                  let extraLength = readUInt16(header, at: 30),
                  let commentLength = readUInt16(header, at: 32),
                  let localHeaderOffset = readUInt32(header, at: 42) else {
                throw StemArchiveError.invalidArchive
            }

            let recordLength = 46 + Int(nameLength) + Int(extraLength) + Int(commentLength)
            guard cursor + UInt64(recordLength) <= UInt64(centralDirectorySize) else {
                throw StemArchiveError.invalidArchive
            }
            let nameData = try readExactly(Int(nameLength), from: file)
            let name = String(data: nameData, encoding: .utf8) ?? "Entry \(index + 1)"
            entries.append(StemArchiveVerificationEntry(
                name: name,
                nameData: nameData,
                flags: flags,
                compression: compression,
                checksum: checksum,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            ))
            let (newTotal, overflow) = totalUncompressedBytes.addingReportingOverflow(UInt64(uncompressedSize))
            guard !overflow else { throw StemArchiveError.invalidArchive }
            totalUncompressedBytes = newTotal

            let skippedLength = Int(extraLength) + Int(commentLength)
            if skippedLength > 0 {
                _ = try readExactly(skippedLength, from: file)
            }
            cursor += UInt64(recordLength)
        }
        guard cursor == UInt64(centralDirectorySize) else { throw StemArchiveError.invalidArchive }

        var completedBytes: UInt64 = 0
        var lastReportedProgress = -1.0
        var lastReportedEntry = ""
        var verifiedEntryCount = 0
        var failures: [StemArchiveVerificationFailure] = []

        for (index, entry) in entries.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            let fractionAtEntryStart = totalUncompressedBytes > 0
                ? Double(completedBytes) / Double(totalUncompressedBytes)
                : Double(index) / Double(entries.count)
            let currentFraction = max(lastReportedProgress, fractionAtEntryStart)
            progress(min(1, currentFraction), entry.name)
            lastReportedProgress = currentFraction
            lastReportedEntry = entry.name

            do {
                try verifyEntry(
                    entry,
                    in: file,
                    archiveSize: fileSize,
                    centralDirectoryOffset: UInt64(centralDirectoryOffset),
                    completedBytes: completedBytes,
                    totalBytes: totalUncompressedBytes,
                    entryIndex: index,
                    entryCount: entries.count,
                    lastReportedProgress: &lastReportedProgress,
                    lastReportedEntry: &lastReportedEntry,
                    progress: progress
                )
                verifiedEntryCount += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription
                    ?? "The entry is truncated or unreadable."
                failures.append(StemArchiveVerificationFailure(
                    entryIndex: index,
                    entryName: entry.name,
                    reason: reason
                ))
            }

            completedBytes += UInt64(entry.uncompressedSize)
            let fraction = totalUncompressedBytes > 0
                ? Double(completedBytes) / Double(totalUncompressedBytes)
                : Double(index + 1) / Double(entries.count)
            progress(min(1, fraction), entry.name)
        }

        return StemArchiveVerificationResult(
            entryCount: entries.count,
            verifiedEntryCount: verifiedEntryCount,
            failures: failures
        )
    }

    private static func verifyEntry(
        _ entry: StemArchiveVerificationEntry,
        in file: FileHandle,
        archiveSize: UInt64,
        centralDirectoryOffset: UInt64,
        completedBytes: UInt64,
        totalBytes: UInt64,
        entryIndex: Int,
        entryCount: Int,
        lastReportedProgress: inout Double,
        lastReportedEntry: inout String,
        progress: @Sendable (Double, String) -> Void
    ) throws {
        guard entry.flags & 0x0001 == 0 else { throw StemArchiveEntryVerificationError.encrypted }
        guard entry.compression == 0 else {
            throw StemArchiveEntryVerificationError.unsupportedCompression(entry.compression)
        }
        guard entry.compressedSize == entry.uncompressedSize else {
            throw StemArchiveEntryVerificationError.sizeMismatch
        }
        guard UInt64(entry.localHeaderOffset) + 30 <= archiveSize else {
            throw StemArchiveEntryVerificationError.invalidHeader
        }

        try file.seek(toOffset: UInt64(entry.localHeaderOffset))
        let localHeader = try readExactly(30, from: file)
        guard readUInt32(localHeader, at: 0) == 0x04034B50,
              let localFlags = readUInt16(localHeader, at: 6),
              let localCompression = readUInt16(localHeader, at: 8),
              let localChecksum = readUInt32(localHeader, at: 14),
              let localCompressedSize = readUInt32(localHeader, at: 18),
              let localUncompressedSize = readUInt32(localHeader, at: 22),
              let localNameLength = readUInt16(localHeader, at: 26),
              let localExtraLength = readUInt16(localHeader, at: 28),
              localFlags == entry.flags,
              localCompression == entry.compression else {
            throw StemArchiveEntryVerificationError.invalidHeader
        }

        let localName = try readExactly(Int(localNameLength), from: file)
        guard localName == entry.nameData else { throw StemArchiveEntryVerificationError.invalidHeader }
        let dataOffset = UInt64(entry.localHeaderOffset) + 30
            + UInt64(localNameLength) + UInt64(localExtraLength)
        let (dataEnd, overflow) = dataOffset.addingReportingOverflow(UInt64(entry.compressedSize))
        guard !overflow, dataEnd <= archiveSize, dataEnd <= centralDirectoryOffset else {
            throw StemArchiveEntryVerificationError.invalidHeader
        }

        let hasDataDescriptor = entry.flags & 0x0008 != 0
        if !hasDataDescriptor,
           (localChecksum != entry.checksum
            || localCompressedSize != entry.compressedSize
            || localUncompressedSize != entry.uncompressedSize) {
            throw StemArchiveEntryVerificationError.sizeMismatch
        }

        try file.seek(toOffset: dataOffset)
        var remaining = Int(entry.compressedSize)
        var bytesRead = 0
        var checksum: UInt32 = 0xFFFFFFFF
        while remaining > 0 {
            if Task.isCancelled { throw CancellationError() }
            let chunk = try readExactly(min(1_048_576, remaining), from: file)
            for byte in chunk {
                checksum = (checksum >> 8) ^ crcTable[Int((checksum ^ UInt32(byte)) & 0xFF)]
            }
            remaining -= chunk.count
            bytesRead += chunk.count

            let fraction = totalBytes > 0
                ? Double(completedBytes + UInt64(bytesRead)) / Double(totalBytes)
                : Double(entryIndex) / Double(entryCount)
            if entry.name != lastReportedEntry || fraction - lastReportedProgress >= 0.01 {
                progress(min(1, fraction), entry.name)
                lastReportedProgress = fraction
                lastReportedEntry = entry.name
            }
        }

        guard UInt64(bytesRead) == UInt64(entry.uncompressedSize) else {
            throw StemArchiveEntryVerificationError.sizeMismatch
        }
        guard checksum ^ 0xFFFFFFFF == entry.checksum else {
            throw StemArchiveEntryVerificationError.checksumMismatch
        }
    }

    static func supportsAudioFile(named fileName: String) -> Bool {
        supportedAudioExtensions.contains(URL(fileURLWithPath: fileName).pathExtension.lowercased())
    }

    /// Reads the complete decoded stream before import so a corrupt or unsupported
    /// selection fails before any of its tracks are committed to the session.
    static func validateAudioFile(at url: URL, named stemName: String) throws {
        guard supportsAudioFile(named: url.lastPathComponent) else {
            throw StemArchiveError.unsupportedAudioFormat(stemName)
        }
        guard let audioFile = try? AVAudioFile(forReading: url),
              audioFile.length > 0,
              audioFile.processingFormat.sampleRate > 0,
              audioFile.processingFormat.channelCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: 16_384) else {
            throw StemArchiveError.unreadableStem(stemName)
        }

        do {
            while audioFile.framePosition < audioFile.length {
                try audioFile.read(into: buffer)
                guard buffer.frameLength > 0 else {
                    throw StemArchiveError.unreadableStem(stemName)
                }
            }
        } catch {
            throw StemArchiveError.unreadableStem(stemName)
        }
    }

    /// Extracts a single uncompressed stem from an archive to a temporary file.
    static func extractStem(from archiveURL: URL, fileName: String, named temporaryFileName: String? = nil) throws -> URL {
        let file = try FileHandle(forReadingFrom: archiveURL)
        defer { try? file.close() }

        let fileSize = try file.seekToEnd()
        guard fileSize >= 22 else { throw StemArchiveError.invalidArchive }
        let tailSize = Int(min(fileSize, 65_557))
        try file.seek(toOffset: fileSize - UInt64(tailSize))
        let tail = try readExactly(tailSize, from: file)

        let endRecordOffset = stride(from: tail.count - 22, through: 0, by: -1).first { offset in
            guard readUInt32(tail, at: offset) == 0x06054B50,
                  let commentLength = readUInt16(tail, at: offset + 20) else { return false }
            return offset + 22 + Int(commentLength) <= tail.count
        }
        guard let endRecordOffset,
              readUInt16(tail, at: endRecordOffset + 4) == 0,
              readUInt16(tail, at: endRecordOffset + 6) == 0,
              let diskEntryCount = readUInt16(tail, at: endRecordOffset + 8),
              let entryCount = readUInt16(tail, at: endRecordOffset + 10),
              diskEntryCount == entryCount,
              let centralDirectorySize = readUInt32(tail, at: endRecordOffset + 12),
              let centralDirectoryOffset = readUInt32(tail, at: endRecordOffset + 16) else {
            throw StemArchiveError.invalidArchive
        }

        let centralEnd = UInt64(centralDirectoryOffset) + UInt64(centralDirectorySize)
        guard centralEnd <= fileSize else { throw StemArchiveError.invalidArchive }
        try file.seek(toOffset: UInt64(centralDirectoryOffset))

        var cursor: UInt64 = 0
        var stemLocation: (offset: UInt32, compressedSize: UInt32, uncompressedSize: UInt32, checksum: UInt32, compression: UInt16)?
        for _ in 0..<entryCount {
            guard cursor + 46 <= UInt64(centralDirectorySize) else { throw StemArchiveError.invalidArchive }
            let header = try readExactly(46, from: file)
            guard readUInt32(header, at: 0) == 0x02014B50,
                  let compression = readUInt16(header, at: 10),
                  let checksum = readUInt32(header, at: 16),
                  let compressedSize = readUInt32(header, at: 20),
                  let uncompressedSize = readUInt32(header, at: 24),
                  let nameLength = readUInt16(header, at: 28),
                  let extraLength = readUInt16(header, at: 30),
                  let commentLength = readUInt16(header, at: 32),
                  let localHeaderOffset = readUInt32(header, at: 42) else {
                throw StemArchiveError.invalidArchive
            }

            let recordLength = 46 + Int(nameLength) + Int(extraLength) + Int(commentLength)
            guard cursor + UInt64(recordLength) <= UInt64(centralDirectorySize) else {
                throw StemArchiveError.invalidArchive
            }
            let nameData = try readExactly(Int(nameLength), from: file)
            if String(data: nameData, encoding: .utf8) == fileName {
                stemLocation = (localHeaderOffset, compressedSize, uncompressedSize, checksum, compression)
            }
            let skippedLength = Int(extraLength) + Int(commentLength)
            if skippedLength > 0 {
                _ = try readExactly(skippedLength, from: file)
            }
            cursor += UInt64(recordLength)
        }

        guard let stemLocation else { throw StemArchiveError.stemNotFound }
        guard stemLocation.compression == 0,
              stemLocation.compressedSize == stemLocation.uncompressedSize else {
            throw StemArchiveError.unsupportedStemCompression
        }

        try file.seek(toOffset: UInt64(stemLocation.offset))
        let localHeader = try readExactly(30, from: file)
        guard readUInt32(localHeader, at: 0) == 0x04034B50,
              readUInt16(localHeader, at: 8) == stemLocation.compression,
              let localNameLength = readUInt16(localHeader, at: 26),
              let localExtraLength = readUInt16(localHeader, at: 28) else {
            throw StemArchiveError.invalidArchive
        }
        let localName = try readExactly(Int(localNameLength), from: file)
        guard String(data: localName, encoding: .utf8) == fileName else {
            throw StemArchiveError.invalidArchive
        }

        let dataOffset = UInt64(stemLocation.offset) + 30
            + UInt64(localNameLength) + UInt64(localExtraLength)
        let dataEnd = dataOffset + UInt64(stemLocation.compressedSize)
        guard dataEnd <= fileSize, dataEnd <= UInt64(centralDirectoryOffset) else {
            throw StemArchiveError.invalidArchive
        }

        let extensionName = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let safeExtension = supportedAudioExtensions.contains(extensionName) ? extensionName : "audio"
        let requestedName = temporaryFileName
            ?? URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let safeBaseName = requestedName
            .components(separatedBy: CharacterSet(charactersIn: "/\\:"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = safeBaseName.isEmpty ? "stem" : safeBaseName
        let extractedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(baseName)-\(UUID().uuidString).\(safeExtension)")
        guard FileManager.default.createFile(atPath: extractedURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var completed = false
        defer {
            if !completed { try? FileManager.default.removeItem(at: extractedURL) }
        }

        let output = try FileHandle(forWritingTo: extractedURL)
        defer { try? output.close() }
        try file.seek(toOffset: dataOffset)
        var remaining = Int(stemLocation.compressedSize)
        var checksum: UInt32 = 0xFFFFFFFF
        while remaining > 0 {
            let chunk = try readExactly(min(1_048_576, remaining), from: file)
            try output.write(contentsOf: chunk)
            for byte in chunk {
                checksum = (checksum >> 8) ^ crcTable[Int((checksum ^ UInt32(byte)) & 0xFF)]
            }
            remaining -= chunk.count
        }
        guard checksum ^ 0xFFFFFFFF == stemLocation.checksum else {
            throw StemArchiveError.invalidArchive
        }
        completed = true
        return extractedURL
    }

    private static func readExactly(_ count: Int, from file: FileHandle) throws -> Data {
        guard count >= 0,
              let data = try file.read(upToCount: count),
              data.count == count else {
            throw StemArchiveError.invalidArchive
        }
        return data
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    static func create(
        sessionName: String,
        tempoBPM: Int,
        stems: [StemArchiveAudio],
        bounceSettings: StemArchiveManifest.BounceSettings? = nil,
        to url: URL
    ) throws {
        let manifest = StemArchiveManifest(
            sessionName: sessionName,
            sessionTempoBPM: tempoBPM,
            stems: stems.map { stem in
                StemArchiveManifest.Stem(
                    trackName: stem.trackName,
                    fileName: stem.fileURL.lastPathComponent,
                    duration: stem.duration,
                    format: stem.fileURL.pathExtension.uppercased()
                )
            },
            bounceSettings: bounceSettings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        let timestamp = dosTimestamp(Date())

        var entries = try stems.map { stem in
            try makeEntry(name: stem.fileURL.lastPathComponent, fileURL: stem.fileURL, data: nil, timestamp: timestamp)
        }
        entries.append(try makeEntry(name: "manifest.json", fileURL: nil, data: manifestData, timestamp: timestamp))
        guard entries.count <= Int(UInt16.max) else { throw StemArchiveError.unsupportedArchiveSize }

        do {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let output = try FileHandle(forWritingTo: url)
            defer { try? output.close() }

            var offset: UInt64 = 0
            var centralDirectory = Data()
            for entry in entries {
                guard offset <= UInt64(UInt32.max) else { throw StemArchiveError.unsupportedArchiveSize }
                let entryOffset = UInt32(offset)
                let localHeader = localFileHeader(for: entry)
                try output.write(contentsOf: localHeader)
                try output.write(contentsOf: entry.nameData)
                offset += UInt64(localHeader.count + entry.nameData.count)

                if let data = entry.data {
                    try output.write(contentsOf: data)
                    offset += UInt64(data.count)
                } else if let fileURL = entry.fileURL {
                    try copyFile(at: fileURL, to: output, byteCount: Int(entry.size))
                    offset += UInt64(entry.size)
                }

                centralDirectory.append(centralDirectoryHeader(for: entry, localOffset: entryOffset))
                centralDirectory.append(entry.nameData)
            }

            guard offset <= UInt64(UInt32.max), centralDirectory.count <= Int(UInt32.max) else {
                throw StemArchiveError.unsupportedArchiveSize
            }
            try output.write(contentsOf: centralDirectory)
            try output.write(contentsOf: endOfCentralDirectory(
                entryCount: UInt16(entries.count),
                centralSize: UInt32(centralDirectory.count),
                centralOffset: UInt32(offset)
            ))
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private static func makeEntry(
        name: String,
        fileURL: URL?,
        data: Data?,
        timestamp: (time: UInt16, date: UInt16)
    ) throws -> StemZipEntry {
        let nameData = Data(name.utf8)
        let size: Int64
        let checksum: UInt32
        if let data {
            size = Int64(data.count)
            checksum = crc32(data)
        } else if let fileURL {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            checksum = try crc32(fileURL: fileURL)
        } else {
            size = 0
            checksum = 0
        }
        guard size >= 0,
              size <= Int64(UInt32.max),
              nameData.count <= Int(UInt16.max) else {
            throw StemArchiveError.unsupportedArchiveSize
        }
        return StemZipEntry(
            name: name,
            fileURL: fileURL,
            data: data,
            nameData: nameData,
            size: UInt32(size),
            checksum: checksum,
            dosTime: timestamp.time,
            dosDate: timestamp.date
        )
    }

    private static func crc32(fileURL: URL) throws -> UInt32 {
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        var crc: UInt32 = 0xFFFFFFFF
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            for byte in chunk {
                crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xFF)]
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xFF)]
        }
        return crc ^ 0xFFFFFFFF
    }

    private static func copyFile(at url: URL, to output: FileHandle, byteCount: Int) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var remaining = byteCount
        while remaining > 0 {
            guard let chunk = try input.read(upToCount: min(1_048_576, remaining)), !chunk.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try output.write(contentsOf: chunk)
            remaining -= chunk.count
        }
    }

    private static func localFileHeader(for entry: StemZipEntry) -> Data {
        var data = Data()
        append(UInt32(0x04034B50), to: &data)
        append(UInt16(20), to: &data)
        append(utf8Flag, to: &data)
        append(UInt16(0), to: &data)
        append(entry.dosTime, to: &data)
        append(entry.dosDate, to: &data)
        append(entry.checksum, to: &data)
        append(entry.size, to: &data)
        append(entry.size, to: &data)
        append(UInt16(entry.nameData.count), to: &data)
        append(UInt16(0), to: &data)
        return data
    }

    private static func centralDirectoryHeader(for entry: StemZipEntry, localOffset: UInt32) -> Data {
        var data = Data()
        append(UInt32(0x02014B50), to: &data)
        append(UInt16(20), to: &data)
        append(UInt16(20), to: &data)
        append(utf8Flag, to: &data)
        append(UInt16(0), to: &data)
        append(entry.dosTime, to: &data)
        append(entry.dosDate, to: &data)
        append(entry.checksum, to: &data)
        append(entry.size, to: &data)
        append(entry.size, to: &data)
        append(UInt16(entry.nameData.count), to: &data)
        append(UInt16(0), to: &data)
        append(UInt16(0), to: &data)
        append(UInt16(0), to: &data)
        append(UInt16(0), to: &data)
        append(UInt32(0), to: &data)
        append(localOffset, to: &data)
        return data
    }

    private static func endOfCentralDirectory(entryCount: UInt16, centralSize: UInt32, centralOffset: UInt32) -> Data {
        var data = Data()
        append(UInt32(0x06054B50), to: &data)
        append(UInt16(0), to: &data)
        append(UInt16(0), to: &data)
        append(entryCount, to: &data)
        append(entryCount, to: &data)
        append(centralSize, to: &data)
        append(centralOffset, to: &data)
        append(UInt16(0), to: &data)
        return data
    }

    private static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, min(2107, components.year ?? 1980))
        let month = max(1, min(12, components.month ?? 1))
        let day = max(1, min(31, components.day ?? 1))
        let hour = max(0, min(23, components.hour ?? 0))
        let minute = max(0, min(59, components.minute ?? 0))
        let second = max(0, min(59, components.second ?? 0))
        let time = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (time, dosDate)
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }
}
