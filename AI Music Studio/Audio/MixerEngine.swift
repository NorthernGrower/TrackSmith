//
//  MixerEngine.swift
//  AI Music Studio
//

import AVFoundation
import Foundation

/// Thread-safe store for per-track audio levels written from the render thread.
final class LevelStore: @unchecked Sendable {
    private let lock = NSLock()
    private var levels: [UUID: Float] = [:]

    func ingest(id: UUID, buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else {
            levels[id] = 0
            return
        }

        let frameCount = Int(buffer.frameLength)
        var sumSquares: Float = 0
        var sampleCount = 0

        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channelData[channel]
            for i in stride(from: 0, to: frameCount, by: 4) {
                let sample = samples[i]
                sumSquares += sample * sample
                sampleCount += 1
            }
        }

        let rms = sqrt(sumSquares / Float(max(1, sampleCount)))
        levels[id] = min(1, rms * 3)
    }

    func level(for id: UUID) -> Float {
        lock.lock()
        defer { lock.unlock() }
        return levels[id] ?? 0
    }
}

/// Plays every track of the session in sync through a single audio engine.
/// Mute, solo and volume changes apply instantly because they only change player gains.
@MainActor
final class MixerEngine {
    private let engine = AVAudioEngine()
    private let levelStore = LevelStore()
    private struct ClipPlayback {
        let clip: AudioClip
        let file: AVAudioFile
        let player: AVAudioPlayerNode
    }

