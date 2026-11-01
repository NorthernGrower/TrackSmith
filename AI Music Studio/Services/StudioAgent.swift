//
//  StudioAgent.swift
//  AI Music Studio
//

import Foundation

/// Where the remote agent lives and how it is authenticated.
enum AgentSettings {
    static let apiKeyName = "AGENT_API_KEY"
    private static let baseURLKey = "studio.agent.baseURL"

    static var baseURL: URL? {
        get {
            UserDefaults.standard.string(forKey: baseURLKey).flatMap(URL.init(string:))
        }
        set {
            UserDefaults.standard.set(newValue?.absoluteString, forKey: baseURLKey)
        }
    }

    static var isConfigured: Bool {
        baseURL != nil
    }

    static var apiKey: String? {
        ApiKeyManager.shared.get(key: apiKeyName)
    }
}

enum AgentError: LocalizedError {
    case invalidResponse
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The agent did not return the expected JSON. Check the format described in Settings."
        case .server(let status):
            if status == 401 || status == 403 {
                return "The agent rejected the API key (HTTP \(status)). Check the key that was entered for the app."
            }
            return "The agent failed with HTTP \(status)."
        }
    }
}

/// One mixer edit the agent (or the local parser) asks for.
struct AgentCommand: Codable {
    enum Action: String, Codable {
        case setVolume = "set_volume"
        case mute
        case unmute
        case solo
        case unsolo
    }

    var action: Action
    var track: String
    var value: Double? = nil
}

/// The remote agent's reply: a short text and mixer commands to apply.
struct AgentReply: Codable {
    var reply: String?
    var commands: [AgentCommand]?
}

/// Parses plain-language mixer commands on device, e.g. "mute the drums".
/// Handles mute/unmute, solo/unsolo and fade-style volume words per track.
enum LocalAgentParser {

    enum VolumeChange {
        case set(Float)
        case adjust(Float)
    }

    static func parse(_ raw: String, tracks: [Track]) -> (commands: [AgentCommand], reply: String) {
        let text = raw.lowercased()
        let tokens = Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))

        var targets: [Track] = []
        if tokens.contains("all") || text.contains("everything") {
            targets = tracks
        } else {
            targets = tracks.filter { track in
                aliases(forTrackName: track.name).contains { alias in
                    alias.contains(" ") ? text.contains(alias) : tokens.contains(alias)
                }
            }
        }

        guard !targets.isEmpty else {
            return ([], "I couldn't find a track in that. Try a track name like 'mute the drums'.")
        }

        if text.contains("unmute") {
            return (targets.map { AgentCommand(action: .unmute, track: $0.name) }, confirmation(targets) { "\($0.name) unmuted" })
        }
        if text.contains("unsolo") || text.contains("desolo") {
            return (targets.map { AgentCommand(action: .unsolo, track: $0.name) }, confirmation(targets) { "\($0.name) unsoloed" })
        }
        if text.contains("solo") {
            return (targets.map { AgentCommand(action: .solo, track: $0.name) }, confirmation(targets) { "\($0.name) soloed" })
        }
        if text.contains("mute") {
            return (targets.map { AgentCommand(action: .mute, track: $0.name) }, confirmation(targets) { "\($0.name) muted" })
        }

        if let change = volumeChange(for: text, tokens: tokens, currentVolume: targets.first?.volume ?? 1) {
            let description: String
            let commands: [AgentCommand]
            switch change {
            case .set(let value):
                commands = targets.map { AgentCommand(action: .setVolume, track: $0.name, value: Double(value)) }
                description = "at \(percentText(for: value))"
            case .adjust(let delta):
                let current = targets.first?.volume ?? 1
                let new = min(1, max(0, current + delta))
                commands = targets.map { AgentCommand(action: .setVolume, track: $0.name, value: Double(new)) }
                description = "\(delta > 0 ? "raised" : "lowered") to \(percentText(for: new))"
            }
            return (commands, confirmation(targets) { _ in description })
        }

        return ([], "Try 'mute the drums', 'solo the vocals' or 'bring the bass down'.")
    }

    // MARK: - Helpers

    private static func confirmation(_ targets: [Track], _ part: (Track) -> String) -> String {
        "Done - \(targets.map(part).joined(separator: ", "))."
    }

    private static func percentText(for value: Float) -> String {
        "\(Int(round(value * 100)))%"
    }

    private static func volumeChange(for text: String, tokens: Set<String>, currentVolume: Float) -> VolumeChange? {
        if tokens.contains("max") || tokens.contains("maximum") || tokens.contains("full") { return .set(1) }
        if tokens.contains("min") || tokens.contains("minimum") || tokens.contains("zero")
            || tokens.contains("silent") || tokens.contains("off") { return .set(0) }
        if tokens.contains("half") { return .set(0.5) }

        if let numberText = firstMatch(in: text, pattern: #"to (\d+(?:\.\d+)?)"#),
           let number = Double(numberText) {
            return .set(number > 1 ? Float(number) / 100 : Float(number))
        }

        let upWords = ["raise", "raised", "up", "increase", "increased", "louder", "boost", "boosted", "higher"]
        let downWords = ["lower", "lowered", "down", "decrease", "decreased", "quieter", "softer", "reduce", "reduced", "bring"]
        let hasUp = upWords.contains { tokens.contains($0) }
        let hasDown = downWords.contains { tokens.contains($0) }
        if hasUp && !hasDown { return .adjust(+0.2) }
        if hasDown && !hasUp { return .adjust(-0.2) }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func aliases(forTrackName name: String) -> [String] {
        let lower = name.lowercased()
        var list = [lower]
        if lower.contains("vocal") || lower.contains("voice") {
            list += ["vocals", "vocal", "voice"]
        }
        if lower.contains("drum") {
            list += ["drums", "drum"]
        }
        if lower.contains("bass") {
            list += ["bass"]
        }
        if lower.contains("other") {
            list += ["other"]
        }
        return list
    }
}

/// Sends a chat message to the remote agent endpoint when one is configured.
///
/// Contract: POST JSON {"message": "…", "tracks": [{"name": "Vocals", "volume": 0.8,
/// "muted": false, "soloed": false}]} with an `Authorization: Bearer <key>` header
/// when a key is entered. The reply is {"reply": "…", "commands": [AgentCommand…]}.
@MainActor
final class AgentClient {

    func send(message: String, tracks: [Track]) async throws -> AgentReply {
        guard let endpoint = AgentSettings.baseURL else {
            throw AgentError.invalidResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = AgentSettings.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "message": message,
            "tracks": tracks.map { track in
                [
                    "name": track.name,
                    "volume": track.volume,
                    "muted": track.isMuted,
                    "soloed": track.isSoloed,
                ]
            },
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AgentError.server(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(AgentReply.self, from: data)
        } catch {
            throw AgentError.invalidResponse
        }
    }
}
