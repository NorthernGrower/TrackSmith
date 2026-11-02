//
//  SampleLibraryView.swift
//  AI Music Studio
//

import SwiftUI

/// Browses the audio already stored on device and loads one into the sampler.
struct SampleLibraryView: View {
    @ObservedObject var model: MixerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedItemID: String?

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.studioBackground)
                .navigationTitle("Sample Library")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search sounds"
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) { loadBar }
        }
        .task {
            if selectedItemID == nil {
                selectedItemID = model.loadedSampleFileName
            }
            model.refreshSampleLibrary()
        }
        .onDisappear { model.stopSamplePreview() }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    @ViewBuilder
    private var content: some View {
        if model.sampleLibrary.isEmpty, model.isLoadingSampleLibrary {
            VStack(spacing: 11) {
                ProgressView()
                    .tint(Color.studioAccent)
                Text("Reading your sounds")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } else if model.sampleLibrary.isEmpty {
            ContentUnavailableView {
                Label("No Sounds Yet", systemImage: "folder")
            } description: {
                Text("Imported tracks, split stems and recorded takes stay on this device and appear here.")
            }
        } else if filteredItems.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            soundList
        }
    }

    private var soundList: some View {
        List {
            Section {
                ForEach(filteredItems) { item in
                    soundRow(item)
                        .listRowBackground(Color.studioPanel)
                        .listRowSeparatorTint(Color.white.opacity(0.08))
                }
            } header: {
                Text(countLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.studioBackground)
    }

    private func soundRow(_ item: SampleLibraryItem) -> some View {
        let isSelected = selectedItemID == item.id
        let isLoaded = model.loadedSampleFileName == item.id
        let isPreviewing = model.previewingSampleID == item.id

        return HStack(spacing: 8) {
            Button {
                selectedItemID = item.id
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: isPreviewing ? "speaker.wave.2.fill" : "waveform")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.studioAccent)
                        .frame(width: 38, height: 38)
                        .background(
                            Color.studioAccent.opacity(isSelected ? 0.22 : 0.11),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.studioAccent.opacity(isSelected ? 0.85 : 0), lineWidth: 1.5)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(item.name)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            if isLoaded {
                                Text("SAMPLER")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .tracking(0.6)
                                    .foregroundStyle(Color.studioAccent)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        Color.studioAccent.opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 3)
                                    )
                            }
                        }

                        Text("\(studioTimeString(item.duration))  ·  \(item.formatLabel)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isLoaded ? "\(item.name), loaded in sampler" : "Select \(item.name)"
            )

            Button {
                model.previewSample(item)
            } label: {
                Image(systemName: isPreviewing ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(isPreviewing ? Color.studioAccent : Color.white.opacity(0.28))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPreviewing ? "Stop preview of \(item.name)" : "Preview \(item.name)")
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var loadBar: some View {
        if let selectedItem {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SELECTED SOUND")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text(selectedItem.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    Button {
                        model.loadSamplerSample(selectedItem)
                        dismiss()
                    } label: {
                        Label("Load into Sampler", systemImage: "waveform.badge.plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 13)
                            .frame(height: 44)
                            .background(Color.studioAccent, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.studioPanel)
            }
        }
    }

    private var filteredItems: [SampleLibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.sampleLibrary }
        return model.sampleLibrary.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var selectedItem: SampleLibraryItem? {
        guard let selectedItemID else { return nil }
        return model.sampleLibrary.first { $0.id == selectedItemID }
    }

    private var countLabel: String {
        let count = filteredItems.count
        return "\(count) \(count == 1 ? "SOUND" : "SOUNDS")  ·  ON DEVICE"
    }
}