    private var trackMixers: [UUID: AVAudioMixerNode] = [:]
    private var instrumentMixers: [UUID: AVAudioMixerNode] = [:]
    private var equalizers: [UUID: AVAudioUnitEQ] = [:]
    private var compressors: [UUID: AVAudioUnitEffect] = [:]
    private var clipPlayers: [UUID: [ClipPlayback]] = [:]
    private var clipSignatures: [UUID: [AudioClip]] = [:]
    private var instrumentVoices: [UUID: [AVAudioPlayerNode]] = [:]
    private var instrumentFormats: [UUID: AVAudioFormat] = [:]
    private var voiceCursors: [UUID: Int] = [:]
    private var previewVoices: [AVAudioPlayerNode] = []
    private var previewFormat: AVAudioFormat?
    private var previewVoiceCursor = 0
    private var scheduledInstrumentFiles: [ObjectIdentifier: AVAudioFile] = [:]
    private var notePlayers: [UUID: [AVAudioPlayerNode]] = [:]
    private var notePlayerBusy: [UUID: [TimeInterval]] = [:]
    private var noteBufferCache: [String: AVAudioPCMBuffer] = [:]
    private let noteVoiceCount = 6
    private var metronomeMixer: AVAudioMixerNode?
    private var metronomeVoices: [AVAudioPlayerNode] = []
    private var metronomeFormat: AVAudioFormat?
    private var metronomeBuffers: [String: AVAudioPCMBuffer] = [:]
    private var metronomeEnabled = false
    private var metronomeVolume: Float = 0.7
    private var songTempoBPM = 120
    private let metronomeVoiceCount = 4
    private let masterBus = AVAudioMixerNode()
    private let masterReverb = AVAudioUnitReverb()
    private let masterDelay = AVAudioUnitDelay()
    private var masterEffectsSettings = MasterEffectsSettings()
    private var mixTracks: [Track] = []
    private var automationTime: TimeInterval = 0
    private var activeLoop: ClosedRange<TimeInterval>?
    private var playbackHostStart: UInt64 = 0
    private var loopScheduleDelay: TimeInterval = 0.04
    private var nextLoopPass = 0
    private var scheduledUntilOffset: TimeInterval = 0
    private var takeRecorder: InstrumentTakeRecorder?
    private var takeTrackID: UUID?
    private var takeURL: URL?
    private var takeUsesMicrophone = false
    private let instrumentVoiceCount = 8
    private var trackIDs: [UUID] = []

    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    /// Why playback last failed to start, if it did.
    private(set) var lastStartError: String?
    private var playHeadOffset: TimeInterval = 0
    private var playStartDate: Date?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        buildMasterEffectsGraph()
        buildMetronomeGraph()
    }

    /// The format the hardware is actually running at, falling back to 44.1 kHz stereo.
    private func masterConnectionFormat() -> AVAudioFormat? {
        let output = engine.outputNode.outputFormat(forBus: 0)
        if output.sampleRate > 0, output.channelCount > 0 {
            return AVAudioFormat(
                standardFormatWithSampleRate: output.sampleRate,
                channels: min(max(output.channelCount, 1), 2)
            )
        }
        return AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
    }

    /// Connects the master reverb and delay once, between the tracks and the output.
    private func buildMasterEffectsGraph() {
        guard let format = masterConnectionFormat() else { return }

        engine.attach(masterBus)
        engine.attach(masterReverb)
        engine.attach(masterDelay)
        engine.connect(masterBus, to: masterReverb, format: format)
        engine.connect(masterReverb, to: masterDelay, format: format)
        engine.connect(masterDelay, to: engine.mainMixerNode, format: format)
        applyMasterEffects()
    }

    /// Applies the master reverb and delay settings.
    func updateMasterEffects(_ settings: MasterEffectsSettings, tempoBPM: Int) {
        masterEffectsSettings = settings
        songTempoBPM = min(200, max(60, tempoBPM))
        applyMasterEffects()
    }

    private func applyMasterEffects() {
        let settings = masterEffectsSettings
        let bypassed = settings.isBypassed

        masterReverb.loadFactoryPreset(reverbPreset(for: settings.reverbDecay))
        masterReverb.wetDryMix = bypassed ? 0 : Float(min(1, max(0, settings.reverbMix)) * 100)

        masterDelay.delayTime = settings.delaySeconds(tempoBPM: songTempoBPM)
        masterDelay.feedback = bypassed ? 0 : Float(min(0.9, max(0, settings.delayFeedback)) * 100)
        masterDelay.wetDryMix = bypassed ? 0 : Float(min(1, max(0, settings.delayMix)) * 100)
    }

    private func reverbPreset(for decay: Double) -> AVAudioUnitReverbPreset {
        switch decay {
        case ..<0.6: return .smallRoom
        case ..<1.2: return .mediumRoom
        case ..<2.0: return .largeRoom
        case ..<2.8: return .mediumHall
        case ..<3.8: return .largeHall
        default: return .cathedral
        }
    }

    /// Connects the click track once, so it never needs building during playback.
    private func buildMetronomeGraph() {
        guard let clickFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) else {
            return
        }

        let connectionFormat = masterConnectionFormat() ?? clickFormat

        let mixer = AVAudioMixerNode()
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: connectionFormat)
        mixer.outputVolume = metronomeVolume

        for _ in 0..<metronomeVoiceCount {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: mixer, format: clickFormat)
            metronomeVoices.append(voice)
        }

        metronomeMixer = mixer
        metronomeFormat = clickFormat
    }

    /// Rebuilds the playback graph for tracks and their audio clips.
    func load(tracks: [Track]) {
        let newClipSignatures = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0.playbackClips) })
        guard tracks.map(\.id) != trackIDs || newClipSignatures != clipSignatures else {
            updateMix(tracks: tracks)
            ensurePreviewVoices()
            return
        }

        if isPlaying { pause() }
        detachAll()

        trackIDs = tracks.map(\.id)
        clipSignatures = newClipSignatures
        duration = 0

        for track in tracks {
            let clipFiles: [(clip: AudioClip, file: AVAudioFile)] = track.playbackClips.compactMap { clip in
                let url = TrackStorage.url(forFileName: clip.fileName)
                guard let file = try? AVAudioFile(forReading: url) else { return nil }
                return (clip, file)
            }

            let referenceFile: AVAudioFile
            if let firstClip = clipFiles.first {
                referenceFile = firstClip.file
            } else {
                let legacyURL = TrackStorage.url(forFileName: track.fileName)
                guard let file = try? AVAudioFile(forReading: legacyURL) else { continue }
                referenceFile = file
            }

            let format = referenceFile.processingFormat
            let instrumentFormat = AVAudioFormat(
                standardFormatWithSampleRate: format.sampleRate,
                channels: min(format.channelCount, 2)
            ) ?? format
            let mixer = AVAudioMixerNode()
            let instrumentMixer = AVAudioMixerNode()
            let equalizer = AVAudioUnitEQ(numberOfBands: 3)
            let compressor = TrackCompressorUnit.make()

            engine.attach(mixer)
            engine.attach(instrumentMixer)
            engine.attach(equalizer)
            engine.attach(compressor)
            engine.connect(instrumentMixer, to: mixer, format: instrumentFormat)
            engine.connect(mixer, to: equalizer, format: format)
            engine.connect(equalizer, to: compressor, format: format)
            engine.connect(compressor, to: masterBus, format: format)

            let store = levelStore
            let trackID = track.id
            mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                store.ingest(id: trackID, buffer: buffer)
            }

            var voices: [AVAudioPlayerNode] = []
            for _ in 0..<instrumentVoiceCount {
                let voice = AVAudioPlayerNode()
                engine.attach(voice)
                engine.connect(voice, to: instrumentMixer, format: instrumentFormat)
                voices.append(voice)
            }

            var sequencingVoices: [AVAudioPlayerNode] = []
            for _ in 0..<noteVoiceCount {
                let notePlayer = AVAudioPlayerNode()
                engine.attach(notePlayer)
                engine.connect(notePlayer, to: instrumentMixer, format: instrumentFormat)
                sequencingVoices.append(notePlayer)
            }

            var loadedClips: [ClipPlayback] = []
            for (clip, clipFile) in clipFiles {
                let clipPlayer = AVAudioPlayerNode()
                engine.attach(clipPlayer)
                engine.connect(clipPlayer, to: mixer, format: clipFile.processingFormat)
                loadedClips.append(ClipPlayback(clip: clip, file: clipFile, player: clipPlayer))
                duration = max(duration, clip.startTime + clip.duration)
            }

            trackMixers[track.id] = mixer
            instrumentMixers[track.id] = instrumentMixer
            equalizers[track.id] = equalizer
            compressors[track.id] = compressor
            clipPlayers[track.id] = loadedClips
            instrumentVoices[track.id] = voices
            notePlayers[track.id] = sequencingVoices
            instrumentFormats[track.id] = instrumentFormat
            var eqSettings = track.eqSettings
            var compressorSettings = track.compressorSettings
            if track.isFrozen {
                eqSettings.isBypassed = true
                compressorSettings.isBypassed = true
            }
            configureEqualizer(equalizer, settings: eqSettings)
            TrackCompressorUnit.configure(compressor, settings: compressorSettings)
        }

        updateMix(tracks: tracks)
        ensurePreviewVoices()
    }

    func updateMix(tracks: [Track]) {
        mixTracks = tracks
        let clipEnd = tracks.flatMap { track in
            track.playbackClips.map { clip in
                max(0, clip.startTime) + min(clip.duration, max(0, clip.sourceDuration - clip.sourceStartTime))
            }
        }.max() ?? 0
        let noteEnd = tracks.flatMap { $0.sequencedNotes.map(\.endTime) }.max() ?? 0
        duration = max(clipEnd, noteEnd)
        applyMix()
    }

    func updateAutomation(at time: TimeInterval) {
        automationTime = max(0, time)
        applyMix()
    }

    private func applyMix() {
        let anySolo = mixTracks.contains { $0.isSoloed }
        for track in mixTracks {
            let audible = !track.isMuted && (!anySolo || track.isSoloed)
            let automatedVolume = track.volume * track.automationGain(at: automationTime)
            trackMixers[track.id]?.outputVolume = audible ? automatedVolume : 0
            let automatedPan = track.panAutomationPoints.isEmpty
                ? track.pan
                : track.panAutomationValue(at: automationTime)
            trackMixers[track.id]?.pan = min(1, max(-1, automatedPan))
        }
    }

    /// Sets the overall output level of the studio.
    func setMasterVolume(_ volume: Float) {
        let clamped = min(1, max(0, volume))
        if engine.mainMixerNode.outputVolume != clamped {
            engine.mainMixerNode.outputVolume = clamped
        }
    }

    func setTempo(_ bpm: Int) {
        songTempoBPM = min(200, max(60, bpm))
        applyMasterEffects()
    }

    /// Turns the click track on or off and sets its level.
    func setMetronome(enabled: Bool, level: Float) {
        metronomeVolume = min(1, max(0, level))
        metronomeMixer?.outputVolume = metronomeVolume

        guard enabled != metronomeEnabled else { return }
        metronomeEnabled = enabled

        if enabled, isPlaying {
            seek(to: currentTime)
        } else if !enabled {
            metronomeVoices.forEach { $0.stop() }
        }
    }

    /// Plays a bar of count-in clicks and returns how long they last.
    func playCountIn(beats: Int) -> TimeInterval? {
        guard beats > 0, let format = ensureMetronomeGraph() else { return nil }
        let beatDuration = 60.0 / Double(max(60, songTempoBPM))
        let startUptime = ProcessInfo.processInfo.systemUptime + 0.1

        guard startAudioEngine() else { return nil }
        metronomeMixer?.outputVolume = metronomeVolume
        metronomeVoices.forEach { $0.stop() }

        for index in 0..<beats {
            guard let buffer = metronomeClickBuffer(accented: index == 0, format: format) else { continue }
            let voice = metronomeVoices[index % metronomeVoices.count]
            let hostTime = AVAudioTime.hostTime(forSeconds: startUptime + Double(index) * beatDuration)
            voice.scheduleBuffer(buffer, at: AVAudioTime(hostTime: hostTime), options: [])
        }
        metronomeVoices.forEach { $0.play() }

        return Double(beats) * beatDuration
    }

    /// Stops any clicks that are still queued.
    func silenceMetronome() {
        metronomeVoices.forEach { $0.stop() }
    }

    private func ensureMetronomeGraph() -> AVAudioFormat? {
        metronomeFormat
    }

    private func metronomeClickBuffer(accented: Bool, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let key = "\(accented)-\(Int(format.sampleRate))-\(format.channelCount)"
        if let cached = metronomeBuffers[key] { return cached }

        guard let base = InstrumentSoundGenerator.drumHit(.closedHat, format: format),
              let channels = base.floatChannelData else { return nil }

        let gain: Float = accented ? 1.0 : 0.45
        for channel in 0..<Int(format.channelCount) {
            let samples = channels[channel]
            for frame in 0..<Int(base.frameLength) {
                samples[frame] *= gain
            }
        }

        metronomeBuffers[key] = base
        return base
    }

    /// Schedules a click on every beat inside a timeline window.
    private func scheduleMetronome(from start: TimeInterval, to end: TimeInterval, timeOffset: TimeInterval) {
        guard let format = metronomeFormat, !metronomeVoices.isEmpty, end > start else { return }
        let beatDuration = 60.0 / Double(max(60, songTempoBPM))
        var beatIndex = Int(ceil(max(0, start) / beatDuration))
        var voiceIndex = 0

        while true {
            let beatTime = Double(beatIndex) * beatDuration
            if beatTime >= end { break }
            guard let buffer = metronomeClickBuffer(accented: beatIndex % 4 == 0, format: format) else { break }

            let seconds = loopScheduleDelay + timeOffset + (beatTime - start)
            let hostTime = playbackHostStart + AVAudioTime.hostTime(forSeconds: seconds)
            let voice = metronomeVoices[voiceIndex % metronomeVoices.count]
            voice.scheduleBuffer(buffer, at: AVAudioTime(hostTime: hostTime), options: [])
            voiceIndex += 1
            beatIndex += 1
        }
    }

    func updateEqualizer(trackID: UUID, settings: TrackEQSettings) {
        guard let equalizer = equalizers[trackID] else { return }
        var settings = settings
        if mixTracks.first(where: { $0.id == trackID })?.isFrozen == true {
            settings.isBypassed = true
        }
        configureEqualizer(equalizer, settings: settings)
    }

    func updateCompressor(trackID: UUID, settings: TrackCompressorSettings) {
        guard let compressor = compressors[trackID] else { return }
        var settings = settings
        if mixTracks.first(where: { $0.id == trackID })?.isFrozen == true {
            settings.isBypassed = true
        }
        TrackCompressorUnit.configure(compressor, settings: settings)
    }

    private func configureEqualizer(_ equalizer: AVAudioUnitEQ, settings: TrackEQSettings) {
        guard equalizer.bands.count >= 3 else { return }
        let low = equalizer.bands[0]
        low.filterType = .lowShelf
        low.frequency = Float(settings.lowFrequency)
        low.gain = Float(settings.lowGain)
        low.bypass = settings.isBypassed

        let mid = equalizer.bands[1]
        mid.filterType = .parametric
        mid.frequency = Float(settings.midFrequency)
        mid.bandwidth = 1
        mid.gain = Float(settings.midGain)
        mid.bypass = settings.isBypassed

        let high = equalizer.bands[2]
        high.filterType = .highShelf
        high.frequency = Float(settings.highFrequency)
        high.gain = Float(settings.highGain)
        high.bypass = settings.isBypassed
    }

    /// Sets or clears the section that repeats during playback.
    func setLoopRange(_ range: ClosedRange<TimeInterval>?) {
        let trimmed = range.flatMap { candidate -> ClosedRange<TimeInterval>? in
            candidate.upperBound - candidate.lowerBound > 0.05 ? candidate : nil
        }
        guard trimmed != activeLoop else { return }

        let position = currentTime
        activeLoop = trimmed

        guard isPlaying else { return }
        seek(to: position)
    }

    /// Keeps the next loop passes scheduled while playback continues.
    func ensureLoopScheduling() {
        guard isPlaying, activeLoop != nil else { return }
        scheduleLoopPasses(ahead: 30)
    }

    func play() {
        guard !trackIDs.isEmpty else { return }
        if metronomeEnabled {
            _ = ensureMetronomeGraph()
        }
        guard startAudioEngine() else { return }

        let loop = activeLoop
        if let loop,
           playHeadOffset < loop.lowerBound || playHeadOffset >= loop.upperBound {
            playHeadOffset = loop.lowerBound
        }
        updateAutomation(at: playHeadOffset)

        let scheduleDelay = 0.04
        let hostStart = AVAudioTime.hostTime(forSeconds: ProcessInfo.processInfo.systemUptime + scheduleDelay)
        let playbackStart = AVAudioTime(hostTime: hostStart)
        isPlaying = true
        playStartDate = Date().addingTimeInterval(scheduleDelay)
        playbackHostStart = hostStart
        loopScheduleDelay = scheduleDelay
        nextLoopPass = 0
        scheduledUntilOffset = 0

        for id in trackIDs {
            for loadedClip in clipPlayers[id] ?? [] {
                loadedClip.player.stop()
            }
        }
        for players in notePlayers.values {
            for player in players {
                player.stop()
            }
        }
        notePlayerBusy.removeAll()
        metronomeVoices.forEach { $0.stop() }

        if loop != nil {
            scheduleLoopPasses(ahead: 30)
        } else {
            scheduleWindow(from: playHeadOffset, to: max(duration, playHeadOffset), timeOffset: 0)
        }

        for id in trackIDs {
            for loadedClip in clipPlayers[id] ?? [] {
                loadedClip.player.play(at: playbackStart)
            }
        }
        for players in notePlayers.values {
            for player in players {
                player.play(at: playbackStart)
            }
        }
        for voice in metronomeVoices {
            voice.play(at: playbackStart)
        }
    }

    /// Schedules as many loop passes as needed to cover the coming seconds.
    private func scheduleLoopPasses(ahead: TimeInterval) {
        guard let loop = activeLoop else { return }
        let length = max(0.05, loop.upperBound - loop.lowerBound)
        let elapsed = playStartDate.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        let target = elapsed + ahead
        var scheduled = 0

        while scheduledUntilOffset < target, scheduled < 500 {
            let passStart = nextLoopPass == 0 ? playHeadOffset : loop.lowerBound
            let passOffset = nextLoopPass == 0
                ? 0
                : (loop.upperBound - playHeadOffset) + Double(nextLoopPass - 1) * length

            if loop.upperBound > passStart {
                scheduleWindow(from: passStart, to: loop.upperBound, timeOffset: passOffset)
                scheduledUntilOffset = passOffset + (loop.upperBound - passStart)
            }

            nextLoopPass += 1
            scheduled += 1
        }
    }

    /// Schedules every clip portion inside a timeline window at a host offset.
    private func scheduleWindow(from start: TimeInterval, to end: TimeInterval, timeOffset: TimeInterval) {
        guard end > start else { return }

        if metronomeEnabled {
            scheduleMetronome(from: start, to: end, timeOffset: timeOffset)
        }

        for id in trackIDs {
            for loadedClip in clipPlayers[id] ?? [] {
                let clip = loadedClip.clip
                let playableDuration = min(
                    clip.duration,
                    max(0, clip.sourceDuration - clip.sourceStartTime)
                )
                guard playableDuration > 0 else { continue }

                let clipStart = max(0, clip.startTime)
                let clipEnd = clipStart + playableDuration
                let overlapStart = max(start, clipStart)
                let overlapEnd = min(end, clipEnd)
                guard overlapEnd > overlapStart else { continue }

                let seconds = loopScheduleDelay + timeOffset + (overlapStart - start)
                scheduleClipSegment(
                    loadedClip,
                    offset: overlapStart - clipStart,
                    duration: overlapEnd - overlapStart,
                    at: seconds
                )
            }

            if let track = mixTracks.first(where: { $0.id == id }), !track.sequencedNotes.isEmpty {
                scheduleSynthNotes(
                    track.sequencedNotes,
                    trackID: id,
                    start: start,
                    end: end,
                    timeOffset: timeOffset
                )
            }
        }
    }

    /// Schedules the track's piano-roll notes that start inside a timeline window.
    private func scheduleSynthNotes(
        _ notes: [SynthNote],
        trackID: UUID,
        start: TimeInterval,
        end: TimeInterval,
        timeOffset: TimeInterval
    ) {
        guard let players = notePlayers[trackID], !players.isEmpty,
              let format = instrumentFormats[trackID] else { return }

        var busy = notePlayerBusy[trackID] ?? Array(repeating: 0, count: players.count)
        if busy.count != players.count {
            busy = Array(repeating: 0, count: players.count)
        }

        for note in notes where note.startTime >= start && note.startTime < end {
            guard let buffer = noteBuffer(for: note, trackID: trackID, format: format) else { continue }

            let index = busy.firstIndex(where: { $0 <= note.startTime })
                ?? busy.indices.min(by: { busy[$0] < busy[$1] }) ?? 0
            busy[index] = note.endTime

            let seconds = loopScheduleDelay + timeOffset + (note.startTime - start)
            let hostTime = playbackHostStart + AVAudioTime.hostTime(forSeconds: seconds)
            players[index].scheduleBuffer(buffer, at: AVAudioTime(hostTime: hostTime), options: [])
        }

        notePlayerBusy[trackID] = busy
    }

    /// Builds (and caches) the synth audio for one piano-roll note.
    private func noteBuffer(for note: SynthNote, trackID: UUID, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let key = "\(trackID.uuidString)-\(note.pitch)-\(Int(note.duration * 1000))"
        if let cached = noteBufferCache[key] { return cached }

        guard let buffer = InstrumentSoundGenerator.synthNote(
            frequency: SynthNote.frequency(for: note.pitch),
            waveform: SynthNoteVoice.waveform,
            cutoff: SynthNoteVoice.cutoff,
            attack: SynthNoteVoice.attack,
            release: SynthNoteVoice.release,
            duration: note.duration + SynthNoteVoice.release,
            format: format
        ) else { return nil }

        if noteBufferCache.count > 120 {
            noteBufferCache.removeAll()
        }
        noteBufferCache[key] = buffer
        return buffer
    }

    private func scheduleClipSegment(
        _ loadedClip: ClipPlayback,
        offset: TimeInterval,
        duration: TimeInterval,
        at seconds: TimeInterval
    ) {
        let sampleRate = loadedClip.file.processingFormat.sampleRate
        guard sampleRate > 0 else { return }

        let startFrame = AVAudioFramePosition((loadedClip.clip.sourceStartTime + offset) * sampleRate)
        let availableFrames = loadedClip.file.length - startFrame
        let requestedFrames = AVAudioFramePosition(max(0, duration) * sampleRate)
        let frames = min(availableFrames, requestedFrames)
        guard startFrame >= 0, frames > 0 else { return }

        let hostTime = playbackHostStart + AVAudioTime.hostTime(forSeconds: seconds)
        loadedClip.player.scheduleSegment(
            loadedClip.file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(min(frames, Int64(UInt32.max))),
            at: AVAudioTime(hostTime: hostTime)
        )
    }

    func pause() {
        guard isPlaying else { return }
        playHeadOffset = currentTime
        updateAutomation(at: playHeadOffset)
        clipPlayers.values.flatMap { $0 }.forEach { $0.player.pause() }
        notePlayers.values.flatMap { $0 }.forEach { $0.pause() }
        metronomeVoices.forEach { $0.pause() }
        isPlaying = false
        playStartDate = nil
    }

    func stop() {
        pause()
        playHeadOffset = 0
        updateAutomation(at: playHeadOffset)
        clipPlayers.values.flatMap { $0 }.forEach { $0.player.stop() }
        notePlayers.values.flatMap { $0 }.forEach { $0.stop() }
        notePlayerBusy.removeAll()
        metronomeVoices.forEach { $0.stop() }
        instrumentVoices.values.flatMap { $0 }.forEach { $0.stop() }
        previewVoices.forEach { $0.stop() }
    }

    /// Moves the playhead to a time; keeps playing if currently playing.
    func seek(to time: TimeInterval) {
        let wasPlaying = isPlaying
        if wasPlaying {
            pause()
        }
        playHeadOffset = min(max(0, time), duration)
        updateAutomation(at: playHeadOffset)
        clipPlayers.values.flatMap { $0 }.forEach { $0.player.stop() }
        notePlayers.values.flatMap { $0 }.forEach { $0.stop() }
        notePlayerBusy.removeAll()
        metronomeVoices.forEach { $0.stop() }
        if wasPlaying {
            play()
        }
    }

    var currentTime: TimeInterval {
        guard isPlaying, let start = playStartDate else { return playHeadOffset }
        let elapsed = max(0, Date().timeIntervalSince(start))
        let linear = playHeadOffset + elapsed

        if let loop = activeLoop {
            let length = loop.upperBound - loop.lowerBound
            if length > 0, linear >= loop.upperBound {
                let overflow = (linear - loop.upperBound).truncatingRemainder(dividingBy: length)
                return min(loop.upperBound, loop.lowerBound + overflow)
            }
            return min(loop.upperBound, linear)
        }

        return duration > 0 ? min(duration, linear) : linear
    }

    func level(for id: UUID) -> Float {
        levelStore.level(for: id)
    }

    func instrumentFormat(for destinationTrackID: UUID?) -> AVAudioFormat? {
        if let destinationTrackID, let format = instrumentFormats[destinationTrackID] {
            return format
        }
        ensurePreviewFormat()
        return previewFormat
    }

    func playInstrumentBuffer(
        _ buffer: AVAudioPCMBuffer,
        destinationTrackID: UUID?,
        monophonic: Bool = false
    ) {
        let group = voices(for: destinationTrackID)
        guard !group.players.isEmpty, startAudioEngine() else { return }
        let index = monophonic ? 0 : nextVoiceIndex(for: group.trackID, count: group.players.count)
        let player = group.players[index]
        player.stop()
        scheduledInstrumentFiles.removeValue(forKey: ObjectIdentifier(player))
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()
    }

    func playInstrumentFile(at url: URL, destinationTrackID: UUID?) {
        guard let file = try? AVAudioFile(forReading: url) else { return }
        let group = voices(for: destinationTrackID)
        guard !group.players.isEmpty, startAudioEngine() else { return }
        let index = nextVoiceIndex(for: group.trackID, count: group.players.count)
        let player = group.players[index]
        player.stop()
        player.scheduleFile(file, at: nil)
        scheduledInstrumentFiles[ObjectIdentifier(player)] = file
        player.play()
    }

    /// Stops any sound preview playing on the master output.
    func stopPreviews() {
        for voice in previewVoices {
            voice.stop()
            scheduledInstrumentFiles.removeValue(forKey: ObjectIdentifier(voice))
        }
    }

    func startInstrumentRecording(trackID: UUID, outputURL: URL) throws {
        guard takeRecorder == nil else { throw InstrumentRecordingError.alreadyRecording }
        guard let instrumentMixer = instrumentMixers[trackID] else {
            throw InstrumentRecordingError.destinationUnavailable
        }

        let format = instrumentMixer.outputFormat(forBus: 0)
        let recorder: InstrumentTakeRecorder
        do {
            recorder = try InstrumentTakeRecorder(url: outputURL, format: format)
        } catch {
            throw InstrumentRecordingError.fileCreationFailed
        }

        instrumentMixer.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            recorder.append(buffer)
        }
        takeRecorder = recorder
        takeTrackID = trackID
        takeURL = outputURL
        takeUsesMicrophone = false

        guard startAudioEngine() else {
            instrumentMixer.removeTap(onBus: 0)
            takeRecorder = nil
            takeTrackID = nil
            takeURL = nil
            try? FileManager.default.removeItem(at: outputURL)
            throw InstrumentRecordingError.engineUnavailable
        }
    }

    func startMicrophoneRecording(trackID: UUID, outputURL: URL) throws {
        guard takeRecorder == nil else { throw InstrumentRecordingError.alreadyRecording }
        guard instrumentMixers[trackID] != nil else {
            throw InstrumentRecordingError.destinationUnavailable
        }

        let audioSession = AVAudioSession.sharedInstance()
        guard audioSession.recordPermission == .granted else {
            throw InstrumentRecordingError.microphoneUnavailable
        }
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            throw InstrumentRecordingError.microphoneUnavailable
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw InstrumentRecordingError.microphoneUnavailable
        }

        let recorder: InstrumentTakeRecorder
        do {
            recorder = try InstrumentTakeRecorder(url: outputURL, format: format)
        } catch {
            throw InstrumentRecordingError.fileCreationFailed
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            recorder.append(buffer)
        }
        takeRecorder = recorder
        takeTrackID = trackID
        takeURL = outputURL
        takeUsesMicrophone = true

        guard startAudioEngine() else {
            input.removeTap(onBus: 0)
            takeRecorder = nil
            takeTrackID = nil
            takeURL = nil
            takeUsesMicrophone = false
            try? FileManager.default.removeItem(at: outputURL)
            throw InstrumentRecordingError.engineUnavailable
        }
    }

    func finishInstrumentRecording() -> RecordedInstrumentTake? {
        guard let recorder = takeRecorder,
              let trackID = takeTrackID,
              let url = takeURL else { return nil }

        if takeUsesMicrophone {
            engine.inputNode.removeTap(onBus: 0)
        } else {
            instrumentMixers[trackID]?.removeTap(onBus: 0)
        }
        takeUsesMicrophone = false
        takeRecorder = nil
        takeTrackID = nil
        takeURL = nil

        guard let recordedDuration = recorder.finish() else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return RecordedInstrumentTake(trackID: trackID, url: url, duration: recordedDuration)
    }

    private func startAudioEngine() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            lastStartError = "The audio session could not start: \(error.localizedDescription)"
        }

        guard !engine.isRunning else { return true }
        engine.prepare()
        do {
            try engine.start()
            lastStartError = nil
            return true
        } catch {
            lastStartError = error.localizedDescription
            return false
        }
    }

    private func voices(for destinationTrackID: UUID?) -> (trackID: UUID?, players: [AVAudioPlayerNode]) {
        if let destinationTrackID, let voices = instrumentVoices[destinationTrackID] {
            return (destinationTrackID, voices)
        }
        ensurePreviewVoices()
        return (nil, previewVoices)
    }

    private func nextVoiceIndex(for trackID: UUID?, count: Int) -> Int {
        guard count > 0 else { return 0 }
        if let trackID {
            let index = voiceCursors[trackID, default: 0] % count
            voiceCursors[trackID] = (index + 1) % count
            return index
        }
        let index = previewVoiceCursor % count
        previewVoiceCursor = (index + 1) % count
        return index
    }

    private func ensurePreviewFormat() {
        guard previewFormat == nil else { return }
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44_100
        let channels = min(max(outputFormat.channelCount, 1), 2)
        previewFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)
    }

    private func ensurePreviewVoices() {
        guard previewVoices.isEmpty else { return }
        ensurePreviewFormat()
        guard let previewFormat else { return }
        for _ in 0..<instrumentVoiceCount {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: previewFormat)
            previewVoices.append(voice)
        }
    }

    private func detachAll() {
        if takeUsesMicrophone {
            engine.inputNode.removeTap(onBus: 0)
        } else if let takeTrackID {
            instrumentMixers[takeTrackID]?.removeTap(onBus: 0)
        }
        _ = takeRecorder?.finish()
        takeRecorder = nil
        takeTrackID = nil
        takeURL = nil
        takeUsesMicrophone = false

        engine.stop()
        for loadedClips in clipPlayers.values {
            loadedClips.forEach { clip in
                clip.player.stop()
                engine.detach(clip.player)
            }
        }
        for voices in instrumentVoices.values {
            voices.forEach { voice in
                voice.stop()
                engine.detach(voice)
            }
        }
        for players in notePlayers.values {
            players.forEach { player in
                player.stop()
                engine.detach(player)
            }
        }
        notePlayers.removeAll()
        notePlayerBusy.removeAll()
        noteBufferCache.removeAll()
        previewVoices.forEach { voice in
            voice.stop()
            engine.detach(voice)
        }
        for mixer in instrumentMixers.values {
            engine.detach(mixer)
        }
        for equalizer in equalizers.values {
            engine.detach(equalizer)
        }
        for compressor in compressors.values {
            engine.detach(compressor)
        }
        for mixer in trackMixers.values {
            mixer.removeTap(onBus: 0)
            engine.detach(mixer)
        }
        trackMixers.removeAll()
        instrumentMixers.removeAll()
        equalizers.removeAll()
        compressors.removeAll()
        clipPlayers.removeAll()
        clipSignatures.removeAll()
        instrumentVoices.removeAll()
        instrumentFormats.removeAll()
        voiceCursors.removeAll()
        previewVoices.removeAll()
        previewFormat = nil
        scheduledInstrumentFiles.removeAll()
        mixTracks = []
        automationTime = 0
        trackIDs = []
        playHeadOffset = 0
        playStartDate = nil
        isPlaying = false
    }
}

