//
//  InstrumentSoundView.swift
//  AI Music Studio
//

import SwiftUI

/// Browsable list of every voice and its presets, applied to the open track.
struct InstrumentSoundView: View {
    @ObservedObject var model: MixerViewModel
    let trackID: UUID

    @Environment(\.dismiss) private var dismiss

    private var track: Track? {
        model.tracks.first { $0.id == trackID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let track {
                    List {
                        Section {
                            HStack(spacing: 12) {
                                Image(systemName: track.voice.systemImage)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.studioAccent)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        Color.studioAccent.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(track.soundPreset.name)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(track.voice.title)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.studioPanel)
                        } header: {
                            Text("CURRENT SOUND")
                        }

                        ForEach(InstrumentPresetLibrary.voiceOrder) { voice in
                            Section {
                                ForEach(InstrumentPresetLibrary.presets(for: voice)) { preset in
                                    Button {
                                        model.setInstrumentPreset(preset.id, for: trackID)
                                    } label: {
                                        row(preset, isSelected: track.soundPreset.id == preset.id)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Color.studioPanel)
                                }
                            } header: {
                                Label(voice.title, systemImage: voice.systemImage)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                } else {
                    ContentUnavailableView(
                        "Track Removed",
                        systemImage: "pianokeys",
                        description: Text("This track is no longer part of the session.")
                    )
                }
            }
            .background(Color.studioBackground)
            .navigationTitle("Sounds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    private func row(_ preset: InstrumentPreset, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(preset.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.studioAccent)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }
}
