//
//  AuxBus.swift
//  AI Music Studio
//

import Foundation

/// One aux send bus: a shared effect with a return level.
struct AuxBusSettings: Codable, Equatable, Identifiable {
    enum Effect: String, Codable, CaseIterable {
        case reverb
        case delay

        var title: String { rawValue.capitalized }
    }

    var id: String
    var name: String
    var effect: Effect
    var isBypassed: Bool
    /// Return level of the bus, from 0 to 1.
    var level: Float
    var reverbMix: Float
    var reverbDecay: Double
    var delayBeats: Double
    var delayFeedback: Float
    var delayMix: Float

    static var busA: AuxBusSettings {
        AuxBusSettings(
            id: "A",
            name: "Aux A",
            effect: .reverb,
            isBypassed: false,
            level: 0.8,
            reverbMix: 0.4,
            reverbDecay: 1.8,
            delayBeats: 0.5,
            delayFeedback: 0.3,
            delayMix: 0.3
        )
    }

    static var busB: AuxBusSettings {
        AuxBusSettings(
            id: "B",
            name: "Aux B",
            effect: .delay,
            isBypassed: false,
            level: 0.7,
            reverbMix: 0.3,
            reverbDecay: 1.4,
            delayBeats: 0.75,
            delayFeedback: 0.35,
            delayMix: 0.35
        )
    }
}
