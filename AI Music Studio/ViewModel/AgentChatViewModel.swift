//
//  AgentChatViewModel.swift
//  AI Music Studio
//

import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let isUser: Bool
    let text: String
}

/// The agent conversation in the chat drawer. Messages go to the remote agent
/// when one is configured in Settings; otherwise commands are parsed on device
/// and applied to the mixer immediately.
@MainActor
final class AgentChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = [
        ChatMessage(isUser: false, text: "Tell me what to change - for example 'mute the drums' or 'bring the vocals down'.")
    ]
    @Published var draft = ""
    @Published private(set) var isWaiting = false
    weak var mixer: MixerViewModel?

    private let client = AgentClient()

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWaiting, let mixer else { return }

        draft = ""
        messages.append(ChatMessage(isUser: true, text: text))
        isWaiting = true

        Task {
            defer { isWaiting = false }
            if AgentSettings.isConfigured {
                await sendRemote(text, mixer: mixer)
            } else {
                let (commands, reply) = LocalAgentParser.parse(text, tracks: mixer.tracks)
                apply(commands, mixer: mixer)
                messages.append(ChatMessage(isUser: false, text: reply))
            }
        }
    }

    private func sendRemote(_ message: String, mixer: MixerViewModel) async {
        do {
            let reply = try await client.send(message: message, tracks: mixer.tracks)
            let commands = reply.commands ?? []
            apply(commands, mixer: mixer)
            if let text = reply.reply, !text.isEmpty {
                messages.append(ChatMessage(isUser: false, text: text))
            } else {
                messages.append(ChatMessage(isUser: false, text: commands.isEmpty ? "I couldn't do that." : "Done."))
            }
        } catch {
            let description = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach the agent."
            messages.append(ChatMessage(isUser: false, text: description))
        }
    }

    private func apply(_ commands: [AgentCommand], mixer: MixerViewModel) {
        for command in commands {
            guard let track = mixer.track(named: command.track) else { continue }
            switch command.action {
            case .setVolume:
                let value = Float(min(1, max(0, command.value ?? 1)))
                mixer.setVolume(track.id, value)
            case .mute:
                mixer.setMuted(track.id, true)
            case .unmute:
                mixer.setMuted(track.id, false)
            case .solo:
                mixer.setSoloed(track.id, true)
            case .unsolo:
                mixer.setSoloed(track.id, false)
            }
        }
        mixer.commitSession()
    }
}
