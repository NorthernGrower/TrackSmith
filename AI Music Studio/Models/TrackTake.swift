//
//  TrackTake.swift
//  AI Music Studio
//

import Foundation

/// One recorded pass on a track, kept so earlier performances are never lost.
struct TrackTake: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var fileName: String
    var startTime: TimeInterval
    var duration: TimeInterval
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        startTime: TimeInterval,
        duration: TimeInterval,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.startTime = startTime
        self.duration = duration
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fileName
        case startTime
        case duration
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Take"
        fileName = try values.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        startTime = try values.decodeIfPresent(TimeInterval.self, forKey: .startTime) ?? 0
        duration = try values.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}
