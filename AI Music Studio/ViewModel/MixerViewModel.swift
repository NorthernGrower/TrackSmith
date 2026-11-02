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
    @Published private(set) var sections: [SongSection] = []
    @Published private(set) var channelPresets: [ChannelPreset] = []
    @Published private(set) var masterLevel: Float = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var tempoBPM = 120
    @Published private(set) var loopStart: TimeInterval = 0
    @Published private(set) var loopEnd: TimeInterval = 0
    @Published private(set) var isLoopEnabled = false
    @Published private(set) var isMetronomeEnabled = false
    @Published private(set) var metronomeLevel: Float = 0.7
    @Published private(set) var isCountInEnabled = false
    @Published private(set) var isCountingIn = false
    @Published private(set) var countInBeatsRemaining = 0
    @Published private(set) var drumPattern = DrumPattern()
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
        let storedSessions = StudioSessionStorage.load()
        sessions = storedSessions.sessions
        activeSessionID = storedSessions.activeSessionID
        if let session = storedSessions.sessions.first(where: { $0.id == storedSessions.activeSessionID }) {
            sessionName = session.name
            activeTemplateID = session.templateID
            tracks = session.tracks
            groups = session.groups
            tempoBPM = min(200, max(60, session.tempoBPM))
            drumPattern = session.drumPattern
            loopStart = max(0, session.loopStart)
            loopEnd = max(loopStart, session.loopEnd)
            isLoopEnabled = session.isLoopEnabled
            masterVolume = min(1, max(0, session.masterVolume))
            masterEffects = session.masterEffects
            sections = session.sections
            isMetronomeEnabled = session.isMetronomeEnabled
            metronomeLevel = min(1, max(0, session.metronomeLevel))
            isCountInEnabled = session.isCountInEnabled
        }
        exports = MixExportStorage.loadExports()
        resolveClipMetadata()
        engine.load(tracks: tracks)
        engine.updateGroups(groups)
        duration = engine.duration
        applyLoopChangeToEngine()
        engine.setMasterVolume(masterVolume)
        engine.setTempo(tempoBPM)
        engine.updateMasterEffects(masterEffects, tempoBPM: tempoBPM)
        engine.setMetronome(enabled: isMetronomeEnabled, level: metronomeLevel)
        loadWaveforms()

        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1.0 / 30))
            }
        }
    }

    deinit {
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

        if deletingActive, let replacement = sessions.first {
            activateSession(replacement)
        } else {
            StudioSessionStorage.save(sessions: sessions, activeSessionID: activeSessionID)
        }
    }

    private func persistActiveSession(markEdited: Bool = true) {
        guard let index = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        sessions[index].name = sessionName
        sessions[index].templateID = activeTemplateID
        sessions[index].tracks = tracks
        sessions[index].groups = groups
        sessions[index].tempoBPM = tempoBPM
        sessions[index].drumPattern = drumPattern
        sessions[index].loopStart = loopStart
        sessions[index].loopEnd = loopEnd
        sessions[index].isLoopEnabled = isLoopEnabled
        sessions[index].masterVolume = masterVolume
        sessions[index].masterEffects = masterEffects
        sessions[index].sections = sections
        sessions[index].isMetronomeEnabled = isMetronomeEnabled
        sessions[index].metronomeLevel = metronomeLevel
        sessions[index].isCountInEnabled = isCountInEnabled
        if markEdited {
            sessions[index].lastEdited = Date()
        }
        StudioSessionStorage.save(sessions: sessions, activeSessionID: activeSessionID)
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
        sessionName = session.name
        activeTemplateID = session.templateID
        tracks = session.tracks
        groups = session.groups
        tempoBPM = min(200, max(60, session.tempoBPM))
        drumPattern = session.drumPattern
        loopStart = max(0, session.loopStart)
        loopEnd = max(loopStart, session.loopEnd)
        isLoopEnabled = session.isLoopEnabled
        masterVolume = min(1, max(0, session.masterVolume))
        masterEffects = session.masterEffects
        sections = session.sections
        isMetronomeEnabled = session.isMetronomeEnabled
        metronomeLevel = min(1, max(0, session.metronomeLevel))
        isCountInEnabled = session.isCountInEnabled
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

    func playDrumPad(_ pad: DrumPad, destinationTrackID: UUID?) {
        guard let format = engine.instrumentFormat(for: destinationTrackID),
              let buffer = InstrumentSoundGenerator.drumHit(pad, format: format) else { return }
        engine.playInstrumentBuffer(buffer, destinationTrackID: destinationTrackID)
    }

    func toggleDrumStep(_ pad: DrumPad, step: Int) {
        guard (0..<DrumPattern.stepCount).contains(step) else { return }
        drumPattern.toggle(pad, step: step)
        persistActiveSession()
    }

    func startDrumSequencer(destinationTrackID: UUID?) {
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
                        self.playDrumPad(pad, destinationTrackID: destinationTrackID)
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

        let clip = AudioClip(
            name: "Take \(tracks[index].clips.count + 1)",
            fileName: take.url.lastPathComponent,
            startTime: recordingStartTime,
            duration: take.duration
        )
        tracks[index].clips.append(clip)
        recordingElapsed = take.duration

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

    func bounceMix() {
        guard !isBouncing else { return }
        isBouncing = true
        isStemBounce = false
        bounceProgress = 0
        bounceStatus = "Preparing mix…"
        bounceError = nil
        lastExportURL = nil

        let outputURL = MixExportStorage.newExportURL()
        let tracksToBounce = tracks
        let groupsToBounce = groups
        let masterVolumeToBounce = masterVolume
        let masterEffectsToBounce = masterEffects
        let tempoToBounce = tempoBPM
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
                        tempoBPM: tempoToBounce,
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
    func bounceStems() {
        guard !isBouncing else { return }

        let tracksToRender = tracks.filter { audibleDuration(of: $0) > 0 }
        guard !tracksToRender.isEmpty else {
            bounceError = "There are no tracks with audio or notes to export."
            return
        }

        isBouncing = true
        isStemBounce = true
        bounceProgress = 0
        bounceStatus = "Preparing stems…"
        bounceError = nil
        lastExportURL = nil

        let master = masterVolume
        let effects = masterEffects
        let tempo = tempoBPM
        let session = sessionName
        let groupsToBounce = groups

        Task {
            do {
                var lastURL: URL?
                for (index, track) in tracksToRender.enumerated() {
                    let stemURL = MixExportStorage.exportURL(name: "\(session)-\(track.name)")
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
                            tempoBPM: tempo,
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
        let noteEnd = track.sequencedNotes.map(\.endTime).max() ?? 0
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
        let wasPlaying = isPlaying
        let resumeTime = engine.currentTime

        isFreezingTrack = true
        freezeStatus = "Freezing \(track.name)…"
        freezeError = nil
        if wasPlaying { pause() }

        Task { [weak self] in
            do {
                let duration = try await Task.detached(priority: .userInitiated) {
                    try TrackFreezeRenderer.render(track: track, to: outputURL)
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
