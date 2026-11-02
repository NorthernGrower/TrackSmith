//
//  TrackGroup.swift
//  AI Music Studio
//

import Foundation

/// A bus that links several tracks to one fader, mute and solo.
struct TrackGroup: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    /// Index into the studio's track colour palette.
    var colorIndex: Int
    var trackIDs: [UUID]
    /// Gain applied on top of each member's own level, from 0 to 1.
    var volume: Float
    var isMuted: Bool
    var isSoloed: Bool

    init(
        id: UUID = UUID(),
        name: String,
        colorIndex: Int = 0,
        trackIDs: [UUID] = [],
        volume: Float = 1,
        isMuted: Bool = false,
        isSoloed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.trackIDs = trackIDs
        self.volume = volume
        self.isMuted = isMuted
        self.isSoloed = isSoloed
    }
}
