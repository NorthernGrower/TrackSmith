//
//  StemArchive.swift
//  AI Music Studio
//

import Foundation

struct StemArchiveAudio: Sendable {
    let trackName: String
    let fileURL: URL
    let duration: TimeInterval
}

private struct StemArchiveManifest: Encodable {
    struct Stem: Encodable {
        let trackName: String
        let fileName: String
        let duration: TimeInterval
        let format: String
    }

    let sessionName: String
    let sessionTempoBPM: Int
    let stems: [Stem]
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

enum StemArchiveError: LocalizedError {
    case unsupportedArchiveSize

    var errorDescription: String? {
        switch self {
        case .unsupportedArchiveSize:
            return "The stems are too large to fit in a standard ZIP archive."
        }
    }
}

/// Writes an uncompressed ZIP archive containing the rendered stems and a JSON manifest.
enum StemArchive {
    private static let utf8Flag: UInt16 = 0x0800
    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
        }
        return crc
    }

    static func create(
        sessionName: String,
        tempoBPM: Int,
        stems: [StemArchiveAudio],
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
            }
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
