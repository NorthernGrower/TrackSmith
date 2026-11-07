//
//  ExportLibraryView.swift
//  AI Music Studio
//

import SwiftUI

enum ExportLibraryFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case mixes
    case stems
    case archives

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .mixes: return "Mixes"
        case .stems: return "Stems"
        case .archives: return "ZIPs"
        }
    }
}

struct ExportLibraryView: View {
    @ObservedObject var model: MixerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var midiShareItem: ShareItem?
    @State private var stemArchives: [MixExportArchive] = []
    @State private var searchText = ""
    @State private var selectedFilter = ExportLibraryFilter.all

    var body: some View {
        NavigationStack {
            Group {
                if !hasExports {
                    ContentUnavailableView(
                        "No Exports Yet",
                        systemImage: "waveform",
                        description: Text("Bounced mixes, stems, and stem archives will be saved here for sharing.")
                    )
                } else {
                    List {
                        Section {
                            TextField("Search exports or sessions", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Picker("Filter exports", selection: $selectedFilter) {
                                ForEach(ExportLibraryFilter.allCases) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel("Filter exports by type")
                        }
                        .listRowBackground(Color.studioPanel)

                        if !visibleArchives.isEmpty {
                            Section("Stem Archives") {
                                ForEach(visibleArchives) { archive in
                                    archiveRow(archive)
                                }
                            }
                        }

                        if !visibleMixes.isEmpty {
                            Section(audioSectionTitle) {
                                ForEach(visibleMixes) { mix in
                                    audioRow(mix)
                                }
                            }
                        }

                        if visibleArchives.isEmpty && visibleMixes.isEmpty {
                            ContentUnavailableView(
                                "No Matching Exports",
                                systemImage: "magnifyingglass",
                                description: Text("Try another name or export type.")
                            )
                            .listRowBackground(Color.clear)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.studioBackground)
                }
            }
            .background(Color.studioBackground)
            .navigationTitle("Mix Exports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        let noteTracks = model.tracks.filter { !$0.notes.isEmpty }
                        if noteTracks.isEmpty {
                            Text("No tracks with notes")
                        } else {
                            ForEach(noteTracks) { track in
                                Button(track.name) {
                                    model.exportMIDI(trackID: track.id)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "music.note.list")
                    }
                    .accessibilityLabel("Export a track as MIDI")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $midiShareItem) { item in
            ShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: model.midiExportURL) { _, url in
            guard let url else { return }
            midiShareItem = ShareItem(url: url)
            model.clearMIDIExportURL()
        }
        .alert("MIDI Export", isPresented: midiErrorAlert) {
            Button("OK", role: .cancel) { model.midiError = nil }
        } message: {
            Text(model.midiError ?? "")
        }
        .onAppear {
            model.refreshExports()
            stemArchives = MixExportStorage.loadStemArchives()
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    private var hasExports: Bool {
        !model.exports.isEmpty || !stemArchives.isEmpty
    }

    private var visibleMixes: [MixExport] {
        model.exports.filter { export in
            switch selectedFilter {
            case .all:
                break
            case .mixes:
                guard export.kind == .mix else { return false }
            case .stems:
                guard export.kind == .stem else { return false }
            case .archives:
                return false
            }
            return matchesSearch(name: export.name, sessionName: export.sessionName)
        }
    }

    private var audioSectionTitle: String {
        switch selectedFilter {
        case .mixes: return "Mixes"
        case .stems: return "Stems"
        case .all, .archives: return "Audio Exports"
        }
    }

    private var visibleArchives: [MixExportArchive] {
        guard selectedFilter == .all || selectedFilter == .archives else { return [] }
        return stemArchives.filter { archive in
            matchesSearch(name: archive.name, sessionName: archive.sessionName)
        }
    }

    private func matchesSearch(name: String, sessionName: String?) -> Bool {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(term)
            || (sessionName?.localizedCaseInsensitiveContains(term) ?? false)
    }

    private func archiveRow(_ archive: MixExportArchive) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.studioAccent)
                .frame(width: 38, height: 38)
                .background(Color.studioAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                Text(archive.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("ZIP  ·  \(archive.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(archive.sessionName.map { "Session · \($0)" } ?? "Session · unavailable for older export")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            ShareLink(item: archive.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Share \(archive.name)")
        }
        .padding(.vertical, 5)
        .listRowBackground(Color.studioPanel)
    }

    private func audioRow(_ mix: MixExport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.studioAccent)
                .frame(width: 38, height: 38)
                .background(Color.studioAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                Text(mix.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("\(mix.kind.title.uppercased())  ·  \(studioTimeString(mix.duration))  ·  \(mix.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(mix.sessionName.map { "Session · \($0)" } ?? "Session · unavailable for older export")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            ShareLink(item: mix.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Share \(mix.name)")
        }
        .padding(.vertical, 5)
        .listRowBackground(Color.studioPanel)
    }

    private var midiErrorAlert: Binding<Bool> {
        Binding(
            get: { model.midiError != nil },
            set: { presenting in
                if !presenting { model.midiError = nil }
            }
        )
    }
}
