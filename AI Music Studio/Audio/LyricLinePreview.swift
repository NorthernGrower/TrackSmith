import AVFoundation
import Combine
import Foundation

@MainActor
final class LyricLinePreview: ObservableObject {
    @Published private(set) var playingKey: String?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var stopTask: Task<Void, Never>?
    private var isPrepared = false

    func play(_ text: String, key: String) {
        stop()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        if !isPrepared {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            do {
                try engine.start()
                isPrepared = true
            } catch {
                return
            }
        }

        let wordCount = max(1, text.split(whereSeparator: \.isWhitespace).count)
        let noteDuration = 0.26
        let scale = [0, 2, 4, 5, 7, 9, 11]
        let root = 69
        for index in 0..<wordCount {
            let pitch = root + scale[(index * 2 + key.unicodeScalars.reduce(0) { $0 + Int($1.value) }) % scale.count]
            let frequency = 440 * pow(2, Double(pitch - 69) / 12)
            guard let buffer = InstrumentSoundGenerator.vocalNote(
                frequency: frequency,
                duration: noteDuration,
                velocity: 0.78,
                vibratoDepth: 0.015,
                attackSeconds: 0.025,
                releaseSeconds: 0.08,
                breath: 0.07,
                level: 0.16,
                format: format
            ) else { continue }
            player.scheduleBuffer(buffer)
        }
        playingKey = key
        if !player.isPlaying { player.play() }
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(wordCount) * noteDuration + 0.12))
            guard !Task.isCancelled else { return }
            self?.playingKey = nil
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player.stop()
        playingKey = nil
    }
}
