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

    init() {
        lyrics = LyricsDraftStorage.loadLast()
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
        let draft = lyrics

        Task.detached(priority: .userInitiated) {
            let session = SongComposer.compose(request: request, lyrics: draft)
            await MainActor.run {
                model.createSession(fromGenerated: session)
                self.isComposingSong = false
                completion()
            }
        }
    }
}
