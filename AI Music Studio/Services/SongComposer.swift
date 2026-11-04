//
//  SongComposer.swift
//  AI Music Studio
//

import Foundation

/// Everything the user picks before a song is generated.
struct SongRequest {
    var genre: MusicGenre
    var topic: String
    var vocal: VocalStyle
    var guitar: GuitarStyle
    var drumKit: DrumKit
    var tempo: Int
}

/// Builds a complete session — drums, bass, keys, guitar and Marlene's vocal —
/// from a genre preset and an optional lyric sheet.
enum SongComposer {
    static let barCount = 16

    private struct SectionPlan {
        let name: String
        let startBar: Int
        let barCount: Int
        let phrase: VocalPhrase?
    }

    private enum VocalPhrase {
        case verse
        case chorus
        case bridge

        var beats: [Double] {
            switch self {
            case .verse: return [0.0, 0.75, 1.5, 2.5, 3.0]
            case .chorus: return [0.0, 0.5, 1.25, 2.0, 2.5, 3.25]
            case .bridge: return [0.0, 1.0, 2.0]
            }
        }

        var noteBeats: Double {
            switch self {
            case .verse: return 0.55
            case .chorus: return 0.5
            case .bridge: return 0.8
            }
        }

        var contour: [Int] {
            switch self {
            case .verse: return [0, 2, 1, 2, 1, 0, 2, 1]
            case .chorus: return [2, 1, 2, 0, 1, 2, 1, 2]
            case .bridge: return [1, 2, 0, 2, 1, 0, 2, 1]
            }
        }
    }

    private static let plans: [SectionPlan] = [
        SectionPlan(name: "Intro", startBar: 0, barCount: 2, phrase: nil),
        SectionPlan(name: "Verse 1", startBar: 2, barCount: 4, phrase: .verse),
        SectionPlan(name: "Chorus", startBar: 6, barCount: 4, phrase: .chorus),
        SectionPlan(name: "Bridge", startBar: 10, barCount: 2, phrase: .bridge),
        SectionPlan(name: "Final Chorus", startBar: 12, barCount: 4, phrase: .chorus),
    ]

