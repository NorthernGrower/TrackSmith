//
//  SpeechPromptRecognizer.swift
//  AI Music Studio
//

import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class SpeechPromptRecognizer: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var previousCategory: AVAudioSession.Category?
    private var previousMode: AVAudioSession.Mode?
    private var previousOptions: AVAudioSession.CategoryOptions?

    func start() {
        guard !isListening else { return }
        errorMessage = nil
        transcript = ""

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard status == .authorized else {
                    self.errorMessage = self.authorizationMessage(for: status)
                    return
                }
                self.requestMicrophonePermission()
            }
        }
    }

    func stop() {
        stopAudioCapture()
        recognitionTask?.finish()
    }

    private func requestMicrophonePermission() {
        audioSession.requestRecordPermission { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard granted else {
                    self.errorMessage = "Microphone access is off. Enable it in Settings to dictate a prompt."
                    return
                }
                self.beginListening()
            }
        }
    }

    private func beginListening() {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is not available right now."
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        previousCategory = audioSession.category
        previousMode = audioSession.mode
        previousOptions = audioSession.categoryOptions

        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            recognitionRequest = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let failure = error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let text, !text.isEmpty {
                        self.transcript = text
                    }
                    if let failure, self.isListening {
                        self.stopAudioCapture()
                        self.errorMessage = failure
                    } else if isFinal {
                        self.stopAudioCapture()
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            audioEngine.inputNode.removeTap(onBus: 0)
            restoreAudioSession()
            errorMessage = "Could not start voice input: \(error.localizedDescription)"
        }
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        isListening = false
        restoreAudioSession()
    }

    private func restoreAudioSession() {
        guard let previousCategory, let previousMode, let previousOptions else { return }
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        try? audioSession.setCategory(previousCategory, mode: previousMode, options: previousOptions)
        try? audioSession.setActive(true)
        self.previousCategory = nil
        self.previousMode = nil
        self.previousOptions = nil
    }

    private func authorizationMessage(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .denied:
            return "Speech recognition access is off. Enable it in Settings to dictate a prompt."
        case .restricted:
            return "Speech recognition is restricted on this device."
        case .notDetermined:
            return "Speech recognition permission has not been granted."
        case .authorized:
            return ""
        @unknown default:
            return "Speech recognition is not available right now."
        }
    }
}
