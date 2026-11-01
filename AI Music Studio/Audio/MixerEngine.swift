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
    private var clipPlayers: [UUID: [ClipPlayback]] = [:]
    private var clipSignatures: [UUID: [AudioClip]] = [:]
    private var instrumentVoices: [UUID: [AVAudioPlayerNode]] = [:]
    private var instrumentFormats: [UUID: AVAudioFormat] = [:]
    private var voiceCursors: [UUID: Int] = [:]
    private var previewVoices: [AVAudioPlayerNode] = []
    private var previewFormat: AVAudioFormat?
    private var previewVoiceCursor = 0
    private var scheduledInstrumentFiles: [ObjectIdentifier: AVAudioFile] = [:]
    private var takeRecorder: InstrumentTakeRecorder?
    private var takeTrackID: UUID?
    private var takeURL: URL?
    private var takeUsesMicrophone = false
    private let instrumentVoiceCount = 8
    private var trackIDs: [UUID] = []

    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private var playHeadOffset: TimeInterval = 0
    private var playStartDate: Date?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    /// Rebuilds the playback graph for tracks and their audio clips.
    func load(tracks: [Track]) {
        let newClipSignatures = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0.clips) })
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
            let clipFiles: [(clip: AudioClip, file: AVAudioFile)] = track.clips.compactMap { clip in
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

            engine.attach(mixer)
            engine.attach(instrumentMixer)
            engine.attach(equalizer)
            engine.connect(instrumentMixer, to: mixer, format: instrumentFormat)
            engine.connect(mixer, to: equalizer, format: format)
            engine.connect(equalizer, to: engine.mainMixerNode, format: format)

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
            clipPlayers[track.id] = loadedClips
            instrumentVoices[track.id] = voices
            instrumentFormats[track.id] = instrumentFormat
            configureEqualizer(equalizer, settings: track.eqSettings)
        }

        updateMix(tracks: tracks)
        ensurePreviewVoices()
    }

    func updateMix(tracks: [Track]) {
        let anySolo = tracks.contains { $0.isSoloed }
        for track in tracks {
            let audible = !track.isMuted && (!anySolo || track.isSoloed)
            trackMixers[track.id]?.outputVolume = audible ? track.volume : 0
        }
    }

    func updateEqualizer(trackID: UUID, settings: TrackEQSettings) {
        guard let equalizer = equalizers[trackID] else { return }
        configureEqualizer(equalizer, settings: settings)
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

    func play() {
        guard !trackIDs.isEmpty, startAudioEngine() else { return }

        let scheduleDelay = 0.04
        let hostStart = AVAudioTime.hostTime(forSeconds: ProcessInfo.processInfo.systemUptime + scheduleDelay)
        let playbackStart = AVAudioTime(hostTime: hostStart)
        isPlaying = true
        playStartDate = Date().addingTimeInterval(scheduleDelay)

        for id in trackIDs {
            for loadedClip in clipPlayers[id] ?? [] {
                loadedClip.player.stop()
                let clip = loadedClip.clip
                let availableSourceDuration = max(0, clip.sourceDuration - clip.sourceStartTime)
                let clipDuration = min(clip.duration, availableSourceDuration)
                let clipEnd = clip.startTime + clipDuration
                guard clipEnd > playHeadOffset else { continue }

                let offsetInClip = max(0, playHeadOffset - clip.startTime)
                let sourceTime = clip.sourceStartTime + offsetInClip
                let startFrame = AVAudioFramePosition(sourceTime * loadedClip.file.processingFormat.sampleRate)
                let availableFrames = loadedClip.file.length - startFrame
                guard availableFrames > 0 else { continue }

                let playableDuration = clipDuration - offsetInClip
                let requestedFrames = AVAudioFramePosition(playableDuration * loadedClip.file.processingFormat.sampleRate)
                let framesToPlay = min(availableFrames, requestedFrames)
                guard framesToPlay > 0 else { continue }
                let frameCount = AVAudioFrameCount(min(framesToPlay, Int64(UInt32.max)))
                let delay = max(0, clip.startTime - playHeadOffset)
                let clipHostTime = hostStart + AVAudioTime.hostTime(forSeconds: delay)
                let clipStart = AVAudioTime(hostTime: clipHostTime)
                loadedClip.player.scheduleSegment(
                    loadedClip.file,
                    startingFrame: startFrame,
                    frameCount: frameCount,
                    at: clipStart
                )
                loadedClip.player.play(at: playbackStart)
            }
        }
    }

    func pause() {
        guard isPlaying else { return }
        if let start = playStartDate {
            playHeadOffset = min(duration, playHeadOffset + max(0, Date().timeIntervalSince(start)))
        }
        clipPlayers.values.flatMap { $0 }.forEach { $0.player.pause() }
        isPlaying = false
        playStartDate = nil
    }

    func stop() {
        pause()
        playHeadOffset = 0
        clipPlayers.values.flatMap { $0 }.forEach { $0.player.stop() }
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
        clipPlayers.values.flatMap { $0 }.forEach { $0.player.stop() }
        if wasPlaying {
            play()
        }
    }

    var currentTime: TimeInterval {
        guard isPlaying, let start = playStartDate else { return playHeadOffset }
        let elapsed = max(0, Date().timeIntervalSince(start))
        return duration > 0 ? min(duration, playHeadOffset + elapsed) : playHeadOffset + elapsed
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
        try? AVAudioSession.sharedInstance().setActive(true)
        guard !engine.isRunning else { return true }
        engine.prepare()
        do {
            try engine.start()
            return true
        } catch {
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
        for mixer in trackMixers.values {
            mixer.removeTap(onBus: 0)
            engine.detach(mixer)
        }
        trackMixers.removeAll()
        instrumentMixers.removeAll()
        equalizers.removeAll()
        clipPlayers.removeAll()
        clipSignatures.removeAll()
        instrumentVoices.removeAll()
        instrumentFormats.removeAll()
        voiceCursors.removeAll()
        previewVoices.removeAll()
        previewFormat = nil
        scheduledInstrumentFiles.removeAll()
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