    static func compose(request: SongRequest, lyrics: LyricsDraft?) -> StudioSession {
        let tempo = min(190, max(70, request.tempo))
        let beat = 60.0 / Double(tempo)
        let barDuration = beat * 4
        let genre = request.genre
        let chords = genre.chords

        var tracks: [Track] = []

        if let groove = DrumGrooveRenderer.render(
            kit: request.drumKit,
            groove: genre.groove,
            bars: barCount,
            tempo: tempo,
            token: genre.rawValue
        ) {
            let clip = AudioClip(
                name: "\(request.drumKit.title) Groove",
                fileName: groove.fileName,
                startTime: 0,
                duration: groove.duration,
                sourceStartTime: 0,
                sourceDuration: groove.duration,
                isOriginal: true
            )
            var drums = Track(
                name: "Drums",
                fileName: groove.fileName,
                volume: 0.9,
                clips: [clip]
            )
            drums.eqSettings.lowGain = 1.5
            drums.eqSettings.highGain = 0.5
            tracks.append(drums)
        }

        // Bass follows the root of each bar's chord.
        var bassNotes: [SynthNote] = []
        let bassRhythm: [Double] = [0.0, 1.5, 2.0, 3.0]
        for barIndex in 0..<barCount {
            let chord = chords[barIndex % chords.count]
            let root = wrapped(36 + chord.rootOffset, into: 33...45)
            for (index, position) in bassRhythm.enumerated() {
                let pitch = index == 2 ? wrapped(root + 7, into: 33...50) : root
                bassNotes.append(SynthNote(
                    pitch: pitch,
                    startTime: Double(barIndex) * barDuration + position * beat,
                    duration: beat * 0.42,
                    velocity: index == 0 ? 0.88 : 0.68
                ))
            }
        }
        var bass = Track(name: "Bass", fileName: "", volume: 0.78, notes: bassNotes)
        bass.voice = genre.bassVoice
        bass.eqSettings.lowGain = 2
        bass.eqSettings.highGain = -1
        bass.compressorSettings.isBypassed = false
        bass.compressorSettings.thresholdDB = -20
        bass.compressorSettings.ratio = 3
        tracks.append(bass)

        // Keys hold each bar's chord under the arrangement.
        if let keysVoice = genre.keysVoice {
            var keysNotes: [SynthNote] = []
            for barIndex in 0..<barCount {
                let chord = chords[barIndex % chords.count]
                for interval in chord.intervals {
                    keysNotes.append(SynthNote(
                        pitch: wrapped(60 + chord.rootOffset + interval, into: 60...76),
                        startTime: Double(barIndex) * barDuration,
                        duration: beat * 3.4,
                        velocity: 0.45
                    ))
                }
            }
            var keys = Track(name: "Keys", fileName: "", volume: 0.5, pan: -0.1, notes: keysNotes)
            keys.voice = keysVoice
            tracks.append(keys)
        }

        // Guitar strums the same chords with the chosen guitar voice.
        if let guitarVoice = request.guitar.voice {
            var guitarNotes: [SynthNote] = []
            let strums: [Double] = genre == .rock || genre == .country ? [0.0, 2.0, 3.5] : [0.0, 2.0]
            for barIndex in 0..<barCount {
                let chord = chords[barIndex % chords.count]
                for position in strums {
                    for (stringIndex, interval) in chord.intervals.prefix(3).enumerated() {
                        guitarNotes.append(SynthNote(
                            pitch: wrapped(52 + chord.rootOffset + interval, into: 52...67),
                            startTime: Double(barIndex) * barDuration + position * beat + Double(stringIndex) * 0.012,
                            duration: beat * 0.85,
                            velocity: Float(0.62 - Double(stringIndex) * 0.06)
                        ))
                    }
                }
            }
            var guitar = Track(
                name: request.guitar.trackName,
                fileName: "",
                volume: 0.56,
                pan: 0.14,
                notes: guitarNotes
            )
            guitar.voice = guitarVoice
            tracks.append(guitar)
        }

        // Marlene sings a phrase per vocal section, with an optional harmony.
        if request.vocal.includesVocal {
            let harmonyCount = request.vocal.harmonyCount
            var leadNotes: [SynthNote] = []
            var harmonyNotes: [SynthNote] = []

            for plan in plans {
                guard let phrase = plan.phrase else { continue }
                for barOffset in 0..<plan.barCount {
                    let barIndex = plan.startBar + barOffset
                    let chord = chords[barIndex % chords.count]
                    let barStart = Double(barIndex) * barDuration
                    for (stepIndex, position) in phrase.beats.enumerated() {
                        let contour = phrase.contour
                        let intervalIndex = contour[(barOffset * phrase.beats.count + stepIndex) % contour.count]
                        let interval = chord.intervals[min(intervalIndex, chord.intervals.count - 1)]
                        let pitch = wrapped(64 + chord.rootOffset + interval, into: 62...79)
                        let start = barStart + position * beat

                        leadNotes.append(SynthNote(
                            pitch: pitch,
                            startTime: start,
                            duration: beat * phrase.noteBeats,
                            velocity: stepIndex == 0 ? 0.82 : 0.68
                        ))

                        if harmonyCount > 1 {
                            harmonyNotes.append(SynthNote(
                                pitch: wrapped(pitch + 4, into: 62...81),
                                startTime: start,
                                duration: beat * phrase.noteBeats,
                                velocity: 0.4
                            ))
                        }
                    }
                }
            }

            var vocal = Track(
                name: "Marlene (Lead)",
                fileName: "",
                volume: 0.82,
                pan: 0.02,
                notes: leadNotes
            )
            vocal.voice = .marleneVocal
            var vocalEQ = vocal.eqSettings
            vocalEQ.lowGain = -2
            vocalEQ.midGain = 1.5
            vocal.eqSettings = vocalEQ
            vocal.compressorSettings.isBypassed = false
            vocal.compressorSettings.thresholdDB = -22
            vocal.compressorSettings.ratio = 3.5
            tracks.append(vocal)

            if harmonyCount > 1 {
                var harmony = Track(
                    name: "Marlene (Harmony)",
                    fileName: "",
                    volume: 0.5,
                    pan: -0.18,
                    notes: harmonyNotes
                )
                harmony.voice = .marleneVocal
                tracks.append(harmony)
            }
        }

        let title = lyrics?.title
            ?? request.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionTitle = "\(title.isEmpty ? genre.title : title) — \(genre.title)"

        var session = StudioSession(
            name: sessionTitle,
            templateID: "ai-\(genre.rawValue)",
            tracks: tracks,
            tempoBPM: tempo
        )

        session.drumKit = request.drumKit
        session.masterEffects.isBypassed = false
        session.masterEffects.reverbMix = genre == .rnb || genre == .electronic ? 0.2 : 0.12
        session.masterEffects.reverbDecay = 1.8
        session.masterEffects.delayMix = genre == .electronic ? 0.14 : 0.07
        session.masterEffects.delayFeedback = 0.22
        session.sections = plans.map { plan in
            SongSection(name: plan.name, time: Double(plan.startBar) * barDuration)
        }

        applyGroove(genre.groove, to: &session)
        return session
    }

    // MARK: - Helpers

    private static func wrapped(_ pitch: Int, into range: ClosedRange<Int>) -> Int {
        var value = pitch
        while value > range.upperBound { value -= 12 }
        while value < range.lowerBound { value += 12 }
        return value
    }

    private static func applyGroove(_ groove: GenreGroove, to session: inout StudioSession) {
        for step in groove.kick where (0..<DrumPattern.stepCount).contains(step) {
            session.drumPattern.toggle(.kick, step: step)
        }
        for step in groove.snare where (0..<DrumPattern.stepCount).contains(step) {
            session.drumPattern.toggle(.snare, step: step)
        }
        for step in groove.closedHat where (0..<DrumPattern.stepCount).contains(step) {
            session.drumPattern.toggle(.closedHat, step: step)
        }
        for step in groove.openHat where (0..<DrumPattern.stepCount).contains(step) {
            session.drumPattern.toggle(.openHat, step: step)
        }
        for step in groove.clap where (0..<DrumPattern.stepCount).contains(step) {
            session.drumPattern.toggle(.clap, step: step)
        }
    }
}
