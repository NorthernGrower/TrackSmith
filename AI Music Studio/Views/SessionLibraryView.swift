//
//  SessionLibraryView.swift
//  AI Music Studio
//

import SwiftUI

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

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.sessions.sorted(by: { $0.lastEdited > $1.lastEdited })) { session in
                    sessionRow(session)
                        .listRowBackground(Color.studioPanel)
                }
            }
            .listStyle(.plain)
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
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
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
