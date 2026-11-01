//
//  SettingsView.swift
//  AI Music Studio
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var agentURLText = AgentSettings.baseURL?.absoluteString ?? ""
    @State private var agentKeySet = ApiKeyManager.shared.has(key: AgentSettings.apiKeyName)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Agent base URL (https://…)", text: $agentURLText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: agentURLText) { _, newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                            AgentSettings.baseURL = trimmed.isEmpty ? nil : URL(string: trimmed)
                        }

                    HStack {
                        Text("API key")
                        Spacer()
                        Text(agentKeySet ? "Saved" : "Not entered yet")
                            .foregroundStyle(agentKeySet ? Color.green : Color.secondary)
                    }

                    Text("Enter your agent API key using the key entry card in the chat app. It is stored securely in the Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("When set, chat messages go to the agent instead of being parsed on device. The app posts {\"message\": \"…\", \"tracks\": [{\"name\": \"Vocals\", \"volume\": 0.8, \"muted\": false, \"soloed\": false}]} and applies the commands in the reply:")
                        .font(.footnote)
                    Text("{\"reply\": \"Done.\", \"commands\": [{\"action\": \"set_volume|mute|unmute|solo|unsolo\", \"track\": \"drums\", \"value\": 0.3}]}")
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text("Agent API")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
