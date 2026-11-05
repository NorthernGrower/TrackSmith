//
//  SessionVersionsView.swift
//  AI Music Studio
//

import SwiftUI

/// Autosaved snapshots of the open session, with preview, restore and duplicate.
struct SessionVersionsView: View {
    @ObservedObject var model: MixerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    autosaveRow
                        .listRowBackground(Color.studioPanel)
                }

                if model.versions.isEmpty {
                    Section {
                        Text("No versions yet. Change the session and a snapshot appears here a couple of seconds later.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.studioPanel)
                    }
                } else {
                    Section("Versions") {
                        ForEach(model.versions) { version in
                            NavigationLink {
                                SessionVersionPreview(
                                    version: version,
                                    onRestore: {
                                        model.restoreVersion(version.id)
                                        dismiss()
                                    },
                                    onDuplicate: {
                                        model.duplicateVersion(version.id)
                                        dismiss()
                                    }
                                )
                            } label: {
                                versionRow(version, isLatest: version.id == model.versions.first?.id)
                            }
                            .listRowBackground(Color.studioPanel)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.studioBackground)
            .navigationTitle("Session Versions")
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

    private var autosaveRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AUTOSAVE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.studioAccent)

                Text(model.versions.isEmpty
                    ? "Snapshots are kept on this device."
                    : "\(model.versions.count) on this device · newest first")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.studioAccent)
        }
        .padding(.vertical, 2)
    }

    private func versionRow(_ version: SessionVersion, isLatest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(version.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.studioAccent)

                if isLatest {
                    Text("LATEST")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.studioAccent.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.studioAccent)
                }
            }

            Text("\(version.createdAt.formatted(date: .abbreviated, time: .omitted)) · \(version.trackCount) \(version.trackCount == 1 ? "track" : "tracks") · \(Self.formatDuration(version.duration))")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 3)
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, duration)
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// One snapshot in detail, with its arrangement and the restore actions.
private struct SessionVersionPreview: View {
    let version: SessionVersion
    var onRestore: () -> Void
    var onDuplicate: () -> Void

    @State private var showingRestoreConfirmation = false

    private let palette: [Color] = [
        Color(red: 0.98, green: 0.62, blue: 0.18),
        Color(red: 0.16, green: 0.66, blue: 0.60),
        Color(red: 0.36, green: 0.56, blue: 0.93),
        Color(red: 0.80, green: 0.42, blue: 0.78)
    ]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text(version.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 14, weight: .semibold))
                    Text(version.name)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .listRowBackground(Color.studioPanel)
            }

            Section {
                LabeledContent("Tracks", value: "\(version.trackCount)")
                LabeledContent("Duration", value: SessionVersionsView.formatDuration(version.duration))
                LabeledContent("Tempo", value: "\(version.tempoBPM) BPM")
                LabeledContent("Sections", value: "\(version.sectionCount)")
            }
            .listRowBackground(Color.studioPanel)

            Section("Arrangement") {
                if version.session.tracks.isEmpty {
                    Text("No tracks in this version.")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.studioPanel)
                } else {
                    ForEach(Array(version.session.tracks.enumerated()), id: \.element.id) { index, track in
                        HStack(spacing: 9) {
                            Circle()
                                .fill(palette[index % palette.count])
                                .frame(width: 8, height: 8)

                            Text(track.name)
                                .font(.system(size: 12))
                                .lineLimit(1)

                            Spacer(minLength: 6)

                            Text("\(track.clips.count + track.notes.count)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.studioPanel)
                    }
                }
            }

            Section {
                Button("Restore This Version") {
                    showingRestoreConfirmation = true
                }
                .foregroundStyle(Color.studioAccent)

                Button("Open as a New Session") {
                    onDuplicate()
                }
                .foregroundStyle(Color.studioAccent)
            }
            .listRowBackground(Color.studioPanel)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.studioBackground)
        .navigationTitle("Version")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Restore this version?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) { onRestore() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The session will be replaced with this snapshot. Your current state is saved as a version first.")
        }
    }
}
