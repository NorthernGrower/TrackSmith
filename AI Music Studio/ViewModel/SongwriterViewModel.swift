//
//  SongwriterViewModel.swift
//  AI Music Studio
//

import Foundation
import SwiftUI

/// Drives the AI songwriter: writing lyric sheets and arranging them into a session.
@MainActor
final class SongwriterViewModel: ObservableObject {
    @Published private(set) var lyrics: LyricsDraft?
    @Published private(set) var isWritingLyrics = false
    @Published private(set) var isComposingSong = false
    @Published var errorMessage: String?
    @Published private(set) var sectionTake: (title: String, lines: [String])?
    private var lastSongRequest: SongRequest?
    private weak var mixerModel: MixerViewModel?
    private var hasCreatedArrangement = false

    init() {
        lyrics = LyricsDraftStorage.loadLast()
    }

    func rerollSection(_ title: String, genre: MusicGenre, topic: String) {
        guard let current = lyrics else { return }
        let lines = LyricComposer.rerollSection(title, genre: genre, topic: topic, seed: UInt64(Date().timeIntervalSince1970 * 1_000))
        guard !lines.isEmpty else { return }
        sectionTake = (title, lines)
        _ = current
    }

    func keepSectionTake() {
        guard let take = sectionTake, var draft = lyrics,
              let index = draft.sections.firstIndex(where: { $0.title == take.title }) else { return }
        draft.sections[index].lines = take.lines
        lyrics = draft
        LyricsDraftStorage.save(draft)
        sectionTake = nil
        guard hasCreatedArrangement, let request = lastSongRequest, let mixerModel else { return }
        let updated = SongComposer.compose(request: request, lyrics: draft)
        mixerModel.replaceGeneratedVocalSection(updated, sectionName: take.title)
    }

    func discardSectionTake() { sectionTake = nil }

    func loadLyrics(_ draft: LyricsDraft) {
        lyrics = draft
        LyricsDraftStorage.save(draft)
    }

    func writeLyrics(genre: MusicGenre, topic: String) {
        guard !isWritingLyrics else { return }
        isWritingLyrics = true
        let seed = UInt64(Date().timeIntervalSince1970 * 1_000)

        Task {
            try? await Task.sleep(for: .milliseconds(260))
            let draft = LyricComposer.compose(genre: genre, topic: topic, seed: seed)
            LyricsDraftStorage.save(draft)
            lyrics = draft
            isWritingLyrics = false
        }
    }

    func createSong(
        request: SongRequest,
        model: MixerViewModel,
        completion: @escaping () -> Void
    ) {
        guard !isComposingSong else { return }
        isComposingSong = true
        lastSongRequest = request
        mixerModel = model
        hasCreatedArrangement = false
        let draft = lyrics

        Task.detached(priority: .userInitiated) {
            let session = SongComposer.compose(request: request, lyrics: draft)
            await MainActor.run {
                model.createSession(fromGenerated: session)
                self.hasCreatedArrangement = true
                self.isComposingSong = false
                completion()
            }
        }
    }
}
