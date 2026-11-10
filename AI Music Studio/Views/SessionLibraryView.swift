//
//  SessionLibraryView.swift
//  AI Music Studio
//

import SwiftUI
import UIKit

struct SessionLibraryView: View {
    @ObservedObject var model: MixerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var renameSessionID: UUID?
    @State private var renameDraft = ""
    @State private var showingRename = false
    @State private var deleteSessionID: UUID?
    @State private var showingDeleteConfirmation = false
    @State private var isSavingTemplate = false
    @State private var templateName = ""
    @State private var isChoosingImport = false
    @State private var pendingImport: PendingSessionImport?
    @State private var showingNameCollision = false
    @State private var shareItem: SessionShareItem?
    @State private var searchText = ""
    @State private var sortOrder: SessionSortOrder = .recentlyEdited

    private struct PendingSessionImport {
        let url: URL
        let summary: SessionArchiveSummary
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if visibleSessions.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(visibleSessions) { session in
                            sessionRow(session)
                                .listRowBackground(Color.studioPanel)
                        }
                    }
                } header: {
                    HStack {
                        Text("SORT BY")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Sort sessions", selection: $sortOrder) {
                            Text("Recently Edited").tag(SessionSortOrder.recentlyEdited)
                            Text("Name").tag(SessionSortOrder.name)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                        .accessibilityLabel("Sort sessions")
                    }
                    .textCase(nil)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search sessions")
            .scrollContentBackground(.hidden)
            .background(Color.studioBackground)
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isChoosingImport = true
                    } label: {
                        Label("Import Session", systemImage: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        templateName = model.sessionName
                        isSavingTemplate = true
                    } label: {
                        Label("Save as Template", systemImage: "bookmark")
                    }
                    .disabled(model.tracks.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.createSession()
                        dismiss()
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $isChoosingImport,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                handleImportSelection(result)
            }
            .overlay {
                if let progress = model.sessionTransferProgress {
                    transferOverlay(progress: progress)
                }
            }
        }
        .alert("Rename Session", isPresented: $showingRename) {
            TextField("Session name", text: $renameDraft)
            Button("Cancel", role: .cancel) { renameSessionID = nil }
            Button("Save") {
                if let renameSessionID {
                    model.renameSession(renameSessionID, to: renameDraft)
                }
                renameSessionID = nil
            }
        } message: {
            Text("Choose a name for this session.")
        }
        .alert("Save as Template", isPresented: $isSavingTemplate) {
            TextField("Template name", text: $templateName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                model.saveCurrentSessionAsTemplate(name: templateName)
            }
        } message: {
            Text("Keeps this session's tracks, colours and mixer settings so you can start new sessions from them.")
        }
        .alert("Session Transfer", isPresented: transferError) {
            Button("OK") { model.sessionTransferError = nil }
        } message: {
            Text(model.sessionTransferError ?? "")
        }
        .confirmationDialog(
            collisionTitle,
            isPresented: $showingNameCollision,
            titleVisibility: .visible,
            presenting: pendingImport
        ) { pending in
            Button("Keep Both") {
                model.importSessionArchive(from: pending.url, keepBoth: true)
                pendingImport = nil
            }
            Button("Replace Existing", role: .destructive) {
                model.importSessionArchive(from: pending.url, keepBoth: false)
                pendingImport = nil
            }
            Button("Cancel", role: .cancel) {
                pendingImport = nil
            }
        } message: { _ in
            Text("Keep Both adds a copy alongside it. Replacing deletes the session with that name and puts the backup in its place.")
        }
        .confirmationDialog("Delete this session?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Session", role: .destructive) {
                if let deleteSessionID {
                    model.deleteSession(deleteSessionID)
                }
                deleteSessionID = nil
            }
            Button("Cancel", role: .cancel) { deleteSessionID = nil }
        } message: {
            Text("The session and its track arrangement will be removed.")
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: model.sessionExportURL) { _, url in
            guard let url else { return }
            shareItem = SessionShareItem(url: url)
            model.clearSessionExportURL()
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    private var visibleSessions: [StudioSession] {
        let matchingSessions = model.sessions.filter { session in
            searchText.isEmpty || session.name.localizedStandardContains(searchText)
        }

        switch sortOrder {
        case .recentlyEdited:
            return matchingSessions.sorted {
                if $0.lastEdited == $1.lastEdited {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.lastEdited > $1.lastEdited
            }
        case .name:
            return matchingSessions.sorted {
                let comparison = $0.name.localizedStandardCompare($1.name)
                if comparison == .orderedSame {
                    return $0.lastEdited > $1.lastEdited
                }
                return comparison == .orderedAscending
            }
        }
    }

    private var collisionTitle: String {
        let name = pendingImport?.summary.sessionName ?? "This session"
        return "A session named “\(name)” already exists"
    }

    private var transferError: Binding<Bool> {
        Binding(
            get: { model.sessionTransferError != nil },
            set: { if !$0 { model.sessionTransferError = nil } }
        )
    }

    private func transferOverlay(progress: Double) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Text(model.sessionTransferTitle.isEmpty ? "Working…" : model.sessionTransferTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .multilineTextAlignment(.center)

                ProgressView(value: min(1, max(0, progress)))
                    .tint(Color.studioAccent)

                Text("\(Int(min(1, max(0, progress)) * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: 260)
            .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func handleFileImport(_ url: URL) {
        do {
            let summary = try model.inspectSessionArchive(at: url)
            let pending = (url: url, summary: summary)
            if model.sessionExists(named: summary.sessionName) {
                pendingImport = PendingSessionImport(url: pending.url, summary: pending.summary)
                showingNameCollision = true
            } else {
                model.importSessionArchive(from: url, keepBoth: true)
            }
        } catch {
            model.sessionTransferError = (error as? LocalizedError)?.errorDescription
                ?? "That file could not be read."
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            handleFileImport(url)
        case .failure:
            break
        }
    }

    private func sessionRow(_ session: StudioSession) -> some View {
        HStack(spacing: 10) {
            Button {
                model.openSession(session.id)
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: session.id == model.activeSessionID ? "waveform" : "folder")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.studioAccent)
                        .frame(width: 38, height: 38)
                        .background(Color.studioAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(session.name)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            if session.id == model.activeSessionID {
                                Text("OPEN")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .tracking(0.6)
                                    .foregroundStyle(Color.studioAccent)
                            }
                        }
                        let count = session.tracks.count
                        Text("\(count) \(count == 1 ? "track" : "tracks")  ·  Edited \(session.lastEdited.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    model.openSession(session.id)
                    dismiss()
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }

                Button {
                    model.exportSession(session.id)
                } label: {
                    Label("Export Session", systemImage: "square.and.arrow.up")
                }

                Button {
                    renameSessionID = session.id
                    renameDraft = session.name
                    showingRename = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button {
                    model.duplicateSession(session.id)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }

                Divider()

                Button(role: .destructive) {
                    deleteSessionID = session.id
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(model.sessions.count <= 1)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Session actions for \(session.name)")
        }
        .padding(.vertical, 5)
    }
}

private enum SessionSortOrder: String, CaseIterable, Hashable {
    case recentlyEdited
    case name
}

private struct SessionShareItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// The system share sheet, used to send a session backup out of the app.
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
