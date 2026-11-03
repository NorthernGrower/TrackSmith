//
//  HouseDemoSession.swift
//  AI Music Studio
//

import AVFoundation
import Foundation

enum HouseDemoSessionFactory {
    private struct DemoSample {
        let fileName: String
        let duration: TimeInterval
    }

    static func make() -> StudioSession {
        let tempo = 124
        let beat = 60.0 / Double(tempo)
        let bar = beat * 4
        let barCount = 8
        let bundled = SampleLibrary.scan().filter(\.isBundled)
        let kick = sample("starter-kick-1.wav", storedAs: "demo-house-kick.wav", from: bundled)
        let snare = sample("starter-snare.wav", storedAs: "demo-house-snare.wav", from: bundled)
        let clap = sample("starter-clap.wav", storedAs: "demo-house-clap.wav", from: bundled)
        let hat = sample("starter-hat.wav", storedAs: "demo-house-hat.wav", from: bundled)

        var kickClips: [AudioClip] = []
        var snareClips: [AudioClip] = []
        var hatClips: [AudioClip] = []
        for beatIndex in 0..<(barCount * 4) {
            let time = Double(beatIndex) * beat
            if let clip = makeClip(kick, name: "Kick", at: time, maximumDuration: beat * 0.9) {
                kickClips.append(clip)
            }
            if beatIndex % 4 == 1 || beatIndex % 4 == 3 {
                if let clip = makeClip(snare, name: "Snare", at: time, maximumDuration: beat * 0.9) {
                    snareClips.append(clip)
                }
                if let clip = makeClip(clap, name: "Clap", at: time, maximumDuration: beat * 0.7) {
                    snareClips.append(clip)
                }
            }
        }
        for eighthIndex in 0..<(barCount * 8) {
            let time = Double(eighthIndex) * beat / 2
            if let clip = makeClip(hat, name: "Closed Hat", at: time, maximumDuration: beat * 0.22) {
                hatClips.append(clip)
            }
        }

        var drums = Track(
            name: "Drums",
            fileName: kick?.fileName ?? "",
            volume: 0.92,
            clips: kickClips
        )
        drums.eqSettings.lowGain = 1.5
        drums.eqSettings.highGain = 1

        var percussion = Track(
            name: "Snare & Clap",
            fileName: snare?.fileName ?? clap?.fileName ?? "",
            volume: 0.76,
            clips: snareClips
        )
        percussion.pan = 0

        let hats = Track(
            name: "Hi-Hats",
            fileName: hat?.fileName ?? "",
            volume: 0.62,
            pan: 0.12,
            clips: hatClips
        )

        let bassRoots = [48, 53, 55, 50]
        var bassNotes: [SynthNote] = []
        for barIndex in 0..<barCount {
            let root = bassRoots[barIndex % bassRoots.count]
            for step in 0..<8 {
                let pitch = root + (step % 4 == 3 ? 12 : 0)
                bassNotes.append(SynthNote(
                    pitch: pitch,
                    startTime: Double(barIndex) * bar + Double(step) * beat / 2,
                    duration: beat * 0.42,
                    velocity: step == 0 || step == 4 ? 0.92 : 0.72
                ))
            }
        }
        var bass = Track(name: "Bass", fileName: "", volume: 0.78, notes: bassNotes)
        bass.eqSettings.lowGain = 2
        bass.eqSettings.highGain = -1
        bass.compressorSettings.isBypassed = false
        bass.compressorSettings.thresholdDB = -20
        bass.compressorSettings.ratio = 3

        let chordRoots = [57, 53, 48, 55]
        let chordIntervals = [[0, 3, 7], [0, 4, 7], [0, 4, 7], [0, 4, 7]]
        var chordNotes: [SynthNote] = []
        for barIndex in 0..<barCount {
            let root = chordRoots[barIndex % chordRoots.count]
            let intervals = chordIntervals[barIndex % chordIntervals.count]
            for step in [1, 3, 5, 7] {
                for interval in intervals {
                    chordNotes.append(SynthNote(
                        pitch: root + interval,
                        startTime: Double(barIndex) * bar + Double(step) * beat / 2,
                        duration: beat * 0.34,
                        velocity: 0.54
                    ))
                }
            }
        }
        let chords = Track(name: "Chords", fileName: "", volume: 0.58, pan: -0.12, notes: chordNotes)

        let melody = [69, 67, 64, 67, 71, 69, 67, 64]
        var leadNotes: [SynthNote] = []
        for barIndex in 0..<barCount {
            for step in 0..<4 {
                leadNotes.append(SynthNote(
                    pitch: melody[(barIndex * 4 + step) % melody.count],
                    startTime: Double(barIndex) * bar + Double(step) * beat + beat * 0.5,
                    duration: beat * 0.32,
                    velocity: step == 0 ? 0.72 : 0.5
                ))
            }
        }
        let lead = Track(name: "Lead", fileName: "", volume: 0.52, pan: 0.16, notes: leadNotes)

        var session = StudioSession(
            name: "Night Drive — House Demo",
            templateID: "house-demo",
            tracks: [drums, percussion, hats, bass, chords, lead],
            tempoBPM: tempo
        )
        session.masterEffects.isBypassed = false
        session.masterEffects.reverbMix = 0.12
        session.masterEffects.reverbDecay = 1.6
        session.masterEffects.delayMix = 0.1
        session.masterEffects.delayFeedback = 0.24
        session.sections = [
            SongSection(name: "Intro", time: 0),
            SongSection(name: "Build", time: bar * 2),
            SongSection(name: "Drop", time: bar * 4),
            SongSection(name: "Outro", time: bar * 7)
        ]
        for step in stride(from: 0, to: DrumPattern.stepCount, by: 4) {
            session.drumPattern.toggle(.kick, step: step)
        }
        for step in [4, 12] {
            session.drumPattern.toggle(.snare, step: step)
        }
        for step in stride(from: 2, to: DrumPattern.stepCount, by: 2) {
            session.drumPattern.toggle(.closedHat, step: step)
        }
        session.drumPattern.toggle(.openHat, step: 14)
        return session
    }

    private static func sample(
        _ bundledName: String,
        storedAs storedName: String,
        from items: [SampleLibraryItem]
    ) -> DemoSample? {
        guard let bundled = items.first(where: { $0.id == bundledName }) else { return nil }
        let destination = TrackStorage.url(forFileName: storedName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            do {
                try FileManager.default.copyItem(at: bundled.url, to: destination)
            } catch {
                return nil
            }
        }
        guard let file = try? AVAudioFile(forReading: destination),
              file.processingFormat.sampleRate > 0 else { return nil }
        return DemoSample(
            fileName: storedName,
            duration: TimeInterval(file.length) / file.processingFormat.sampleRate
        )
    }

    private static func makeClip(
        _ sample: DemoSample?,
        name: String,
        at start: TimeInterval,
        maximumDuration: TimeInterval
    ) -> AudioClip? {
        guard let sample else { return nil }
        return AudioClip(
            name: name,
            fileName: sample.fileName,
            startTime: start,
            duration: min(sample.duration, maximumDuration),
            sourceStartTime: 0,
            sourceDuration: sample.duration
        )
    }
}
