//
//  LyricsDraft.swift
//  AI Music Studio
//

import Foundation

/// One labelled block of a written song, such as a verse or a chorus.
struct LyricSection: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var lines: [String]

    init(id: UUID = UUID(), title: String, lines: [String]) {
        self.id = id
        self.title = title
        self.lines = lines
    }
}

/// A generated lyric sheet for one song idea.
struct LyricsDraft: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var genreID: String
    var genreTitle: String
    var topic: String
    var sections: [LyricSection]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        genreID: String,
        genreTitle: String,
        topic: String,
        sections: [LyricSection],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.genreID = genreID
        self.genreTitle = genreTitle
        self.topic = topic
        self.sections = sections
        self.createdAt = createdAt
    }

    /// The full sheet as copyable text, e.g. for sharing with a co-writer.
    var plainText: String {
        var text = "\(title)\n\(genreTitle)\(topic.isEmpty ? "" : " · \(topic)")\n"
        for section in sections {
            text += "\n[\(section.title)]\n"
            for line in section.lines {
                text += line + "\n"
            }
        }
        return text
    }

    /// The first chorus, used as the hook shown in short summaries.
    var hook: String {
        sections.first(where: { $0.title.hasPrefix("Chorus") })?.lines.first
            ?? sections.first?.lines.first
            ?? title
    }
}

/// Keeps generated lyric sheets on device so a writer can come back to them.
enum LyricsDraftStorage {
    private static let draftsKey = "studio.lyricDrafts"
    private static let maximumDrafts = 20

    static func loadDrafts() -> [LyricsDraft] {
        guard let data = UserDefaults.standard.data(forKey: draftsKey),
              let drafts = try? JSONDecoder().decode([LyricsDraft].self, from: data) else {
            return []
        }
        return drafts.sorted { $0.createdAt > $1.createdAt }
    }

    static func loadLast() -> LyricsDraft? {
        loadDrafts().first
    }

    static func save(_ draft: LyricsDraft) {
        var drafts = loadDrafts().filter { $0.id != draft.id }
        drafts.insert(draft, at: 0)
        if drafts.count > maximumDrafts {
            drafts = Array(drafts.prefix(maximumDrafts))
        }
        persist(drafts)
    }

    static func delete(_ id: UUID) {
        persist(loadDrafts().filter { $0.id != id })
    }

    static func copy(_ draft: LyricsDraft) -> LyricsDraft {
        var duplicate = draft
        duplicate.id = UUID()
        duplicate.title += " Copy"
        duplicate.createdAt = Date()
        save(duplicate)
        return duplicate
    }

    static func rename(_ draft: LyricsDraft, to title: String) -> LyricsDraft {
        var renamed = draft
        renamed.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        save(renamed)
        return renamed
    }

    private static func persist(_ drafts: [LyricsDraft]) {
        guard let data = try? JSONEncoder().encode(drafts) else { return }
        UserDefaults.standard.set(data, forKey: draftsKey)
    }
}
