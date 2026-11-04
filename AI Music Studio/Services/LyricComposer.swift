//
//  LyricComposer.swift
//  AI Music Studio
//

import Foundation

/// A small deterministic random number generator so a lyric sheet can be
/// regenerated from the same seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Writes a full lyric sheet for a genre and topic entirely on device.
enum LyricComposer {

    static func compose(
        genre: MusicGenre,
        topic rawTopic: String,
        seed: UInt64
    ) -> LyricsDraft {
        var generator = SeededGenerator(seed: seed)
        let bank = genre.lyrics
        let topic = normalizedTopic(rawTopic) ?? bank.imagery

        let hook = fill(pick(bank.hooks, &generator) ?? "This is the sound of letting go", topic: topic)
        let hookTwo = fill(pick(bank.hooks, &generator) ?? hook, topic: topic)
        let openingLine = fill(pick(bank.openings, &generator) ?? hook, topic: topic)
        let bridgeOne = fill(pick(bank.bridges, &generator) ?? hookTwo, topic: topic)
        let bridgeTwo = fill(pick(bank.bridges, &generator) ?? hook, topic: topic)

        let verseOne = makeVerse(bank, opening: openingLine, topic: topic, generator: &generator)
        let verseTwo = makeVerse(bank, opening: nil, topic: topic, generator: &generator)
        let chorusOne = makeChorus(bank, hook: hook, secondHook: hookTwo, topic: topic, generator: &generator)
        let chorusTwo = makeChorus(bank, hook: hookTwo, secondHook: hook, topic: topic, generator: &generator)
        let bridge = makeBridge(
            bank,
            first: bridgeOne,
            second: bridgeTwo,
            topic: topic,
            generator: &generator
        )

        let sections = [
            LyricSection(title: "Verse 1", lines: verseOne),
            LyricSection(title: "Chorus", lines: chorusOne),
            LyricSection(title: "Verse 2", lines: verseTwo),
            LyricSection(title: "Chorus", lines: chorusTwo),
            LyricSection(title: "Bridge", lines: bridge),
            LyricSection(title: "Outro", lines: [hookTwo, "That's where the story lets us go"]),
        ]

        return LyricsDraft(
            title: title(from: hook),
            genreID: genre.rawValue,
            genreTitle: genre.title,
            topic: topic,
            sections: sections
        )
    }

    // MARK: - Sections

    private static func makeVerse(
        _ bank: GenreLyrics,
        opening: String?,
        topic: String,
        generator: inout SeededGenerator
    ) -> [String] {
        let first = pick(bank.couplets, &generator)
        let second = pick(bank.couplets, &generator)

        var lines: [String] = []
        if let opening {
            lines.append(opening)
        }
        if let first {
            lines.append(fill(first.0, topic: topic))
            lines.append(fill(first.1, topic: topic))
        }
        if let second {
            lines.append(fill(second.0, topic: topic))
            lines.append(fill(second.1, topic: topic))
        }
        return Array(lines.prefix(5))
    }

    private static func makeChorus(
        _ bank: GenreLyrics,
        hook: String,
        secondHook: String,
        topic: String,
        generator: inout SeededGenerator
    ) -> [String] {
        let pair = pick(bank.couplets, &generator)
        return [
            hook,
            fill(pair?.0 ?? "Hold on to the feeling", topic: topic),
            secondHook,
            fill(pair?.1 ?? "Let it carry us away", topic: topic),
        ]
    }

    private static func makeBridge(
        _ bank: GenreLyrics,
        first: String,
        second: String,
        topic: String,
        generator: inout SeededGenerator
    ) -> [String] {
        let pair = pick(bank.couplets, &generator)
        return [
            first,
            fill(pair?.1 ?? "Everything we needed shows up here", topic: topic),
            second,
        ]
    }

    // MARK: - Helpers

    private static func pick<T>(_ values: [T], _ generator: inout SeededGenerator) -> T? {
        guard !values.isEmpty else { return nil }
        return values.randomElement(using: &generator)
    }

    private static func fill(_ line: String, topic: String) -> String {
        line.replacingOccurrences(of: "{topic}", with: topic)
    }

    private static func normalizedTopic(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func title(from hook: String) -> String {
        var text = hook.trimmingCharacters(in: CharacterSet(charactersIn: " .,"))
        let prefixes = ["so ", "and ", "yeah, ", "we were ", "this is "]
        let lower = text.lowercased()
        for prefix in prefixes where lower.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = text.first else { return "Untitled Song" }
        return String(first).uppercased() + String(text.dropFirst())
    }
}
