//
//  MixerViewModel.swift
//  AI Music Studio
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class MixerViewModel: ObservableObject {
    private struct UndoTrackState: Equatable {
        let id: UUID
        let clips: [AudioClip]
        let volume: Float
        let isMuted: Bool
        let isSoloed: Bool
        let volumeAutomationPoints: [VolumeAutomationPoint]
        let panAutomationPoints: [PanAutomationPoint]
        let notes: [SynthNote]
    }

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var groups: [TrackGroup] = []
    @Published private(set) var sessions: [StudioSession] = []
    @Published private(set) var activeSessionID = UUID()
    @Published private(set) var sessionName = "Untitled Session"
    @Published private(set) var activeTemplateID: String?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var levels: [UUID: Float] = [:]
    @Published private(set) var masterVolume: Float = 1
    @Published private(set) var masterEffects = MasterEffectsSettings()
    @Published private(set) var mastering = MasteringSettings()
    @Published private(set) var loudness = LoudnessReading()
    @Published private(set) var auxBusA = AuxBusSettings.busA
    @Published private(set) var auxBusB = AuxBusSettings.busB
    @Published private(set) var sections: [SongSection] = []
    @Published private(set) var channelPresets: [ChannelPreset] = []
    @Published private(set) var customTemplates: [SessionTemplate] = []
    @Published private(set) var versions: [SessionVersion] = []
    @Published private(set) var sessionTransferProgress: Double?
    @Published private(set) var sessionTransferTitle = ""
    @Published private(set) var sessionExportURL: URL?
    @Published var sessionTransferError: String?
    @Published private(set) var midiExportURL: URL?
    @Published var midiError: String?
    private var autosaveTask: Task<Void, Never>?
    private var storedVersions: [SessionVersion] = []
    @Published private(set) var masterLevel: Float = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var tempoBPM = 120
    @Published private(set) var loopStart: TimeInterval = 0
    @Published private(set) var loopEnd: TimeInterval = 0
    @Published private(set) var isLoopEnabled = false
    @Published private(set) var isMetronomeEnabled = false
    @Published private(set) var metronomeLevel: Float = 0.7
    @Published private(set) var isCountInEnabled = false
    @Published private(set) var punchIn: TimeInterval = 0
    @Published private(set) var punchOut: TimeInterval = 0
    @Published private(set) var isPunchEnabled = false
    @Published private(set) var armedTrackID: UUID?
    @Published private(set) var isCountingIn = false
    @Published private(set) var countInBeatsRemaining = 0
    @Published private(set) var drumPattern = DrumPattern()
    @Published private(set) var drumKit = DrumKit.studio808
    @Published private(set) var studioMode = StudioModeStorage.load()
    @Published private(set) var isDrumSequencerPlaying = false
    @Published private(set) var currentDrumStep: Int?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    // Timeline state
    @Published private(set) var waveformPeaks: [UUID: [Float]] = [:]
    @Published private(set) var clipWaveformPeaks: [UUID: [Float]] = [:]
    @Published var scrubTime: Double?

    // Stem separation state
    @Published private(set) var isSeparating = false
    @Published private(set) var separationStatus = ""
    @Published private(set) var separationProgress: Double = 0
    @Published var separationError: String?
    @Published private(set) var samplerDisplayName: String?
    @Published private(set) var samplerError: String?
    @Published private(set) var sampleLibrary: [SampleLibraryItem] = []
    @Published private(set) var isLoadingSampleLibrary = false
    @Published private(set) var previewingSampleID: String?
    @Published private(set) var isFreezingTrack = false
    @Published private(set) var freezeStatus = ""
    @Published var freezeError: String?
    @Published private(set) var isRecordingInstrument = false
    @Published private(set) var recordingElapsed: TimeInterval = 0
    @Published private(set) var recordingError: String?
    @Published private(set) var microphonePermissionGranted = false
    @Published private(set) var microphoneError: String?
    @Published private(set) var isBouncing = false
    @Published private(set) var isStemBounce = false
    @Published private(set) var bounceProgress = 0.0
    @Published private(set) var bounceStatus = ""
    @Published private(set) var bounceError: String?
    @Published private(set) var bounceSettings = BounceSettingsStorage.load()
    @Published var audioError: String?
    @Published private(set) var exports: [MixExport] = []
    @Published private(set) var lastExportURL: URL?

    private var recordingStartTime: TimeInterval = 0
    private var samplerFileURL: URL?
    private let engine = MixerEngine()
    private var smoothedLevels: [UUID: Float] = [:]
    private var waveformTask: Task<Void, Never>?
    private var wasPlayingBeforeScrub = false
    nonisolated(unsafe) private var playbackTask: Task<Void, Never>?
    nonisolated(unsafe) private var drumSequencerTask: Task<Void, Never>?
    nonisolated(unsafe) private var samplePreviewTask: Task<Void, Never>?
    nonisolated(unsafe) private var countInTask: Task<Void, Never>?
    private var undoStack: [[UndoTrackState]] = []
    private var redoStack: [[UndoTrackState]] = []
    private var pendingUndoSnapshot: [UndoTrackState]?
    private let historyLimit = 50
    private let minimumLoopLength: TimeInterval = 0.2

    init() {
        microphonePermissionGranted = AVAudioSession.sharedInstance().recordPermission == .granted
        channelPresets = ChannelPresetStorage.load()
        customTemplates = SessionTemplateStorage.load()
        let storedSessions = StudioSessionStorage.load()
        var initialSessions = storedSessions.sessions
        var initialSessionID = storedSessions.activeSessionID
        let shouldSeedDemo = !StudioSessionStorage.hasSeededHouseDemo
            && !initialSessions.contains(where: { $0.templateID == "house-demo" })

        if shouldSeedDemo {
            let demo = HouseDemoSessionFactory.make()
            if initialSessions.count == 1,
               initialSessions[0].name == "Untitled Session",
               initialSessions[0].tracks.isEmpty {
                initialSessions = [demo]
            } else {
                initialSessions.append(demo)
            }
            initialSessionID = demo.id
            StudioSessionStorage.save(sessions: initialSessions, activeSessionID: initialSessionID)
        }
        StudioSessionStorage.markHouseDemoSeeded()

        sessions = initialSessions
        activeSessionID = initialSessionID
        if let session = initialSessions.first(where: { $0.id == initialSessionID }) {
            sessionName = session.name
            activeTemplateID = session.templateID
            tracks = session.tracks
            groups = session.groups
            tempoBPM = min(200, max(60, session.tempoBPM))
            drumPattern = session.drumPattern
            drumKit = session.drumKit
            loopStart = max(0, session.loopStart)
            loopEnd = max(loopStart, session.loopEnd)
            isLoopEnabled = session.isLoopEnabled
            masterVolume = min(1, max(0, session.masterVolume))
            masterEffects = session.masterEffects
            mastering = session.mastering
            auxBusA = session.auxBusA
            auxBusB = session.auxBusB
            sections = session.sections
            isMetronomeEnabled = session.isMetronomeEnabled
            metronomeLevel = min(1, max(0, session.metronomeLevel))
            isCountInEnabled = session.isCountInEnabled
            punchIn = max(0, session.punchIn)
            punchOut = max(punchIn, session.punchOut)
            isPunchEnabled = session.isPunchEnabled
            armedTrackID = session.armedTrackID
        }
        storedVersions = SessionVersionStore.load()
        versions = storedVersions.filter { $0.sessionID == activeSessionID }
        exports = MixExportStorage.loadExports()
        resolveClipMetadata()
        engine.load(tracks: tracks)
        engine.updateGroups(groups)
        duration = engine.duration
        applyLoopChangeToEngine()
        engine.setMasterVolume(masterVolume)
        engine.setTempo(tempoBPM)
        engine.updateMasterEffects(masterEffects, tempoBPM: tempoBPM)
        engine.updateMasterChain(mastering)
        engine.setMetronome(enabled: isMetronomeEnabled, level: metronomeLevel)
        loadWaveforms()

        // Keep a first snapshot so there is always something to go back to.
        if versions.isEmpty {
            Task { [weak self] in
                await Task.yield()
                self?.saveVersionNow(force: true)
            }
        }

        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1.0 / 30))
            }
        }
    }

    deinit {
        autosaveTask?.cancel()
        playbackTask?.cancel()
        drumSequencerTask?.cancel()
        samplePreviewTask?.cancel()
        countInTask?.cancel()
    }

    func importTracks(from urls: [URL]) {
        var imported: [Track] = []
        for url in urls {
            if let result = try? TrackStorage.importFile(at: url) {
                imported.append(Track(name: result.displayName, fileName: result.storedName))
            }
        }
        guard !imported.isEmpty else { return }

        tracks += imported
        reloadEngine()
    }

    /// Adds an empty audio layer and returns its id for immediate instrument routing.
    @discardableResult
    func addInstrumentTrack() -> UUID {
        var number = 1
        let existingNames = Set(tracks.map { $0.name.lowercased() })
        while existingNames.contains("instrument layer \(number)") {
            number += 1
        }

        let track = Track(name: "Instrument Layer \(number)", fileName: "", clips: [])
        let wasPlaying = isPlaying
        let resumeTime = engine.currentTime
        tracks.append(track)
        resolveClipMetadata()
        engine.load(tracks: tracks)
        engine.updateGroups(groups)
        duration = engine.duration
        applyLoopChangeToEngine()
        currentTime = min(max(0, resumeTime), duration)
        engine.seek(to: currentTime)
        if wasPlaying { engine.play() }
        isPlaying = engine.isPlaying
        currentTime = engine.currentTime
        loadWaveforms()
        commitSession()
        return track.id
    }

    func setVolume(_ id: UUID, _ value: Float) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        beginUndoableEdit()
        tracks[index].volume = value
        engine.updateMix(tracks: tracks)
    }

    /// Places a track in the stereo field, from -1 (left) to 1 (right).
    func setPan(_ id: UUID, _ value: Float) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].pan = min(1, max(-1, value))
        engine.updateMix(tracks: tracks)
    }

    /// Sets the overall output level of the master strip.
    func setMasterVolume(_ value: Float) {
        masterVolume = min(1, max(0, value))
        engine.setMasterVolume(masterVolume)
    }

    /// Applies the master reverb and delay settings while they are adjusted.
    func updateMasterEffects(_ settings: MasterEffectsSettings) {
        masterEffects = settings
        engine.updateMasterEffects(settings, tempoBPM: tempoBPM)
    }

    /// Applies the mastering chain while its controls are adjusted.
    func updateMastering(_ settings: MasteringSettings) {
        mastering = settings
        engine.updateMasterChain(settings)
    }

    /// Clears the integrated loudness and peak hold for a fresh measurement.
    func resetLoudness() {
        engine.resetLoudness()
        loudness = LoudnessReading()
    }

    /// Sets a track's send level to one of the two aux buses.
    func setSend(_ trackID: UUID, bus: String, value: Float) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let clamped = min(1, max(0, value))
        if bus == "B" {
            tracks[index].sendB = clamped
        } else {
            tracks[index].sendA = clamped
        }
        engine.updateMix(tracks: tracks)
        commitSession()
    }

    /// Applies an aux bus's effects and return level.
    func updateAuxBus(_ settings: AuxBusSettings) {
        if settings.id == "B" {
            auxBusB = settings
        } else {
            auxBusA = settings
        }
        engine.updateAuxBuses(a: auxBusA, b: auxBusB)
        commitSession()
    }

    // MARK: - Song sections

    /// Adds a named section marker at the playhead and returns its id.
    func addSection(at time: TimeInterval) -> UUID? {
        let section = SongSection(
            name: SongSection.suggestedName(existing: sections),
            time: snappedSectionTime(time)
        )
        sections.append(section)
        sections.sort { $0.time < $1.time }
        persistActiveSession()
        return section.id
    }

    /// Moves a section marker, snapping it to the bar grid.
    func moveSection(_ id: UUID, to time: TimeInterval) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        sections[index].time = snappedSectionTime(time)
        sections.sort { $0.time < $1.time }
    }

    func renameSection(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = sections.firstIndex(where: { $0.id == id }) else { return }
        sections[index].name = trimmed
        persistActiveSession()
    }

    func deleteSection(_ id: UUID) {
        sections.removeAll { $0.id == id }
        persistActiveSession()
    }

    /// Saves finished marker edits with the session.
    func commitSections() {
        persistActiveSession()
    }

    /// Moves the playhead, keeping playback running when it was playing.
    func seek(to time: TimeInterval) {
        let position = duration > 0 ? min(max(0, time), duration) : max(0, time)
        scrubTime = nil
        currentTime = position
        engine.seek(to: position)
        isPlaying = engine.isPlaying
        currentTime = engine.currentTime
    }

    private func snappedSectionTime(_ time: TimeInterval) -> TimeInterval {
        let bar = beatDuration * 4
        let snapped = (max(0, time) / bar).rounded() * bar
        if duration > 0 {
            return min(snapped, duration)
        }
        return max(0, snapped)
    }

    // MARK: - Channel presets

    /// Captures a track's EQ, compressor, pan and level as a named preset.
    @discardableResult
    func saveChannelPreset(from trackID: UUID, name: String) -> UUID? {
        guard let track = tracks.first(where: { $0.id == trackID }) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = ChannelPreset(
            name: trimmed.isEmpty ? "\(track.name) Preset" : trimmed,
            sourceTrackName: track.name,
            volume: track.volume,
            pan: track.pan,
            eqSettings: track.eqSettings,
            compressorSettings: track.compressorSettings
        )
        channelPresets.insert(preset, at: 0)
        ChannelPresetStorage.save(channelPresets)
        return preset.id
    }

    /// Applies a preset's EQ, compressor, pan and level to a track.
    func applyChannelPreset(_ presetID: UUID, to trackID: UUID) {
        guard let preset = channelPresets.first(where: { $0.id == presetID }),
              let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }

        beginUndoableEdit()
        tracks[index].volume = preset.volume
        tracks[index].pan = preset.pan
        tracks[index].eqSettings = preset.eqSettings
        tracks[index].compressorSettings = preset.compressorSettings

        engine.updateMix(tracks: tracks)
        engine.updateEqualizer(trackID: trackID, settings: preset.eqSettings)
        engine.updateCompressor(trackID: trackID, settings: preset.compressorSettings)
        commitSession()
    }

    func renameChannelPreset(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = channelPresets.firstIndex(where: { $0.id == id }) else { return }
        channelPresets[index].name = trimmed
        ChannelPresetStorage.save(channelPresets)
    }

    func deleteChannelPreset(_ id: UUID) {
        channelPresets.removeAll { $0.id == id }
        ChannelPresetStorage.save(channelPresets)
    }

    func addVolumeAutomationPoint(
        trackID: UUID,
        at time: TimeInterval,
        gain: Float,
        snapInterval: TimeInterval,
        maximumTime: TimeInterval
    ) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        beginUndoableEdit()
        let snapped = min(maximumTime, snappedTime(time, interval: snapInterval))
        tracks[index].volumeAutomationPoints.append(
            VolumeAutomationPoint(time: snapped, gain: min(1, max(0, gain)))
        )
        tracks[index].volumeAutomationPoints.sort { $0.time < $1.time }
        engine.updateMix(tracks: tracks)
        commitSession()
    }

    func moveVolumeAutomationPoint(
        trackID: UUID,
        pointID: UUID,
        to time: TimeInterval,
        gain: Float,
        snapInterval: TimeInterval,
        maximumTime: TimeInterval
    ) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let pointIndex = tracks[trackIndex].volumeAutomationPoints.firstIndex(where: { $0.id == pointID }) else { return }
        beginUndoableEdit()
        let snapped = min(maximumTime, snappedTime(time, interval: snapInterval))
        tracks[trackIndex].volumeAutomationPoints[pointIndex].time = snapped
        tracks[trackIndex].volumeAutomationPoints[pointIndex].gain = min(1, max(0, gain))
        tracks[trackIndex].volumeAutomationPoints.sort { $0.time < $1.time }
        engine.updateMix(tracks: tracks)
    }

    func deleteVolumeAutomationPoint(trackID: UUID, pointID: UUID) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let pointIndex = tracks[trackIndex].volumeAutomationPoints.firstIndex(where: { $0.id == pointID }) else { return }
        beginUndoableEdit()
        tracks[trackIndex].volumeAutomationPoints.remove(at: pointIndex)
        engine.updateMix(tracks: tracks)
        commitSession()
    }

    // MARK: - Pan automation

    func addPanAutomationPoint(
        trackID: UUID,
        at time: TimeInterval,
        pan: Float,
        snapInterval: TimeInterval,
        maximumTime: TimeInterval
    ) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        beginUndoableEdit()
        let snapped = min(maximumTime, snappedTime(time, interval: snapInterval))
        tracks[index].panAutomationPoints.append(
            PanAutomationPoint(time: snapped, pan: min(1, max(-1, pan)))
        )
        tracks[index].panAutomationPoints.sort { $0.time < $1.time }
        engine.updateMix(tracks: tracks)
        commitSession()
    }

    func movePanAutomationPoint(
        trackID: UUID,
        pointID: UUID,
        to time: TimeInterval,
        pan: Float,
        snapInterval: TimeInterval,
        maximumTime: TimeInterval
    ) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let pointIndex = tracks[trackIndex].panAutomationPoints.firstIndex(where: { $0.id == pointID }) else { return }
        beginUndoableEdit()
        let snapped = min(maximumTime, snappedTime(time, interval: snapInterval))
        tracks[trackIndex].panAutomationPoints[pointIndex].time = snapped
        tracks[trackIndex].panAutomationPoints[pointIndex].pan = min(1, max(-1, pan))
        tracks[trackIndex].panAutomationPoints.sort { $0.time < $1.time }
        engine.updateMix(tracks: tracks)
    }

    func deletePanAutomationPoint(trackID: UUID, pointID: UUID) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let pointIndex = tracks[trackIndex].panAutomationPoints.firstIndex(where: { $0.id == pointID }) else { return }
        beginUndoableEdit()
        tracks[trackIndex].panAutomationPoints.remove(at: pointIndex)
        engine.updateMix(tracks: tracks)
        commitSession()
    }

    /// Applies an arpeggiator's settings to a track's arrangement notes.
    func updateArpeggiator(_ settings: ArpeggiatorSettings, for trackID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        beginUndoableEdit()
        tracks[index].arpeggiator = settings
        engine.updateMix(tracks: tracks)
        duration = engine.duration
        commitSession()
    }

    // MARK: - Piano roll notes

    func addSynthNote(
        trackID: UUID,
        pitch: Int,
        startTime: TimeInterval,
        duration noteDuration: TimeInterval,
        snapInterval: TimeInterval
    ) -> UUID? {
        addSynthChord(
            trackID: trackID,
            pitch: pitch,
            startTime: startTime,
            duration: noteDuration,
            chordType: .single,
            snapInterval: snapInterval
        ).first
    }

    /// Places every note of a chord on the same beat, as one undoable edit.
    @discardableResult
    func addSynthChord(
        trackID: UUID,
        pitch: Int,
        startTime: TimeInterval,
        duration noteDuration: TimeInterval,
        chordType: ChordType,
        snapInterval: TimeInterval
    ) -> [UUID] {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return [] }
        beginUndoableEdit()
        let start = snappedTime(startTime, interval: snapInterval)
        let length = max(snapInterval, snappedTime(noteDuration, interval: snapInterval))
        let rootPitch = min(SynthNote.highestPitch, max(SynthNote.lowestPitch, pitch))

        var ids: [UUID] = []
        for chordPitch in chordType.pitches(root: rootPitch) {
            let note = SynthNote(pitch: chordPitch, startTime: start, duration: length)
            tracks[index].notes.append(note)
            ids.append(note.id)
        }

        tracks[index].notes.sort { $0.startTime < $1.startTime }
        engine.updateMix(tracks: tracks)
        duration = engine.duration
        commitSession()
        return ids
    }

    func moveSynthNote(
        trackID: UUID,
        noteID: UUID,
        startTime: TimeInterval,
        pitch: Int,
        snapInterval: TimeInterval
    ) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let noteIndex = tracks[trackIndex].notes.firstIndex(where: { $0.id == noteID }) else { return }
        beginUndoableEdit()
        tracks[trackIndex].notes[noteIndex].startTime = snappedTime(startTime, interval: snapInterval)
        tracks[trackIndex].notes[noteIndex].pitch = min(SynthNote.highestPitch, max(SynthNote.lowestPitch, pitch))
        tracks[trackIndex].notes.sort { $0.startTime < $1.startTime }
        engine.updateMix(tracks: tracks)
        duration = engine.duration
    }

    func resizeSynthNote(
        trackID: UUID,
        noteID: UUID,
        duration newDuration: TimeInterval,
        snapInterval: TimeInterval
    ) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let noteIndex = tracks[trackIndex].notes.firstIndex(where: { $0.id == noteID }) else { return }
        beginUndoableEdit()
        tracks[trackIndex].notes[noteIndex].duration = max(snapInterval, snappedTime(newDuration, interval: snapInterval))
        engine.updateMix(tracks: tracks)
        duration = engine.duration
    }

    func deleteSynthNote(trackID: UUID, noteID: UUID) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let noteIndex = tracks[trackIndex].notes.firstIndex(where: { $0.id == noteID }) else { return }
        beginUndoableEdit()
        tracks[trackIndex].notes.remove(at: noteIndex)
        engine.updateMix(tracks: tracks)
        duration = engine.duration
        commitSession()
    }

    /// Removes every selected note as one undoable edit.
    func deleteSynthNotes(trackID: UUID, noteIDs: Set<UUID>) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }), !noteIDs.isEmpty else { return }
        beginUndoableEdit()
        tracks[index].notes.removeAll { noteIDs.contains($0.id) }
        engine.updateMix(tracks: tracks)
        duration = engine.duration
        commitSession()
    }

    /// Sets how hard a note plays while the velocity handle is dragged.
    func setSynthNoteVelocity(trackID: UUID, noteID: UUID, velocity: Float) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let noteIndex = tracks[trackIndex].notes.firstIndex(where: { $0.id == noteID }) else { return }
        tracks[trackIndex].notes[noteIndex].velocity = min(1, max(0.05, velocity))
        engine.updateMix(tracks: tracks)
    }

    /// Pulls the selected notes toward the beat while keeping some of their feel.
    func quantizeSynthNotes(trackID: UUID, noteIDs: Set<UUID>, grid: TimeInterval, strength: Double) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              !noteIDs.isEmpty else { return }
        let step = max(0.01, grid)
        let amount = min(1, max(0, strength))
        beginUndoableEdit()

        for noteIndex in tracks[trackIndex].notes.indices where noteIDs.contains(tracks[trackIndex].notes[noteIndex].id) {
            let note = tracks[trackIndex].notes[noteIndex]
            let target = (note.startTime / step).rounded() * step
            let shifted = note.startTime + (target - note.startTime) * amount
            tracks[trackIndex].notes[noteIndex].startTime = max(0, shifted)
        }

        tracks[trackIndex].notes.sort { $0.startTime < $1.startTime }
        engine.updateMix(tracks: tracks)
        duration = engine.duration
        commitSession()
    }

    // MARK: - MIDI

    /// Adds a new instrument track holding the notes of an imported MIDI file.
    @discardableResult
    func addMIDITrack(_ imported: MIDIFile.Imported) -> UUID {
        if let tempo = imported.tempoBPM {
            setTempo(tempo)
        }

        let proposed = (imported.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = proposed.isEmpty ? "MIDI Track" : proposed
        var name = base
        var suffix = 2
        while tracks.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            name = "\(base) \(suffix)"
            suffix += 1
        }

        let track = Track(
            name: name,
            fileName: "",
            clips: [],
            notes: clampedImportedNotes(imported.notes)
        )
        let wasPlaying = isPlaying
        let resumeTime = engine.currentTime

        tracks.append(track)
        resolveClipMetadata()
        engine.load(tracks: tracks)
        engine.updateGroups(groups)
        duration = engine.duration
        applyLoopChangeToEngine()
        currentTime = min(max(0, resumeTime), duration)
        engine.seek(to: currentTime)
        if wasPlaying { engine.play() }
        isPlaying = engine.isPlaying
        currentTime = engine.currentTime
        loadWaveforms()
        commitSession()
        return track.id
    }

    /// Swaps a track's piano-roll notes for the ones read from a MIDI file.
    func replaceSynthNotes(trackID: UUID, with notes: [SynthNote], tempoBPM: Int? = nil) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }),
              !notes.isEmpty else { return }
        if let tempo = tempoBPM {
            setTempo(tempo)
        }
        beginUndoableEdit()
        tracks[index].notes = clampedImportedNotes(notes)
        engine.updateMix(tracks: tracks)
        duration = engine.duration
        commitSession()
    }

    /// Writes a track's sequenced notes to a standard MIDI file for sharing.
    func exportMIDI(trackID: UUID) {
        guard let track = tracks.first(where: { $0.id == trackID }) else { return }
        guard !track.notes.isEmpty else {
            midiError = "This track has no sequenced notes to export yet."
            return
        }

        let data = MIDIFile.export(track: track, tempoBPM: tempoBPM)
        let directory = MIDIFile.exportsDirectory
        let url = directory.appendingPathComponent(MIDIFile.suggestedFileName(for: track.name))

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            midiError = nil
            midiExportURL = url
        } catch {
            midiExportURL = nil
            midiError = "The MIDI file could not be written."
        }
    }

    func clearMIDIExportURL() {
        midiExportURL = nil
    }

    /// Brings imported notes into the piano roll's playable range.
    private func clampedImportedNotes(_ notes: [SynthNote]) -> [SynthNote] {
        notes
            .map { note in
                var copy = note
                copy.pitch = min(SynthNote.highestPitch, max(SynthNote.lowestPitch, note.pitch))
                copy.startTime = max(0, note.startTime)
                copy.duration = max(0.05, note.duration)
                copy.velocity = min(1, max(0.05, note.velocity))
                return copy
            }
            .sorted { $0.startTime < $1.startTime }
    }

    func setTrackEQ(_ id: UUID, settings: TrackEQSettings) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].eqSettings = settings
        engine.updateEqualizer(trackID: id, settings: settings)
        commitSession()
    }

    func setTrackCompressor(_ id: UUID, settings: TrackCompressorSettings) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].compressorSettings = settings
        engine.updateCompressor(trackID: id, settings: settings)
        commitSession()
    }

    func commitSession() {
        finishUndoableEdit()
        persistActiveSession()
    }

    func createSession() {
        prepareToLeaveCurrentSession()
        persistActiveSession(markEdited: false)
        let session = StudioSession(name: uniqueSessionName("Untitled Session"))
        sessions.append(session)
        activateSession(session)
    }

    /// Starts a session from a prepared layout, with its tracks, colours and mixer
    /// settings already in place.
    func createSession(from template: SessionTemplate) {
        prepareToLeaveCurrentSession()
        persistActiveSession(markEdited: false)
        var session = StudioSession(
            name: uniqueSessionName(template.name),
            templateID: template.id,
            tempoBPM: template.tempoBPM
        )
        session.tracks = template.tracks.map { slot in
            Track(
                name: slot.name,
                fileName: "",
                volume: slot.volume,
                pan: slot.pan,
                eqSettings: slot.eqSettings,
                compressorSettings: slot.compressorSettings
            )
        }
        sessions.append(session)
        activateSession(session)
    }

    /// Opens a fully written session from the AI songwriter, keeping its tracks,
    /// arrangement, tempo and drum kit.
    func createSession(fromGenerated generated: StudioSession) {
        prepareToLeaveCurrentSession()
        persistActiveSession(markEdited: false)
        var session = generated
        session.name = uniqueSessionName(generated.name)
        session.lastEdited = Date()
        sessions.append(session)
        activateSession(session)
    }

    /// Captures the current session's arrangement notes with a new voice.
    func setVoice(_ trackID: UUID, voice: TrackVoiceKind) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }), tracks[index].voice != voice else {
            return
        }
        tracks[index].voice = voice
        engine.load(tracks: tracks)
        commitSession()
    }

    /// Captures the open session's tracks and mixer settings as a custom template.
    @discardableResult
    func saveCurrentSessionAsTemplate(name: String) -> SessionTemplate? {
        persistActiveSession(markEdited: false)
        guard !tracks.isEmpty,
              let session = sessions.first(where: { $0.id == activeSessionID }) else { return nil }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? session.name : trimmed
        var templateName = base
        var suffix = 2
        while customTemplates.contains(where: { $0.name.caseInsensitiveCompare(templateName) == .orderedSame }) {
            templateName = "\(base) \(suffix)"
            suffix += 1
        }

        let template = SessionTemplate.make(from: session, name: templateName)
        customTemplates.insert(template, at: 0)
        SessionTemplateStorage.save(customTemplates)
        return template
    }

    /// Removes a saved template, leaving the sessions made from it untouched.
    func deleteCustomTemplate(_ id: String) {
        guard customTemplates.contains(where: { $0.id == id }) else { return }
        customTemplates.removeAll { $0.id == id }
        SessionTemplateStorage.save(customTemplates)
    }

    func openSession(_ id: UUID) {
        guard id != activeSessionID,
              let session = sessions.first(where: { $0.id == id }) else { return }
        prepareToLeaveCurrentSession()
        persistActiveSession(markEdited: false)
        activateSession(session)
    }

    func renameSession(_ id: UUID, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].name = trimmedName
        sessions[index].lastEdited = Date()
        if id == activeSessionID {
            sessionName = trimmedName
        }
        StudioSessionStorage.save(sessions: sessions, activeSessionID: activeSessionID)
    }

    func duplicateSession(_ id: UUID) -> UUID? {
        persistActiveSession(markEdited: false)
        guard let source = sessions.first(where: { $0.id == id }) else { return nil }
        var duplicate = source
        duplicate.id = UUID()
        duplicate.name = uniqueSessionName("\(source.name) Copy")
        duplicate.lastEdited = Date()

        var trackIDMap: [UUID: UUID] = [:]
        for trackIndex in duplicate.tracks.indices {
            let originalTrackID = duplicate.tracks[trackIndex].id
            let newTrackID = UUID()
            trackIDMap[originalTrackID] = newTrackID
            duplicate.tracks[trackIndex].id = newTrackID
            for clipIndex in duplicate.tracks[trackIndex].clips.indices {
                var clip = duplicate.tracks[trackIndex].clips[clipIndex]
                clip.id = clip.isOriginal && clip.id == originalTrackID ? newTrackID : UUID()
                duplicate.tracks[trackIndex].clips[clipIndex] = clip
            }
        }
        duplicate.groups = duplicate.groups.compactMap { group in
            let members = group.trackIDs.compactMap { trackIDMap[$0] }
            guard !members.isEmpty else { return nil }
            var copy = group
            copy.id = UUID()
            copy.trackIDs = members
            return copy
        }

        sessions.append(duplicate)
        StudioSessionStorage.save(sessions: sessions, activeSessionID: activeSessionID)
        return duplicate.id
    }

    func deleteSession(_ id: UUID) {
        guard sessions.count > 1,
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let deletingActive = id == activeSessionID
        if deletingActive {
            prepareToLeaveCurrentSession()
            persistActiveSession(markEdited: false)
        }
        sessions.remove(at: index)
        storedVersions.removeAll { $0.sessionID == id }
        SessionVersionStore.save(storedVersions)
        versions = storedVersions.filter { $0.sessionID == activeSessionID }

        if deletingActive, let replacement = sessions.first {
            activateSession(replacement)
        } else {
            StudioSessionStorage.save(sessions: sessions, activeSessionID: activeSessionID)
        }
    }

    // MARK: - Session backup and import

    var isTransferringSession: Bool { sessionTransferProgress != nil }

    /// Reads the header of a backup so the name can be checked first.
    func inspectSessionArchive(at url: URL) throws -> SessionArchiveSummary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try SessionArchive.summary(at: url)
    }

    func sessionExists(named name: String) -> Bool {
        sessions.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Packs one session and its audio into a single file for sharing.
    func exportSession(_ id: UUID) {
        guard sessionTransferProgress == nil,
              let session = sessions.first(where: { $0.id == id }) else { return }

        sessionTransferError = nil
        sessionExportURL = nil
        sessionTransferProgress = 0
        sessionTransferTitle = "Packing session…"

        let url = SessionArchive.exportURL(for: session.name)
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try SessionArchive.export(session: session, to: url) { fraction in
                    Task { @MainActor in
                        self?.sessionTransferProgress = fraction
                        self?.sessionTransferTitle = fraction >= 1
                            ? "Preparing file…"
                            : "Packing audio · \(Int(fraction * 100))%"
                    }
                }
                await MainActor.run {
                    guard let self else { return }
                    self.sessionTransferProgress = nil
                    self.sessionTransferTitle = ""
                    self.sessionExportURL = url
                }
            } catch {
                await MainActor.run {
                    self?.sessionTransferProgress = nil
                    self?.sessionTransferTitle = ""
                    self?.sessionTransferError = (error as? LocalizedError)?.errorDescription
                        ?? "The session could not be packed."
                }
            }
        }
    }

    /// Unpacks a backup as a new session. With `keepBoth` a name collision
    /// becomes a copy; otherwise the existing session of that name is replaced.
    func importSessionArchive(from url: URL, keepBoth: Bool) {
        guard sessionTransferProgress == nil else { return }

        let scoped = url.startAccessingSecurityScopedResource()
        sessionTransferError = nil
        sessionTransferProgress = 0
        sessionTransferTitle = "Reading backup…"

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let summary = try SessionArchive.summary(at: url)
                let finalName: String = await MainActor.run { [weak self] in
                    guard let self else { return summary.sessionName }
                    if keepBoth, self.sessionExists(named: summary.sessionName) {
                        return self.uniqueSessionName(summary.sessionName)
                    }
                    return summary.sessionName
                }

                let imported = try SessionArchive.importSession(from: url, renameTo: finalName) { fraction in
                    Task { @MainActor in
                        self?.sessionTransferProgress = fraction
                        self?.sessionTransferTitle = fraction >= 1
                            ? "Finishing import…"
                            : "Unpacking audio · \(Int(fraction * 100))%"
                    }
                }

                await MainActor.run {
                    guard let self else { return }
                    if !keepBoth,
                       let existing = self.sessions.first(where: {
                           $0.name.caseInsensitiveCompare(summary.sessionName) == .orderedSame
                       }) {
                        self.sessions.removeAll { $0.id == existing.id }
                        self.storedVersions.removeAll { $0.sessionID == existing.id }
                        SessionVersionStore.save(self.storedVersions)
                    }
                    self.sessions.append(imported)
                    StudioSessionStorage.save(sessions: self.sessions, activeSessionID: imported.id)
                    self.activateSession(imported)
                    self.sessionTransferProgress = nil
                    self.sessionTransferTitle = ""
                }
            } catch {
                await MainActor.run {
                    self?.sessionTransferProgress = nil
                    self?.sessionTransferTitle = ""
                    self?.sessionTransferError = (error as? LocalizedError)?.errorDescription
                        ?? "The session could not be imported."
                }
            }

            if scoped { url.stopAccessingSecurityScopedResource() }
        }
    }

    func clearSessionExportURL() {
        sessionExportURL = nil
    }

    // MARK: - Session versions

    /// Captures the current state of a session as a version, unless it is
    /// identical to the newest one already stored.
    @discardableResult
    func saveVersionNow(sessionID: UUID? = nil, force: Bool = false) -> SessionVersion? {
        let targetID = sessionID ?? activeSessionID
        guard let session = sessions.first(where: { $0.id == targetID }) else { return nil }

        let latest = storedVersions
            .filter { $0.sessionID == targetID }
            .max(by: { $0.createdAt < $1.createdAt })
        if !force, let latest, isSameArrangement(latest.session, session) {
            return nil
        }

        let version = SessionVersion(
            id: UUID(),
            sessionID: targetID,
            createdAt: Date(),
            name: session.name,
            trackCount: session.tracks.count,
            duration: session.arrangementDuration,
            tempoBPM: session.tempoBPM,
            sectionCount: session.sections.count,
            session: session
        )
        storedVersions.insert(version, at: 0)
        pruneVersions(for: targetID)
        SessionVersionStore.save(storedVersions)
        if targetID == activeSessionID {
            versions = storedVersions.filter { $0.sessionID == activeSessionID }
        }
        return version
    }

    /// Records the current state a couple of seconds after the last edit.
    private func scheduleAutosave(for sessionID: UUID) {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveVersionNow(sessionID: sessionID)
        }
    }

    /// Restores a snapshot into the open session, keeping the current state
    /// as a version first so nothing is lost.
    func restoreVersion(_ id: UUID) {
        guard let version = storedVersions.first(where: { $0.id == id }) else { return }
        persistActiveSession(markEdited: false)
        saveVersionNow(force: true)
        prepareToLeaveCurrentSession()
        var restored = version.session
        restored.id = activeSessionID
        restored.name = version.name
        restored.lastEdited = Date()
        activateSession(restored)
    }

    /// Opens a snapshot as a new session, leaving the open one untouched.
    @discardableResult
    func duplicateVersion(_ id: UUID) -> UUID? {
        guard let version = storedVersions.first(where: { $0.id == id }) else { return nil }
        persistActiveSession(markEdited: false)
        var copy = version.session
        copy.id = UUID()
        copy.name = uniqueSessionName("\(version.name) Copy")
        copy.lastEdited = Date()
        sessions.append(copy)
        StudioSessionStorage.save(sessions: sessions, activeSessionID: activeSessionID)
        activateSession(copy)
        return copy.id
    }

    private func pruneVersions(for sessionID: UUID) {
        let mine = storedVersions.filter { $0.sessionID == sessionID }
        guard mine.count > SessionVersionStore.maximumPerSession else { return }
        let keep = Set(mine.prefix(SessionVersionStore.maximumPerSession).map(\.id))
        storedVersions.removeAll { $0.sessionID == sessionID && !keep.contains($0.id) }
    }

    private func isSameArrangement(_ left: StudioSession, _ right: StudioSession) -> Bool {
        var a = left
        var b = right
        a.lastEdited = b.lastEdited
        return a == b
    }

    private func persistActiveSession(markEdited: Bool = true) {
        guard let index = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        sessions[index].name = sessionName
        sessions[index].templateID = activeTemplateID
        sessions[index].tracks = tracks
        sessions[index].groups = groups
        sessions[index].tempoBPM = tempoBPM
        sessions[index].drumPattern = drumPattern
        sessions[index].drumKit = drumKit
        sessions[index].loopStart = loopStart
        sessions[index].loopEnd = loopEnd
        sessions[index].isLoopEnabled = isLoopEnabled
        sessions[index].masterVolume = masterVolume
        sessions[index].masterEffects = masterEffects
        sessions[index].mastering = mastering
        sessions[index].auxBusA = auxBusA
        sessions[index].auxBusB = auxBusB
        sessions[index].sections = sections
        sessions[index].isMetronomeEnabled = isMetronomeEnabled
        sessions[index].metronomeLevel = metronomeLevel
        sessions[index].isCountInEnabled = isCountInEnabled
        sessions[index].punchIn = punchIn
        sessions[index].punchOut = punchOut
        sessions[index].isPunchEnabled = isPunchEnabled
        sessions[index].armedTrackID = armedTrackID
        if markEdited {
            sessions[index].lastEdited = Date()
        }
        StudioSessionStorage.save(sessions: sessions, activeSessionID: activeSessionID)
        scheduleAutosave(for: activeSessionID)
    }

    private func prepareToLeaveCurrentSession() {
        stopDrumSequencer()
        if isRecordingInstrument {
            stopInstrumentRecording()
        }
        engine.stop()
        isPlaying = false
        currentTime = 0
        levels = [:]
    }

    private func activateSession(_ session: StudioSession) {
        activeSessionID = session.id
        versions = storedVersions.filter { $0.sessionID == session.id }
        sessionName = session.name
        activeTemplateID = session.templateID
        tracks = session.tracks
        groups = session.groups
        tempoBPM = min(200, max(60, session.tempoBPM))
        drumPattern = session.drumPattern
        drumKit = session.drumKit
        loopStart = max(0, session.loopStart)
        loopEnd = max(loopStart, session.loopEnd)
        isLoopEnabled = session.isLoopEnabled
        masterVolume = min(1, max(0, session.masterVolume))
        masterEffects = session.masterEffects
        mastering = session.mastering
        auxBusA = session.auxBusA
        auxBusB = session.auxBusB
        sections = session.sections
        isMetronomeEnabled = session.isMetronomeEnabled
        metronomeLevel = min(1, max(0, session.metronomeLevel))
        isCountInEnabled = session.isCountInEnabled
        punchIn = max(0, session.punchIn)
        punchOut = max(punchIn, session.punchOut)
        isPunchEnabled = session.isPunchEnabled
        armedTrackID = session.armedTrackID
        pendingUndoSnapshot = nil
        undoStack.removeAll()
        redoStack.removeAll()
        updateHistoryAvailability()
        scrubTime = nil
        resolveClipMetadata()
        engine.load(tracks: tracks)
        duration = engine.duration
        applyLoopChangeToEngine()
        engine.setMasterVolume(masterVolume)
        engine.setTempo(tempoBPM)
        engine.updateMasterEffects(masterEffects, tempoBPM: tempoBPM)
        engine.updateMasterChain(mastering)
        engine.setMetronome(enabled: isMetronomeEnabled, level: metronomeLevel)
        isPlaying = false
        currentTime = 0
        loadWaveforms()
        persistActiveSession(markEdited: false)
    }

    private func uniqueSessionName(_ proposed: String) -> String {
        let base = proposed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Session" : proposed
        var candidate = base
        var suffix = 2
        while sessions.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    func undo() {
        finishUndoableEdit()
        guard let previous = undoStack.popLast() else {
            updateHistoryAvailability()
            return
        }
        redoStack.append(makeUndoSnapshot())
        restoreUndoableState(previous)
        updateHistoryAvailability()
    }

    func redo() {
        finishUndoableEdit()
        guard let next = redoStack.popLast() else {
            updateHistoryAvailability()
            return
        }
        undoStack.append(makeUndoSnapshot())
        restoreUndoableState(next)
        updateHistoryAvailability()
    }

    private func beginUndoableEdit() {
        if pendingUndoSnapshot == nil {
            pendingUndoSnapshot = makeUndoSnapshot()
        }
    }

    private func finishUndoableEdit() {
        guard let before = pendingUndoSnapshot else { return }
        pendingUndoSnapshot = nil
        let after = makeUndoSnapshot()
        guard before != after else {
            updateHistoryAvailability()
            return
        }
        undoStack.append(before)
        if undoStack.count > historyLimit {
            undoStack.removeFirst(undoStack.count - historyLimit)
        }
        redoStack.removeAll()
        updateHistoryAvailability()
    }

    private func makeUndoSnapshot() -> [UndoTrackState] {
        tracks.map {
            UndoTrackState(
                id: $0.id,
                clips: $0.clips,
                volume: $0.volume,
                isMuted: $0.isMuted,
                isSoloed: $0.isSoloed,
                volumeAutomationPoints: $0.volumeAutomationPoints,
                panAutomationPoints: $0.panAutomationPoints,
                notes: $0.notes
            )
        }
    }

    private func restoreUndoableState(_ snapshot: [UndoTrackState]) {
        let wasPlaying = isPlaying
        let resumeTime = engine.currentTime
        for state in snapshot {
            guard let index = tracks.firstIndex(where: { $0.id == state.id }) else { continue }
            tracks[index].clips = state.clips
            tracks[index].volume = state.volume
            tracks[index].isMuted = state.isMuted
            tracks[index].isSoloed = state.isSoloed
            tracks[index].volumeAutomationPoints = state.volumeAutomationPoints
            tracks[index].panAutomationPoints = state.panAutomationPoints
            tracks[index].notes = state.notes
        }

        engine.load(tracks: tracks)
        duration = engine.duration
        applyLoopChangeToEngine()
        currentTime = duration > 0 ? min(max(0, resumeTime), duration) : max(0, resumeTime)
        engine.seek(to: currentTime)
        if wasPlaying { engine.play() }
        isPlaying = engine.isPlaying
        currentTime = engine.currentTime
        loadWaveforms()
        persistActiveSession()
    }

    private func updateHistoryAvailability() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func setTempo(_ bpm: Int) {
        let clamped = min(200, max(60, bpm))
        guard clamped != tempoBPM else { return }
        tempoBPM = clamped
        engine.setTempo(clamped)
        engine.updateMasterEffects(masterEffects, tempoBPM: clamped)
        persistActiveSession()
    }

    func adjustTempo(by amount: Int) {
        setTempo(tempoBPM + amount)
    }

    func playSynthNote(
        frequency: Double,
        waveform: SynthWaveform,
        cutoff: Double,
        attack: Double,
        release: Double,
        destinationTrackID: UUID?
    ) {
        guard let format = engine.instrumentFormat(for: destinationTrackID),
              let buffer = InstrumentSoundGenerator.synthNote(
                frequency: frequency,
                waveform: waveform,
                cutoff: cutoff,
                attack: attack,
                release: release,
                format: format
              ) else { return }
        engine.playInstrumentBuffer(buffer, destinationTrackID: destinationTrackID)
    }

    func playDrumPad(
        _ pad: DrumPad,
        destinationTrackID: UUID?,
        volume: Double = 1,
        tuning: Double = 1,
        decay: Double = 1,
        tone: Double = 0.6
    ) {
        let kit = drumKit
        guard let format = engine.instrumentFormat(for: destinationTrackID),
              let buffer = InstrumentSoundGenerator.drumHit(
                pad,
                volume: volume * kit.level,
                tuning: tuning * kit.tuning,
                decay: decay * kit.decay,
                tone: tone * 0.35 + kit.tone * 0.65,
                format: format
              ) else { return }
        engine.playInstrumentBuffer(buffer, destinationTrackID: destinationTrackID)
    }

    func toggleDrumStep(_ pad: DrumPad, step: Int) {
        guard (0..<DrumPattern.stepCount).contains(step) else { return }
        drumPattern.toggle(pad, step: step)
        persistActiveSession()
    }

    /// Whether the full depth of the studio is on show.
    var isProMode: Bool { studioMode == .pro }

    /// Switches between the simple and full studio surfaces, remembered per device.
    func setStudioMode(_ mode: StudioMode) {
        guard mode != studioMode else { return }
        studioMode = mode
        StudioModeStorage.save(mode)
    }

    /// Switches the kit that voices the session's drum pattern.
    func setDrumKit(_ drumKit: DrumKit) {
        guard drumKit != self.drumKit else { return }
        self.drumKit = drumKit
        persistActiveSession()
    }

    func startDrumSequencer(
        destinationTrackID: UUID?,
        volume: Double = 1,
        tuning: Double = 1,
        decay: Double = 1,
        tone: Double = 0.6
    ) {
        guard !isDrumSequencerPlaying else { return }
        if !isPlaying { beginPlayback() }

        isDrumSequencerPlaying = true
        let wallStart = Date()
        let timelineStart = engine.currentTime
        drumSequencerTask = Task { @MainActor [weak self] in
            var previousAbsoluteStep: Int?

            while !Task.isCancelled {
                guard let self, self.isDrumSequencerPlaying else { break }
                let stepDuration = 60.0 / Double(self.tempoBPM) / 4
                let time = self.isPlaying
                    ? self.engine.currentTime
                    : timelineStart + Date().timeIntervalSince(wallStart)
                let absoluteStep = max(0, Int(floor(time / stepDuration)))

                if absoluteStep != previousAbsoluteStep {
                    previousAbsoluteStep = absoluteStep
                    let step = absoluteStep % DrumPattern.stepCount
                    self.currentDrumStep = step
                    for pad in DrumPad.allCases where self.drumPattern.contains(pad, step: step) {
                        self.playDrumPad(
                            pad,
                            destinationTrackID: destinationTrackID,
                            volume: volume,
                            tuning: tuning,
                            decay: decay,
                            tone: tone
                        )
                    }
                }

                try? await Task.sleep(for: .milliseconds(5))
            }

            self?.currentDrumStep = nil
        }
    }

    func stopDrumSequencer() {
        drumSequencerTask?.cancel()
        drumSequencerTask = nil
        isDrumSequencerPlaying = false
        currentDrumStep = nil
    }

    func playTB303Note(
        frequency: Double,
        waveform: TB303Waveform,
        cutoff: Double,
        resonance: Double,
        envelopeAmount: Double,
        decay: Double,
        accent: Bool,
        tuning: Double = 1,
        level: Double = 1,
        destinationTrackID: UUID?
    ) {
        guard let format = engine.instrumentFormat(for: destinationTrackID),
              let buffer = InstrumentSoundGenerator.tb303Note(
                frequency: frequency,
                waveform: waveform,
                cutoff: cutoff,
                resonance: resonance,
                envelopeAmount: envelopeAmount,
                decay: decay,
                accent: accent,
                tuning: tuning,
                level: level,
                format: format
              ) else { return }
        engine.playInstrumentBuffer(buffer, destinationTrackID: destinationTrackID, monophonic: true)
    }

    func loadSampler(from url: URL) {
        do {
            let imported = try TrackStorage.importFile(at: url)
            samplerFileURL = TrackStorage.url(forFileName: imported.storedName)
            samplerDisplayName = imported.displayName
            samplerError = nil
            refreshSampleLibrary()
        } catch {
            samplerError = "The selected audio file could not be loaded."
        }
    }

    func playSampler(destinationTrackID: UUID?) {
        guard let samplerFileURL else { return }
        engine.playInstrumentFile(at: samplerFileURL, destinationTrackID: destinationTrackID)
    }

    func clearSamplerError() {
        samplerError = nil
    }

    // MARK: - Sample library

    /// The library sound the sampler currently holds, when it came from the library.
    var loadedSampleFileName: String? {
        samplerFileURL?.lastPathComponent
    }

    /// Reads the audio files stored on device for the sample library.
    func refreshSampleLibrary() {
        guard !isLoadingSampleLibrary else { return }
        isLoadingSampleLibrary = true

        Task { [weak self] in
            let items = await Task.detached(priority: .userInitiated) {
                SampleLibrary.scan()
            }.value

            guard let self else { return }
            self.sampleLibrary = items
            self.isLoadingSampleLibrary = false

            if let previewingSampleID = self.previewingSampleID,
               !items.contains(where: { $0.id == previewingSampleID }) {
                self.stopSamplePreview()
            }
        }
    }

    /// Plays a short preview of a library sound on the master output.
    func previewSample(_ item: SampleLibraryItem) {
        if previewingSampleID == item.id {
            stopSamplePreview()
            return
        }

        guard FileManager.default.fileExists(atPath: item.url.path) else {
            samplerError = "That sound is no longer in the library."
            refreshSampleLibrary()
            return
        }

        samplePreviewTask?.cancel()
        engine.stopPreviews()
        engine.playInstrumentFile(at: item.url, destinationTrackID: nil)
        previewingSampleID = item.id

        let previewLength = min(max(item.duration, 0.6), 12)
        samplePreviewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(previewLength))
            guard !Task.isCancelled else { return }
            self?.stopSamplePreview()
        }
    }

    func stopSamplePreview() {
        samplePreviewTask?.cancel()
        samplePreviewTask = nil
        previewingSampleID = nil
        engine.stopPreviews()
    }

    /// Points the sampler at a sound already stored on device.
    func loadSamplerSample(_ item: SampleLibraryItem) {
        guard FileManager.default.fileExists(atPath: item.url.path) else {
            samplerError = "That sound is no longer in the library."
            refreshSampleLibrary()
            return
        }
        stopSamplePreview()
        samplerFileURL = item.url
        samplerDisplayName = item.name
        samplerError = nil
    }

    func requestMicrophonePermission() {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            microphonePermissionGranted = true
            microphoneError = nil
        case .denied:
            microphonePermissionGranted = false
            microphoneError = "Microphone access is disabled. Allow it in Settings to record a take."
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                Task { @MainActor [weak self] in
                    self?.microphonePermissionGranted = granted
                    self?.microphoneError = granted ? nil : "Microphone access is needed to record a take."
                }
            }
        @unknown default:
            microphonePermissionGranted = false
            microphoneError = "Microphone access is unavailable on this device."
        }
    }

    func clearMicrophoneError() {
        microphoneError = nil
    }

    func startInstrumentRecording(destinationTrackID: UUID?) {
        guard let trackID = destinationTrackID,
              tracks.contains(where: { $0.id == trackID }) else {
            recordingError = InstrumentRecordingError.destinationUnavailable.localizedDescription
            return
        }
        guard !isRecordingInstrument else { return }

        let outputURL = TrackStorage.uniqueStemURL(baseName: "instrument-take", fileExtension: "caf")
        do {
            try engine.startInstrumentRecording(trackID: trackID, outputURL: outputURL)
        } catch {
            recordingError = (error as? LocalizedError)?.errorDescription ?? "Recording could not start."
            return
        }

        if !isPlaying {
            beginPlayback()
        }
        recordingStartTime = engine.currentTime
        recordingElapsed = 0
        isRecordingInstrument = true
        recordingError = nil
    }

    func startMicrophoneRecording(destinationTrackID: UUID?) {
        guard microphonePermissionGranted else {
            requestMicrophonePermission()
            return
        }
        guard let trackID = destinationTrackID,
              tracks.contains(where: { $0.id == trackID }) else {
            recordingError = InstrumentRecordingError.destinationUnavailable.localizedDescription
            return
        }
        guard !isRecordingInstrument else { return }

        let outputURL = TrackStorage.uniqueStemURL(baseName: "microphone-take", fileExtension: "caf")
        do {
            try engine.startMicrophoneRecording(trackID: trackID, outputURL: outputURL)
        } catch {
            recordingError = (error as? LocalizedError)?.errorDescription ?? "Microphone recording could not start."
            return
        }

        if !isPlaying {
            beginPlayback()
        }
        recordingStartTime = engine.currentTime
        recordingElapsed = 0
        isRecordingInstrument = true
        recordingError = nil
        microphoneError = nil
    }

    func stopInstrumentRecording() {
        guard isRecordingInstrument else { return }
        let wasPlaying = isPlaying
        let resumeTime = engine.currentTime
        let take = engine.finishInstrumentRecording()
        isRecordingInstrument = false

        guard let take,
              let index = tracks.firstIndex(where: { $0.id == take.trackID }) else {
            recordingError = InstrumentRecordingError.noAudioCaptured.localizedDescription
            return
        }

        if isPunchActive(for: take.trackID),
           let punchedLength = applyPunch(take: take) {
            recordingElapsed = punchedLength
        } else {
            registerTake(
                trackID: take.trackID,
                fileName: take.url.lastPathComponent,
                startTime: recordingStartTime,
                duration: take.duration,
                name: "Take"
            )
            recordingElapsed = take.duration
        }
        engine.load(tracks: tracks)
        duration = engine.duration
        currentTime = min(max(0, resumeTime), duration)
        engine.seek(to: currentTime)
        if wasPlaying {
            engine.play()
        }
        isPlaying = engine.isPlaying
        currentTime = engine.currentTime
        loadWaveforms()
        commitSession()
    }

    func clearRecordingError() {
        recordingError = nil
    }

    // MARK: - Clip fades

    /// Sets the fade lengths on a clip; overlapping clips crossfade automatically.
    func setClipFades(trackID: UUID, clipID: UUID, fadeIn: TimeInterval, fadeOut: TimeInterval) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let clipIndex = tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) else { return }
        let duration = tracks[trackIndex].clips[clipIndex].duration
        tracks[trackIndex].clips[clipIndex].fadeIn = min(max(0, fadeIn), max(0, duration - 0.01))
        tracks[trackIndex].clips[clipIndex].fadeOut = min(max(0, fadeOut), max(0, duration - tracks[trackIndex].clips[clipIndex].fadeIn - 0.01))
        engine.updateMix(tracks: tracks)
        commitSession()
    }

    // MARK: - Take lane
    @Published private(set) var auditioningTakeID: UUID?
    private var takeAuditionPlayer: AVAudioPlayer?

    /// Adds a recorded pass to the take lane and places it on the timeline,
    /// leaving the previous active take in the lane untouched.
    private func registerTake(
        trackID: UUID,
        fileName: String,
        startTime: TimeInterval,
        duration: TimeInterval,
        name: String
    ) {
        guard duration > 0,
              let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }

        var track = tracks[index]
        let take = TrackTake(
            name: "\(name) \(track.takes.count + 1)",
            fileName: fileName,
            startTime: max(0, startTime),
            duration: duration
        )
        if let previous = track.activeTakeID {
            track.clips.removeAll { $0.takeID == previous }
        }
        track.takes.append(take)
        track.activeTakeID = take.id
        track.clips.append(clip(for: take))
        track.clips.sort { $0.startTime < $1.startTime }
        tracks[index] = track
    }

    /// Auditions a take without changing the arrangement.
    func auditionTake(trackID: UUID, takeID: UUID) {
        guard let track = tracks.first(where: { $0.id == trackID }),
              let take = track.takes.first(where: { $0.id == takeID }) else { return }

        stopTakeAudition()
        let url = TrackStorage.url(forFileName: take.fileName)
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        takeAuditionPlayer = player
        auditioningTakeID = takeID
        player.play()

        let duration = take.duration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.3, duration)))
            guard let self, self.takeAuditionPlayer === player else { return }
            self.stopTakeAudition()
        }
    }

    func stopTakeAudition() {
        takeAuditionPlayer?.stop()
        takeAuditionPlayer = nil
        auditioningTakeID = nil
    }

    /// Puts a take from the lane on the timeline, replacing the active one.
    func promoteTake(trackID: UUID, takeID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }),
              let take = tracks[index].takes.first(where: { $0.id == takeID }),
              tracks[index].activeTakeID != takeID else { return }

        var track = tracks[index]
        if let previous = track.activeTakeID {
            track.clips.removeAll { $0.takeID == previous }
        }
        track.activeTakeID = takeID
        track.clips.append(clip(for: take))
        track.clips.sort { $0.startTime < $1.startTime }
        tracks[index] = track
        refreshAfterTakeChange()
        commitSession()
    }

    func renameTake(trackID: UUID, takeID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = tracks.firstIndex(where: { $0.id == trackID }),
              let takeIndex = tracks[index].takes.firstIndex(where: { $0.id == takeID }) else { return }

        tracks[index].takes[takeIndex].name = trimmed
        for clipIndex in tracks[index].clips.indices where tracks[index].clips[clipIndex].takeID == takeID {
            tracks[index].clips[clipIndex].name = trimmed
        }
        commitSession()
    }

    /// Removes a take from the lane, promoting the next best take if it was active.
    func deleteTake(trackID: UUID, takeID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }),
              tracks[index].takes.contains(where: { $0.id == takeID }) else { return }

        var track = tracks[index]
        let wasActive = track.activeTakeID == takeID
        track.takes.removeAll { $0.id == takeID }

        if wasActive {
            track.clips.removeAll { $0.takeID == takeID }
            if let fallback = track.takes.last {
                track.activeTakeID = fallback.id
                track.clips.append(clip(for: fallback))
                track.clips.sort { $0.startTime < $1.startTime }
            } else {
                track.activeTakeID = nil
            }
        }

        tracks[index] = track
        if auditioningTakeID == takeID {
            stopTakeAudition()
        }
        refreshAfterTakeChange()
        commitSession()
    }

    private func clip(for take: TrackTake) -> AudioClip {
        AudioClip(
            name: take.name,
            fileName: take.fileName,
            startTime: take.startTime,
            duration: take.duration,
            sourceStartTime: 0,
            sourceDuration: take.duration,
            takeID: take.id
        )
    }

    private func refreshAfterTakeChange() {
        engine.load(tracks: tracks)
        duration = engine.duration
        currentTime = min(currentTime, duration)
        loadWaveforms()
    }

    func bounceMix(settings: BounceSettings) {
        guard !isBouncing else { return }
        bounceSettings = settings
        BounceSettingsStorage.save(settings)
        isBouncing = true
        isStemBounce = false
        bounceProgress = 0
        bounceStatus = "Preparing mix…"
        bounceError = nil
        lastExportURL = nil

        let outputURL = MixExportStorage.exportURL(name: settings.fileName, fileExtension: settings.format.fileExtension)
        let tracksToBounce = tracks
        let groupsToBounce = groups
        let masterVolumeToBounce = masterVolume
        let masterEffectsToBounce = masterEffects
        let masteringToBounce = mastering
        let auxBusAToBounce = auxBusA
        let auxBusBToBounce = auxBusB
        let tempoToBounce = tempoBPM
        let settingsToBounce = settings
        let progressUpdate: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor [weak self] in
                self?.bounceProgress = fraction
                self?.bounceStatus = fraction >= 1 ? "Finishing export…" : "Rendering mix · \(Int(fraction * 100))%"
            }
        }

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try MixBounceRenderer.render(
                        tracks: tracksToBounce,
                        groups: groupsToBounce,
                        masterVolume: masterVolumeToBounce,
                        masterEffects: masterEffectsToBounce,
                        mastering: masteringToBounce,
                        auxBusA: auxBusAToBounce,
                        auxBusB: auxBusBToBounce,
                        tempoBPM: tempoToBounce,
                        settings: settingsToBounce,
                        to: outputURL,
                        progress: progressUpdate
                    )
                }.value
                refreshExports()
                lastExportURL = outputURL
                bounceProgress = 1
                bounceStatus = "Bounce complete"
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                bounceError = (error as? LocalizedError)?.errorDescription ?? "The mix could not be bounced."
                bounceStatus = "Bounce failed"
            }
            isBouncing = false
        }
    }

    /// Renders every track as its own stem, through its mixer settings and the master.
    func bounceStems(settings: BounceSettings) {
        guard !isBouncing else { return }

        let tracksToRender = tracks.filter { audibleDuration(of: $0) > 0 }
        guard !tracksToRender.isEmpty else {
            bounceError = "There are no tracks with audio or notes to export."
            return
        }

        bounceSettings = settings
        BounceSettingsStorage.save(settings)
        isBouncing = true
        isStemBounce = true
        bounceProgress = 0
        bounceStatus = "Preparing stems…"
        bounceError = nil
        lastExportURL = nil

        let master = masterVolume
        let effects = masterEffects
        let chain = mastering
        let tempo = tempoBPM
        let baseName = settings.fileName
        let settingsToBounce = settings
        let groupsToBounce = groups

        Task {
            do {
                var lastURL: URL?
                for (index, track) in tracksToRender.enumerated() {
                    let stemURL = MixExportStorage.exportURL(
                        name: "\(baseName)-\(track.name)",
                        fileExtension: settings.format.fileExtension
                    )
                    let progressUpdate: @Sendable (Double) -> Void = { [weak self] fraction in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.bounceProgress = (Double(index) + min(1, max(0, fraction))) / Double(tracksToRender.count)
                            self.bounceStatus = fraction >= 1
                                ? "Saving \(track.name)…"
                                : "Rendering \(track.name) · \(Int(fraction * 100))%"
                        }
                    }

                    try await Task.detached(priority: .userInitiated) {
                        try MixBounceRenderer.renderStem(
                            track: track,
                            groups: groupsToBounce,
                            masterVolume: master,
                            masterEffects: effects,
                            mastering: chain,
                            tempoBPM: tempo,
                            settings: settingsToBounce,
                            to: stemURL,
                            progress: progressUpdate
                        )
                    }.value

                    lastURL = stemURL
                }

                refreshExports()
                lastExportURL = lastURL
                bounceProgress = 1
                bounceStatus = "Stems complete"
            } catch {
                bounceError = (error as? LocalizedError)?.errorDescription ?? "The stems could not be bounced."
                bounceStatus = "Bounce failed"
            }
            isBouncing = false
            isStemBounce = false
        }
    }

    private func audibleDuration(of track: Track) -> TimeInterval {
        let clipEnd = track.playbackClips.map { clip in
            max(0, clip.startTime) + min(clip.duration, max(0, clip.sourceDuration - clip.sourceStartTime))
        }.max() ?? 0
        let noteEnd = track.playedNotes(tempoBPM: tempoBPM).map(\.endTime).max() ?? 0
        return max(clipEnd, noteEnd)
    }

    func refreshExports() {
        exports = MixExportStorage.loadExports()
    }

    func clearFreezeError() {
        freezeError = nil
    }

    /// Freezes a track into one rendered clip, or restores its source arrangement.
    func toggleFreeze(trackID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }), !isFreezingTrack else { return }
        if tracks[index].isFrozen {
            unfreezeTrack(at: index)
        } else {
            freezeTrack(at: index)
        }
    }

    private func unfreezeTrack(at index: Int) {
        let wasPlaying = isPlaying
        let resumeTime = engine.currentTime
        tracks[index].frozenFileName = nil
        tracks[index].frozenDuration = 0
        reloadEngine()
        if wasPlaying {
            resumePlayback(after: resumeTime)
        }
        commitSession()
    }

    private func freezeTrack(at index: Int) {
        let track = tracks[index]
        let outputURL = TrackStorage.uniqueStemURL(baseName: "\(track.name)-freeze", fileExtension: "wav")
        let freezeTempo = tempoBPM
        let wasPlaying = isPlaying
        let resumeTime = engine.currentTime

        isFreezingTrack = true
        freezeStatus = "Freezing \(track.name)…"
        freezeError = nil
        if wasPlaying { pause() }

        Task { [weak self] in
            do {
                let duration = try await Task.detached(priority: .userInitiated) {
                    try TrackFreezeRenderer.render(track: track, tempoBPM: freezeTempo, to: outputURL)
                }.value

                guard let self,
                      let currentIndex = self.tracks.firstIndex(where: { $0.id == track.id }) else { return }
                self.tracks[currentIndex].frozenFileName = outputURL.lastPathComponent
                self.tracks[currentIndex].frozenDuration = duration
                self.reloadEngine()
                if wasPlaying {
                    self.resumePlayback(after: resumeTime)
                }
                self.freezeStatus = "Frozen \(track.name)"
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                self?.freezeError = (error as? LocalizedError)?.errorDescription ?? "The track could not be frozen."
                self?.freezeStatus = ""
            }
            self?.isFreezingTrack = false
        }
    }

    private func resumePlayback(after time: TimeInterval) {
        let position = duration > 0 ? min(max(0, time), duration) : max(0, time)
        currentTime = position
        engine.seek(to: position)
        beginPlayback()
    }

    func clearBounceError() {
        bounceError = nil
    }

    func moveClip(trackID: UUID, clipID: UUID, to proposedStartTime: TimeInterval, snapInterval: TimeInterval) {
        guard let location = clipLocation(trackID: trackID, clipID: clipID) else { return }
        beginUndoableEdit()
        tracks[location.track].clips[location.clip].startTime = snappedTime(proposedStartTime, interval: snapInterval)
    }

    func trimClipStart(
        trackID: UUID,
        clipID: UUID,
        original: AudioClip,
        to proposedStartTime: TimeInterval,
        snapInterval: TimeInterval
    ) {
        guard let location = clipLocation(trackID: trackID, clipID: clipID) else { return }
        let minimumStart = max(0, original.startTime - original.sourceStartTime)
        let latestStart = original.startTime + original.duration - 0.05
        guard latestStart >= minimumStart else { return }

        let newStart = min(max(minimumStart, snappedTime(proposedStartTime, interval: snapInterval)), latestStart)
        let delta = newStart - original.startTime
        var clip = original
        clip.startTime = newStart
        clip.sourceStartTime = max(0, original.sourceStartTime + delta)
        clip.duration = original.duration - delta
        beginUndoableEdit()
        tracks[location.track].clips[location.clip] = clip
    }

    func trimClipEnd(
        trackID: UUID,
        clipID: UUID,
        original: AudioClip,
        to proposedEndTime: TimeInterval,
        snapInterval: TimeInterval
    ) {
        guard let location = clipLocation(trackID: trackID, clipID: clipID) else { return }
        let minimumDuration = min(0.05, original.duration)
        let maximumDuration = max(0, original.sourceDuration - original.sourceStartTime)
        guard maximumDuration >= minimumDuration else { return }

        let snappedEnd = snappedTime(proposedEndTime, interval: snapInterval)
        let newEnd = min(max(original.startTime + minimumDuration, snappedEnd), original.startTime + maximumDuration)
        var clip = original
        clip.duration = newEnd - original.startTime
        beginUndoableEdit()
        tracks[location.track].clips[location.clip] = clip
    }

    func splitClip(trackID: UUID, clipID: UUID, at time: TimeInterval, snapInterval: TimeInterval) -> UUID? {
        guard let location = clipLocation(trackID: trackID, clipID: clipID) else { return nil }
        let clip = tracks[location.track].clips[location.clip]
        let splitTime = snappedTime(time, interval: snapInterval)
        let splitOffset = splitTime - clip.startTime
        guard splitOffset >= 0.05, splitOffset <= clip.duration - 0.05 else { return nil }

        beginUndoableEdit()
        var left = clip
        left.duration = splitOffset

        var right = clip
        right.id = UUID()
        right.name = "\(clip.name) B"
        right.startTime = splitTime
        right.sourceStartTime = clip.sourceStartTime + splitOffset
        right.duration = clip.duration - splitOffset

        tracks[location.track].clips[location.clip] = left
        tracks[location.track].clips.insert(right, at: location.clip + 1)
        commitClipChanges()
        return right.id
    }

    func duplicateClip(trackID: UUID, clipID: UUID, snapInterval: TimeInterval) -> UUID? {
        guard let location = clipLocation(trackID: trackID, clipID: clipID) else { return nil }
        beginUndoableEdit()
        var duplicate = tracks[location.track].clips[location.clip]
        duplicate.id = UUID()
        duplicate.name = "\(duplicate.name) Copy"
        duplicate.startTime = snappedTime(duplicate.startTime + duplicate.duration, interval: snapInterval)
        tracks[location.track].clips.insert(duplicate, at: location.clip + 1)
        commitClipChanges()
        return duplicate.id
    }

    func deleteClip(trackID: UUID, clipID: UUID) {
        guard let location = clipLocation(trackID: trackID, clipID: clipID) else { return }
        beginUndoableEdit()
        tracks[location.track].clips.remove(at: location.clip)
        commitClipChanges()
    }

    func commitClipChanges() {
        finishUndoableEdit()
        resolveClipMetadata()
        let wasPlaying = isPlaying
        let resumeTime = engine.currentTime
        engine.load(tracks: tracks)
        duration = engine.duration
        currentTime = min(max(0, resumeTime), duration)
        engine.seek(to: currentTime)
        if wasPlaying {
            engine.play()
        }
        isPlaying = engine.isPlaying
        currentTime = engine.currentTime
        loadWaveforms()
        commitSession()
    }

    func toggleMute(_ id: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        beginUndoableEdit()
        tracks[index].isMuted.toggle()
        engine.updateMix(tracks: tracks)
        commitSession()
    }

    func toggleSolo(_ id: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        beginUndoableEdit()
        tracks[index].isSoloed.toggle()
        engine.updateMix(tracks: tracks)
        commitSession()
    }

    func setMuted(_ id: UUID, _ isMuted: Bool) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        beginUndoableEdit()
        tracks[index].isMuted = isMuted
        engine.updateMix(tracks: tracks)
        commitSession()
    }

    func setSoloed(_ id: UUID, _ isSoloed: Bool) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        beginUndoableEdit()
        tracks[index].isSoloed = isSoloed
        engine.updateMix(tracks: tracks)
        commitSession()
    }

    // MARK: - Track groups

    /// The group a track belongs to, when it has been put in one.
    func group(forTrack trackID: UUID) -> TrackGroup? {
        groups.first { $0.trackIDs.contains(trackID) }
    }

    /// The colour slot a new group should take.
    var nextGroupColorIndex: Int {
        let used = Set(groups.map(\.colorIndex))
        return (0..<4).first { !used.contains($0) } ?? groups.count % 4
    }

    /// Puts tracks in a new named bus and returns its id.
    @discardableResult
    func createGroup(name: String, colorIndex: Int, trackIDs: [UUID]) -> UUID? {
        let members = trackIDs.filter { trackID in tracks.contains { $0.id == trackID } }
        guard !members.isEmpty else { return nil }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupName = trimmed.isEmpty ? "Group \(groups.count + 1)" : trimmed

        // A track belongs to one bus, so take its members out of any other.
        for index in groups.indices {
            groups[index].trackIDs.removeAll { members.contains($0) }
        }
        groups.removeAll { $0.trackIDs.isEmpty }

        let group = TrackGroup(
            name: groupName,
            colorIndex: min(3, max(0, colorIndex)),
            trackIDs: members
        )
        groups.append(group)
        applyGroups()
        return group.id
    }

    func renameGroup(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = trimmed
        applyGroups()
    }

    /// Removes a bus, leaving its tracks in the session.
    func deleteGroup(_ id: UUID) {
        guard groups.contains(where: { $0.id == id }) else { return }
        groups.removeAll { $0.id == id }
        applyGroups()
    }

    func setGroupVolume(_ id: UUID, _ value: Float) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].volume = min(1, max(0, value))
        engine.updateGroups(groups)
    }

    func toggleGroupMute(_ id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].isMuted.toggle()
        applyGroups()
    }

    func toggleGroupSolo(_ id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].isSoloed.toggle()
        applyGroups()
    }

    private func applyGroups() {
        engine.updateGroups(groups)
        persistActiveSession()
    }

    /// Finds a track by fuzzy name match (used by the agent chat).
    func track(named name: String) -> Track? {
        let needle = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let exact = tracks.first(where: { $0.name.lowercased() == needle }) { return exact }
        return tracks.first(where: {
            $0.name.lowercased().contains(needle) || needle.contains($0.name.lowercased())
        })
    }

    func togglePlay() {
        if isPlaying || isCountingIn {
            pause()
        } else {
            play()
        }
    }

    func play() {
        if isCountInEnabled, !isCountingIn, !isPlaying {
            startCountIn()
            return
        }
        beginPlayback()
    }

    private func beginPlayback() {
        countInTask?.cancel()
        countInTask = nil
        isCountingIn = false
        countInBeatsRemaining = 0

        engine.play()
        isPlaying = engine.isPlaying
        currentTime = engine.currentTime

        if let startError = engine.lastStartError {
            audioError = "Audio could not start: \(startError)"
        } else if isPlaying {
            audioError = nil
        }
    }

    private func startCountIn() {
        let beats = 4
        countInTask?.cancel()

        guard let length = engine.playCountIn(beats: beats) else {
            beginPlayback()
            return
        }

        isCountingIn = true
        countInBeatsRemaining = beats

        let beatLength = length / Double(beats)
        countInTask = Task { @MainActor [weak self] in
            for beat in 1..<beats {
                try? await Task.sleep(for: .seconds(beatLength))
                guard let self, self.isCountingIn else { return }
                self.countInBeatsRemaining = beats - beat
            }
            try? await Task.sleep(for: .seconds(beatLength))
            guard let self, self.isCountingIn else { return }
            self.beginPlayback()
        }
    }

    private func cancelCountIn() {
        countInTask?.cancel()
        countInTask = nil
        guard isCountingIn else { return }
        isCountingIn = false
        countInBeatsRemaining = 0
        engine.silenceMetronome()
    }

    func pause() {
        cancelCountIn()
        stopDrumSequencer()
        if isRecordingInstrument {
            stopInstrumentRecording()
        }
        engine.pause()
        isPlaying = false
        currentTime = engine.currentTime
    }

    func stop() {
        cancelCountIn()
        stopDrumSequencer()
        if isRecordingInstrument {
            stopInstrumentRecording()
        }
        engine.stop()
        isPlaying = false
        currentTime = 0
        levels = [:]
    }

    // MARK: - Metronome and count-in

    var beatDuration: TimeInterval {
        60.0 / Double(max(60, tempoBPM))
    }

    /// Turns the click track on or off.
    func toggleMetronome() {
        isMetronomeEnabled.toggle()
        engine.setMetronome(enabled: isMetronomeEnabled, level: metronomeLevel)
        persistActiveSession()
    }

    /// Sets the click level for the metronome and the count-in.
    func setMetronomeLevel(_ value: Float) {
        metronomeLevel = min(1, max(0, value))
        engine.setMetronome(enabled: isMetronomeEnabled, level: metronomeLevel)
    }

    /// Arms or disarms the one-bar count-in before playback and recording.
    func toggleCountIn() {
        isCountInEnabled.toggle()
        if !isCountInEnabled {
            cancelCountIn()
        }
        persistActiveSession()
    }

    // MARK: - Punch recording

    /// Whether a usable punch window has been set on the ruler.
    var hasPunchRange: Bool {
        punchOut > punchIn + 0.05
    }

    /// Whether a recording on this track would punch in over the set range.
    func isPunchActive(for trackID: UUID) -> Bool {
        isPunchEnabled && hasPunchRange && armedTrackID == trackID
    }

    func togglePunch() {
        isPunchEnabled.toggle()
        persistActiveSession()
    }

    /// Sets the punch-in point at the playhead.
    func setPunchIn(at time: TimeInterval) {
        punchIn = max(0, time)
        if punchOut <= punchIn + 0.05 {
            punchOut = punchIn + max(0.5, beatDuration)
        }
        persistActiveSession()
    }

    /// Sets the punch-out point at the playhead.
    func setPunchOut(at time: TimeInterval) {
        punchOut = max(punchIn + 0.05, time)
        persistActiveSession()
    }

    /// Chooses the track a punch recording is armed on.
    func armTrack(_ id: UUID?) {
        armedTrackID = id
        persistActiveSession()
    }

    /// Cuts the punched region out of the recording, trims the existing clips
    /// around it and crossfades the new audio into the joins.
    private func applyPunch(take: RecordedInstrumentTake) -> TimeInterval? {
        guard hasPunchRange,
              let index = tracks.firstIndex(where: { $0.id == take.trackID }) else { return nil }

        let offset = max(0, punchIn - recordingStartTime)
        let length = min(punchOut - punchIn, take.duration - offset)
        guard length > 0.05 else { return nil }

        let crossFade = min(0.03, length / 6)
        guard let punched = PunchTakeRenderer.render(
            sourceURL: take.url,
            offset: offset,
            duration: length,
            crossFade: crossFade
        ) else { return nil }

        var track = tracks[index]
        var keptClips: [AudioClip] = []
        for clip in track.clips {
            let start = max(0, clip.startTime)
            let playable = min(clip.duration, max(0, clip.sourceDuration - clip.sourceStartTime))
            let end = start + playable
            let cutStart = punchIn + crossFade
            let cutEnd = punchOut - crossFade
            guard end > cutStart, start < cutEnd else {
                keptClips.append(clip)
                continue
            }
            if start < cutStart {
                var left = clip
                left.duration = cutStart - start
                keptClips.append(left)
            }
            if end > cutEnd {
                var right = clip
                right.startTime = cutEnd
                right.duration = end - cutEnd
                right.sourceStartTime += (cutEnd - start)
                keptClips.append(right)
            }
        }
        track.clips = keptClips
        track.clips.append(AudioClip(
            name: "Punch",
            fileName: punched.url.lastPathComponent,
            startTime: punchIn,
            duration: punched.duration
        ))
        track.clips.sort { $0.startTime < $1.startTime }
        tracks[index] = track
        return punched.duration
    }

    /// Plays a count-in of clicks on the metronome voices.
    func playMetronomeCountIn(beats: Int) {
        _ = engine.playCountIn(beats: beats)
    }

    func stopMetronomeCountIn() {
        engine.silenceMetronome()
    }

    // MARK: - Loop range

    /// Whether the session has a section marked for looping.
    var hasLoopRange: Bool {
        loopEnd > loopStart + 0.01
    }

    private var isLoopingPlayback: Bool {
        isLoopEnabled && hasLoopRange
    }

    /// Turns repeating playback on or off for the marked section.
    func toggleLoop() {
        guard hasLoopRange else { return }
        isLoopEnabled.toggle()
        applyLoopChangeToEngine()
        persistActiveSession()
    }

    /// Marks a new section by dragging on the loop strip.
    func setLoopRange(start: TimeInterval, end: TimeInterval) {
        let lower = max(0, min(start, end))
        var upper = max(start, end)
        if duration > 0 {
            upper = min(upper, duration)
        }
        loopStart = min(lower, max(0, upper - minimumLoopLength))
        loopEnd = max(loopStart + minimumLoopLength, upper)
    }

    /// Moves the start marker of the loop.
    func setLoopStart(_ time: TimeInterval) {
        let maximumStart = max(0, loopEnd - minimumLoopLength)
        loopStart = min(max(0, time), maximumStart)
    }

    /// Moves the end marker of the loop.
    func setLoopEnd(_ time: TimeInterval) {
        let upperLimit = duration > 0 ? duration : max(loopEnd, time)
        loopEnd = min(upperLimit, max(loopStart + minimumLoopLength, time))
    }

    /// Applies finished marker edits to playback and saves them with the session.
    func commitLoopChange() {
        applyLoopChangeToEngine()
        persistActiveSession()
    }

    private func applyLoopChangeToEngine() {
        if duration > 0 {
            loopStart = min(loopStart, max(0, duration - minimumLoopLength))
            loopEnd = min(max(loopStart, loopEnd), duration)
        }

        let range = isLoopingPlayback
            ? ClosedRange(uncheckedBounds: (loopStart, loopEnd))
            : nil
        engine.setLoopRange(range)
    }

    // MARK: - Timeline scrubbing

    func beginScrub() {
        wasPlayingBeforeScrub = isPlaying
        if isPlaying { pause() }
        scrubTime = currentTime
    }

    func updateScrub(_ time: TimeInterval) {
        scrubTime = min(max(0, time), duration)
    }

    func endScrub() {
        if let time = scrubTime {
            currentTime = time
            engine.seek(to: time)
        }
        scrubTime = nil
        if wasPlayingBeforeScrub {
            beginPlayback()
        }
    }

    // MARK: - Waveforms

    /// Loads track and recorded-clip peak envelopes off the main thread.
    func loadWaveforms() {
        waveformTask?.cancel()
        let tracksToLoad = tracks
        waveformTask = Task { [weak self] in
            let peaks = await Task.detached {
                (Self.computePeaks(for: tracksToLoad), Self.computeClipPeaks(for: tracksToLoad))
            }.value
            self?.waveformPeaks = peaks.0
            self?.clipWaveformPeaks = peaks.1
        }
    }

    /// Streams each track's audio and records the loudest sample per bucket.
    private nonisolated static func computePeaks(for tracks: [Track]) -> [UUID: [Float]] {
        var result: [UUID: [Float]] = [:]
        let bucketCount = 2000

        for track in tracks {
            let url = TrackStorage.url(forFileName: track.fileName)
            guard let file = try? AVAudioFile(forReading: url),
                  let buffer = try? AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16384) else {
                continue
            }

            let totalFrames = Int(file.length)
            guard totalFrames > 0 else { continue }

            var peaks = [Float](repeating: 0, count: bucketCount)
            let channelCount = Int(file.processingFormat.channelCount)
            var framesRead = 0

            while framesRead < totalFrames {
                let toRead = min(16384, totalFrames - framesRead)
                try? file.read(into: buffer, frameCount: AVAudioFrameCount(toRead))
                let read = Int(buffer.frameLength)
                guard read > 0, let data = buffer.floatChannelData else { break }

                for channel in 0..<channelCount {
                    let samples = data[channel]
                    for i in 0..<read {
                        let bucket = min(bucketCount - 1, (framesRead + i) * bucketCount / totalFrames)
                        let value = abs(samples[i])
                        if value > peaks[bucket] {
                            peaks[bucket] = value
                        }
                    }
                }
                framesRead += read
            }

            normalize(&peaks)
            result[track.id] = peaks
        }
        return result
    }

    private nonisolated static func computeClipPeaks(for tracks: [Track]) -> [UUID: [Float]] {
        var result: [UUID: [Float]] = [:]
        let bucketCount = 1000

        for clip in tracks.flatMap(\.playbackClips) {
            let url = TrackStorage.url(forFileName: clip.fileName)
            guard let file = try? AVAudioFile(forReading: url),
                  let buffer = try? AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16384) else {
                continue
            }

            let sampleRate = file.processingFormat.sampleRate
            let sourceStart = max(0, Int(clip.sourceStartTime * sampleRate))
            let availableFrames = max(0, Int(file.length) - sourceStart)
            let clipFrames = min(availableFrames, max(0, Int(clip.duration * sampleRate)))
            guard clipFrames > 0 else { continue }
            file.framePosition = AVAudioFramePosition(sourceStart)

            var peaks = [Float](repeating: 0, count: bucketCount)
            let channelCount = Int(file.processingFormat.channelCount)
            var framesRead = 0

            while framesRead < clipFrames {
                let toRead = min(16384, clipFrames - framesRead)
                try? file.read(into: buffer, frameCount: AVAudioFrameCount(toRead))
                let read = Int(buffer.frameLength)
                guard read > 0, let data = buffer.floatChannelData else { break }

                for channel in 0..<channelCount {
                    for frame in 0..<read {
                        let bucket = min(bucketCount - 1, (framesRead + frame) * bucketCount / clipFrames)
                        peaks[bucket] = max(peaks[bucket], abs(data[channel][frame]))
                    }
                }
                framesRead += read
            }

            normalize(&peaks)
            result[clip.id] = peaks
        }
        return result
    }

    private nonisolated static func normalize(_ peaks: inout [Float]) {
        let maxPeak = peaks.max() ?? 0
        guard maxPeak > 0 else { return }
        for index in peaks.indices {
            peaks[index] = min(1, peaks[index] / maxPeak)
        }
    }

    // MARK: - Stem separation

    /// Splits a full song into stems on device and loads them as tracks.
    func separateStems(from songURL: URL) {
        guard !isSeparating else { return }

        isSeparating = true
        separationProgress = 0
        separationStatus = "Preparing…"

        Task {
            do {
                let stems = try await OnDeviceStemSeparator.separate(fileAt: songURL) { [weak self] status, fraction in
                    Task { @MainActor in
                        self?.separationStatus = status
                        self?.separationProgress = fraction
                    }
                }
                applyStems(stems)
            } catch {
                separationError = (error as? LocalizedError)?.errorDescription
                    ?? "Separation failed. The file may not be readable as audio."
            }
            isSeparating = false
        }
    }

    private func applyStems(_ stems: [ImportedStem]) {
        stop()
        tracks = stems.map { Track(name: $0.name, fileName: $0.storedName) }
        reloadEngine()
    }

    private func clipLocation(trackID: UUID, clipID: UUID) -> (track: Int, clip: Int)? {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let clipIndex = tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) else { return nil }
        return (trackIndex, clipIndex)
    }

    private func snappedTime(_ time: TimeInterval, interval: TimeInterval) -> TimeInterval {
        let step = max(0.05, interval)
        return max(0, (time / step).rounded() * step)
    }

    private func resolveClipMetadata() {
        for trackIndex in tracks.indices {
            for clipIndex in tracks[trackIndex].clips.indices {
                var clip = tracks[trackIndex].clips[clipIndex]
                let url = TrackStorage.url(forFileName: clip.fileName)
                guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { continue }

                let sourceDuration = TimeInterval(file.length) / file.processingFormat.sampleRate
                if clip.sourceDuration <= 0 || clip.sourceDuration > sourceDuration {
                    clip.sourceDuration = sourceDuration
                }
                if clip.duration <= 0 {
                    clip.duration = max(0, clip.sourceDuration - clip.sourceStartTime)
                }
                clip.duration = min(clip.duration, max(0, clip.sourceDuration - clip.sourceStartTime))
                tracks[trackIndex].clips[clipIndex] = clip
            }
        }
    }

    private func reloadEngine() {
        if isRecordingInstrument {
            stopInstrumentRecording()
        }
        resolveClipMetadata()
        engine.load(tracks: tracks)
        engine.updateGroups(groups)
        duration = engine.duration
        applyLoopChangeToEngine()
        isPlaying = false
        currentTime = 0
        loadWaveforms()
        commitSession()
    }

    private func refresh() {
        let time = engine.currentTime
        engine.updateAutomation(at: time)
        engine.ensureLoopScheduling()
        if isPlaying, !isLoopingPlayback, duration > 0, time >= duration {
            stop()
        } else {
            currentTime = time
            if isRecordingInstrument {
                recordingElapsed = max(0, time - recordingStartTime)
            }
        }
        updateLevels()
        loudness = engine.loudnessReading()
    }

    private func updateLevels() {
        for track in tracks {
            let level = engine.level(for: track.id)
            let previous = smoothedLevels[track.id] ?? 0
            let smoothed = level > previous ? level : previous * 0.82
            smoothedLevels[track.id] = smoothed
            levels[track.id] = smoothed
        }

        let loudestTrack = tracks.map { levels[$0.id] ?? 0 }.max() ?? 0
        let target = min(1, loudestTrack * masterVolume)
        masterLevel = target > masterLevel ? target : masterLevel * 0.82
    }
}
