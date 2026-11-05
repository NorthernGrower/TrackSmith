//
//  StudioMode.swift
//  AI Music Studio
//

import Foundation

/// How much of the studio is on show: the simple daily controls or the full depth.
enum StudioMode: String, CaseIterable, Identifiable {
    case simple
    case pro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: return "Simple"
        case .pro: return "Pro"
        }
    }

    var subtitle: String {
        switch self {
        case .simple: return "Name, fader, mute, solo and record"
        case .pro: return "Automation, EQ depth, routing and mastering"
        }
    }

    var systemImage: String {
        switch self {
        case .simple: return "rectangle.grid.1x2"
        case .pro: return "slider.horizontal.3"
        }
    }
}

/// Remembers the chosen studio mode on this device.
enum StudioModeStorage {
    private static let key = "studio.mode"

    static func load() -> StudioMode {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let mode = StudioMode(rawValue: raw) else {
            return .simple
        }
        return mode
    }

    static func save(_ mode: StudioMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: key)
    }
}
