//
//  ChannelPresetsView.swift
//  AI Music Studio
//

import SwiftUI

/// Saves channel strips on device and applies them to other tracks.
struct ChannelPresetsView: View {
    @ObservedObject var model: MixerViewModel
    var initialTrackID: UUID?

    @Environment(\.dismiss) private var dismiss

    @State private var selectedPresetID: UUID?
    @State private var sourceTrackID: UUID?
    @State private var targetTrackID: UUID?
    @State private var saveName = ""
    @State private var showingSave = false
    @State private var renamePresetID: UUID?
    @State private var renameDraft = ""
    @State private var showingRename = false
    @State private var appliedMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    savePanel
                    presetList
                }
                .padding(16)
            }
            .background(Color.studioBackground)
            .navigationTitle("Channel Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { applyBar }
        }
        .onAppear {
            if sourceTrackID == nil {
                sourceTrackID = initialTrackID ?? model.tracks.first?.id
            }
            if targetTrackID == nil {
                targetTrackID = model.tracks.first(where: { $0.id != sourceTrackID })?.id
                    ?? model.tracks.first?.id
            }
        }
        .alert("Save Preset", isPresented: $showingSave) {
            TextField("Preset name", text: $saveName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let sourceTrackID,
                   let id = model.saveChannelPreset(from: sourceTrackID, name: saveName) {
                    selectedPresetID = id
                    appliedMessage = nil
                }
            }
        } message: {
            Text("Captures the EQ, compressor, pan and level of \(sourceTrackName).")
        }
        .alert("Rename Preset", isPresented: $showingRename) {
            TextField("Preset name", text: $renameDraft)
            Button("Cancel", role: .cancel) { renamePresetID = nil }
            Button("Save") {
                if let renamePresetID {
                    model.renameChannelPreset(renamePresetID, to: renameDraft)
                }
                renamePresetID = nil
            }
        } message: {
            Text("Choose a name for this preset.")
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    private var sourceTrackName: String {
        guard let sourceTrackID,
              let track = model.tracks.first(where: { $0.id == sourceTrackID }) else {
            return "this track"
        }
        return track.name
    }

    private var savePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SAVE THIS CHANNEL")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.studioAccent)

            if model.tracks.isEmpty {
                Text("Add a track to capture its channel settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(model.tracks) { track in
                            Button {
                                sourceTrackID = track.id
                            } label: {
                                Label(track.name, systemImage: track.id == sourceTrackID ? "checkmark" : "waveform")
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                            Text(sourceTrackName)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.studioAccent)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(Color.studioAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel("Preset source track")

                    Spacer(minLength: 4)

                    Button {
                        saveName = "\(sourceTrackName) Preset"
                        showingSave = true
                    } label: {
                        Label("Save Preset", systemImage: "bookmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Color.studioAccent, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var presetList: some View {
        if model.channelPresets.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bookmark")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.studioAccent)
                Text("No presets yet")
                    .font(.system(size: 13, weight: .semibold))
                Text("Save a channel above to reuse its EQ, compressor, pan and level.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("LIBRARY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                ForEach(model.channelPresets) { preset in
                    presetRow(preset)
                }
            }
        }
    }

    private func presetRow(_ preset: ChannelPreset) -> some View {
        let isSelected = selectedPresetID == preset.id

        return HStack(spacing: 10) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.studioAccent)
                .frame(width: 38, height: 38)
                .background(
                    Color.studioAccent.opacity(isSelected ? 0.22 : 0.12),
                    in: RoundedRectangle(cornerRadius: 9)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(preset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if isSelected {
                        Text("SELECTED")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(Color.studioAccent)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.studioAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text(preset.summary)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Menu {
                Button {
                    renamePresetID = preset.id
                    renameDraft = preset.name
                    showingRename = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    model.deleteChannelPreset(preset.id)
                    if selectedPresetID == preset.id {
                        selectedPresetID = nil
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Preset actions for \(preset.name)")
        }
        .padding(10)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(isSelected ? Color.studioAccent.opacity(0.6) : Color.white.opacity(0.07), lineWidth: isSelected ? 1.5 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedPresetID = preset.id }
    }

    private var applyBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("APPLY TO")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.studioAccent)

                Spacer(minLength: 4)

                if let appliedMessage {
                    Text(appliedMessage)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.tracks) { track in
                        Button {
                            targetTrackID = track.id
                            appliedMessage = nil
                        } label: {
                            Text(track.name.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                                .lineLimit(1)
                                .foregroundStyle(targetTrackID == track.id ? Color.black : Color.white.opacity(0.75))
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(
                                    targetTrackID == track.id ? Color.studioAccent : Color.studioPanelHighlight.opacity(0.7),
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Apply preset to \(track.name)")
                    }
                }
            }

            Button {
                applySelected()
            } label: {
                Label("Apply Preset", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color.studioAccent, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(selectedPresetID == nil || targetTrackID == nil)
            .opacity(selectedPresetID == nil || targetTrackID == nil ? 0.45 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.studioPanel)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
        }
    }

    private func applySelected() {
        guard let selectedPresetID, let targetTrackID else { return }
        model.applyChannelPreset(selectedPresetID, to: targetTrackID)
        let name = model.tracks.first(where: { $0.id == targetTrackID })?.name ?? "track"
        appliedMessage = "Applied to \(name)"
    }
}
