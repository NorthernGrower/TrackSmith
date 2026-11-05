//
//  TakeLaneView.swift
//  AI Music Studio
//

import SwiftUI

/// The numbered take lane for one track: audition, promote, rename or delete takes.
struct TakeLaneView: View {
    @ObservedObject var model: MixerViewModel
    let trackID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var renamingTakeID: UUID?
    @State private var renameDraft = ""
    @State private var showingRename = false

    private var track: Track? {
        model.tracks.first(where: { $0.id == trackID })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let track, !track.takes.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(track.takes.count) \(track.takes.count == 1 ? "TAKE" : "TAKES") · ONE PLAYS ON THE TIMELINE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.7)
                                .foregroundStyle(.secondary)

                            ForEach(Array(track.takes.enumerated()), id: \.element.id) { index, take in
                                takeRow(track: track, take: take, number: index + 1)
                            }
                        }
                        .padding(16)
                    }
                } else {
                    ContentUnavailableView(
                        "No Takes Yet",
                        systemImage: "square.stack.3d.up",
                        description: Text("Record onto this track and every pass will be kept here.")
                    )
                }
            }
            .background(Color.studioBackground)
            .navigationTitle("Take Lane")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.stopTakeAudition()
                        dismiss()
                    }
                }
            }
        }
        .alert("Rename Take", isPresented: $showingRename) {
            TextField("Take name", text: $renameDraft)
            Button("Cancel", role: .cancel) { renamingTakeID = nil }
            Button("Save") {
                if let renamingTakeID {
                    model.renameTake(trackID: trackID, takeID: renamingTakeID, to: renameDraft)
                }
                renamingTakeID = nil
            }
        } message: {
            Text("Give this take a name you recognise.")
        }
        .onDisappear { model.stopTakeAudition() }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    private func takeRow(track: Track, take: TrackTake, number: Int) -> some View {
        let isActive = track.activeTakeID == take.id
        let isAuditioning = model.auditioningTakeID == take.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("T\(number)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(isActive ? Color.black : Color.studioAccent)
                    .background(
                        isActive ? Color.studioAccent : Color.studioAccent.opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(take.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(studioTimeString(take.duration))  ·  starts \(studioTimeString(take.startTime))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                if isActive {
                    Text("ACTIVE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.studioAccent, in: Capsule())
                }
            }

            HStack(spacing: 8) {
                Button {
                    if isAuditioning {
                        model.stopTakeAudition()
                    } else {
                        model.auditionTake(trackID: trackID, takeID: take.id)
                    }
                } label: {
                    Label(isAuditioning ? "Stop" : "Audition", systemImage: isAuditioning ? "stop.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .background(Color.studioPanelHighlight.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))

                Button {
                    model.promoteTake(trackID: trackID, takeID: take.id)
                } label: {
                    Label("Promote", systemImage: "arrow.up.to.line")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isActive ? Color.secondary : Color.black)
                .background(
                    isActive ? Color.studioPanelHighlight.opacity(0.4) : Color.studioAccent,
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .disabled(isActive)

                Button {
                    renamingTakeID = take.id
                    renameDraft = take.name
                    showingRename = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 36, height: 34)
                }
                .buttonStyle(.plain)
                .background(Color.studioPanelHighlight.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityLabel("Rename \(take.name)")

                Button {
                    model.deleteTake(trackID: trackID, takeID: take.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.88, green: 0.42, blue: 0.38))
                        .frame(width: 36, height: 34)
                }
                .buttonStyle(.plain)
                .background(Color.studioPanelHighlight.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityLabel("Delete \(take.name)")
            }
        }
        .padding(12)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.studioAccent.opacity(0.4) : Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}
