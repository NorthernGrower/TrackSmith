import SwiftUI

struct LyricsLibraryView: View {
    let onLoad: (LyricsDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var drafts = LyricsDraftStorage.loadDrafts()
    @State private var selected: LyricsDraft?
    @State private var renameTarget: LyricsDraft?
    @State private var renameText = ""
    @State private var deleteTarget: LyricsDraft?

    var body: some View {
        NavigationStack {
            List {
                if drafts.isEmpty {
                    ContentUnavailableView("No Saved Lyrics", systemImage: "book.closed", description: Text("Generated lyric sheets are saved here automatically."))
                        .listRowBackground(Color.clear)
                }
                ForEach(drafts) { draft in
                    Button { selected = draft } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(draft.title).font(.headline).foregroundStyle(.primary)
                            Text("\(draft.genreTitle) · \(draft.topic.isEmpty ? "No topic" : draft.topic)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(draft.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }.padding(.vertical, 4)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = draft }
                        Button("Copy", systemImage: "doc.on.doc") { _ = LyricsDraftStorage.copy(draft); refresh() }
                        Button("Rename", systemImage: "pencil") { renameTarget = draft; renameText = draft.title }
                            .tint(.orange)
                    }
                    .contextMenu {
                        Button("Load in Songwriter", systemImage: "text.quote") { onLoad(draft); dismiss() }
                        Button("Copy", systemImage: "doc.on.doc") { _ = LyricsDraftStorage.copy(draft); refresh() }
                        Button("Rename", systemImage: "pencil") { renameTarget = draft; renameText = draft.title }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = draft }
                    }
                }
            }
            .navigationTitle("Lyrics Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $selected) { draft in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(draft.title).font(.title2.bold())
                            Text("\(draft.genreTitle) · \(draft.topic)").font(.subheadline).foregroundStyle(.secondary)
                            ForEach(draft.sections) { section in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(section.title.uppercased()).font(.caption.bold()).tracking(1).foregroundStyle(.orange)
                                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in Text(line) }
                                }
                            }
                            Button { onLoad(draft); selected = nil; dismiss() } label: {
                                Label("Load in Songwriter", systemImage: "text.quote").frame(maxWidth: .infinity).padding()
                            }.buttonStyle(.borderedProminent).tint(.orange)
                        }.padding()
                    }.navigationTitle("Lyric Sheet").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { selected = nil } } }
                }
                .studioAgentAccess(context: "Lyric Sheet")
                .preferredColorScheme(.dark)
            }
            .alert("Rename Lyrics", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                TextField("Title", text: $renameText)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Save") {
                    if let draft = renameTarget, !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        _ = LyricsDraftStorage.rename(draft, to: renameText); refresh()
                    }
                    renameTarget = nil
                }
            }
            .confirmationDialog("Delete this lyric sheet?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let draft = deleteTarget { LyricsDraftStorage.delete(draft.id); refresh() }; deleteTarget = nil }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            }
        }
        .studioAgentAccess(context: "Lyrics Library")
        .preferredColorScheme(.dark)
        .tint(.orange)
    }

    private func refresh() { drafts = LyricsDraftStorage.loadDrafts() }
}