/// Copies imported audio into the app's own Stems folder and persists the session.
enum TrackStorage {
    private static let tracksKey = "studio.tracks"
    private static let stemFolderName = "Stems"

    static var stemsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent(stemFolderName)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func url(forFileName fileName: String) -> URL {
        stemsDirectory.appendingPathComponent(fileName)
    }

    static func importFile(at source: URL) throws -> (storedName: String, displayName: String) {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        var destination = stemsDirectory.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = stemsDirectory.appendingPathComponent("\(UUID().uuidString.prefix(8))_\(source.lastPathComponent)")
        }
        try FileManager.default.copyItem(at: source, to: destination)

        // Convert compressed formats (MP3, M4A, …) to WAV PCM on import so
        // playback, waveforms and stem separation all work reliably.
        var storedName = destination.lastPathComponent
        if destination.pathExtension.lowercased() != "wav",
           let converted = try? convertToWAV(at: destination) {
            try? FileManager.default.removeItem(at: destination)
            storedName = converted.lastPathComponent
        }

        let display = source.deletingPathExtension().lastPathComponent
        return (storedName, display)
    }

    /// Converts any readable audio file to interleaved float32 WAV, chunk by chunk.
    private static func convertToWAV(at url: URL) throws -> URL? {
        let input = try AVAudioFile(forReading: url)
        let sampleRate = input.processingFormat.sampleRate
        let channelCount = input.processingFormat.channelCount

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: true
        ) else { return nil }

        guard let readBuffer = try? AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 32768),
              let writeBuffer = try? AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 32768),
              let readData = readBuffer.floatChannelData,
              let writeData = writeBuffer.floatChannelData else { return nil }

        let outputURL = uniqueStemURL(baseName: url.deletingPathExtension().lastPathComponent, fileExtension: "wav")
        let output = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: true
        )

        let channels = Int(channelCount)
        while true {
            try input.read(into: readBuffer)
            let frames = Int(readBuffer.frameLength)
            if frames == 0 { break }

            for frame in 0..<frames {
                for channel in 0..<channels {
                    writeData[0][frame * channels + channel] = readData[channel][frame]
                }
            }

            writeBuffer.frameLength = readBuffer.frameLength
            try output.write(from: writeBuffer)
        }

        return outputURL
    }

    /// Returns a unique destination in the Stems folder for a new stem file.
    static func uniqueStemURL(baseName: String, fileExtension: String) -> URL {
        let safeName = baseName.replacingOccurrences(of: " ", with: "-")
        return stemsDirectory.appendingPathComponent("stem-\(UUID().uuidString.prefix(8))-\(safeName).\(fileExtension)")
    }

    static func loadTracks() -> [Track] {
        guard let data = UserDefaults.standard.data(forKey: tracksKey),
              let tracks = try? JSONDecoder().decode([Track].self, from: data) else { return [] }
        return tracks
    }

    static func saveTracks(_ tracks: [Track]) {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        UserDefaults.standard.set(data, forKey: tracksKey)
    }
}
