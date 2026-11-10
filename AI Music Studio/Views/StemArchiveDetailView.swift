//
//  StemArchiveDetailView.swift
//  AI Music Studio
//

import AVFoundation
import SwiftUI

struct StemArchiveDetailView: View {
    let archive: MixExportArchive

    @StateObject private var previewController = StemArchivePreviewController()
    @State private var manifest: StemArchiveManifest?
    @State private var manifestError: String?
    @State private var isLoading = true
    @State private var shareItem: ShareItem?
    @State private var temporaryShareURL: URL?
    @State private var shareFileName: String?
    @State private var shareError: String?
    @State private var sharePreparationTask: Task<Void, Never>?
    @StateObject private var verificationProgress = StemArchiveVerificationProgress()
    @State private var isVerifyingArchive = false
    @State private var verificationResult: StemArchiveVerificationResult?
    @State private var verificationError: String?
    @State private var verificationRequestID = UUID()
    @State private var verificationWorkerTask: Task<StemArchiveVerificationResult, any Error>?

    private var sessionName: String {
        manifest?.sessionName ?? archive.sessionName ?? archive.name
    }

    private var archiveTitle: String {
        "\(sessionName) - Stems"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(archiveTitle)
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("ZIP ARCHIVE  ·  \(manifest?.stems.count ?? 0) STEMS")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                }

                sessionCard

                if let bounceSettings = manifest?.bounceSettings {
                    bounceSettingsSection(bounceSettings)
                }

                verificationSection

                VStack(alignment: .leading, spacing: 11) {
                    Text("CONTENTS")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)

                    if let manifest {
                        ForEach(manifest.stems) { stem in
                            stemRow(stem)
                        }
                        if let previewError = previewController.errorMessage {
                            Label(previewError, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8)
                        }
                        if let shareError {
                            Label(shareError, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8)
                        }
                    } else if isLoading {
                        ProgressView("Reading manifest…")
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .tint(Color.studioAccent)
                    } else {
                        ContentUnavailableView(
                            "Manifest Unavailable",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(manifestError ?? "The archive contents could not be read.")
                        )
                        .padding(.vertical, 12)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .background(Color.studioBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 9) {
                Button(action: verifyArchive) {
                    HStack(spacing: 9) {
                        if isVerifyingArchive {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.studioAccent)
                        } else {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.studioAccent)
                        }
                        Text(isVerifyingArchive ? "Verifying Archive…" : "Verify Archive")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .padding(.horizontal, 16)
                    .background(Color.studioPanel, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isVerifyingArchive)
                .accessibilityLabel(isVerifyingArchive ? "Verifying archive" : "Verify archive integrity")

                ShareLink(item: archive.url) {
                    Text("Share Archive")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(Color.studioAccent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share stem archive")
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(Color.studioBackground.opacity(0.96))
        }
        .navigationTitle("Stem Archive")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: archive.url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                }
                .accessibilityLabel("Share archive")
            }
        }
        .task {
            loadManifest()
        }
        .sheet(item: $shareItem, onDismiss: {
            cleanupShareFile()
        }) { item in
            ShareSheet(items: [item.url]) {
                cleanupShareFile(at: item.url)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onDisappear {
            sharePreparationTask?.cancel()
            sharePreparationTask = nil
            verificationRequestID = UUID()
            verificationWorkerTask?.cancel()
            verificationWorkerTask = nil
            isVerifyingArchive = false
            if shareItem == nil {
                cleanupShareFile()
            }
            previewController.stop()
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    private var sessionCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(Color.studioAccent)
                .frame(width: 80, height: 80)
                .background(Color.studioBackground, in: RoundedRectangle(cornerRadius: 15))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 7) {
                Text(sessionName)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(manifest.map { "\($0.sessionTempoBPM) BPM" } ?? "Tempo unavailable")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.studioAccent)
                .frame(width: 3)
                .padding(.vertical, 13)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.studioAccent.opacity(0.48), lineWidth: 1)
        }
    }

    private func bounceSettingsSection(_ settings: StemArchiveManifest.BounceSettings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BOUNCE SETTINGS")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)

            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: 13
            ) {
                let rangeValue: String = {
                    guard settings.range == .loopRange,
                          let loopStart = settings.loopStart,
                          let loopEnd = settings.loopEnd else {
                        return settings.range.title
                    }
                    return "\(settings.range.title) · \(studioTimeString(loopStart))–\(studioTimeString(loopEnd))"
                }()
                bounceSettingValue("Range", value: rangeValue)
                bounceSettingValue("Sample Rate", value: settings.sampleRate.title)
                if let bitDepth = settings.bitDepth {
                    bounceSettingValue("Bit Depth", value: bitDepth.title)
                }
                bounceSettingValue("Normalization", value: settings.normalize ? "On" : "Off")
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private func bounceSettingValue(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stemRow(_ stem: StemArchiveManifest.Stem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.studioAccent)
                .frame(width: 54, height: 54)
                .background(Color.studioBackground, in: Circle())
                .overlay {
                    Circle().stroke(Color.white.opacity(0.07), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(stem.trackName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(Self.formatDuration(stem.duration))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Text(stem.format.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.studioAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.studioAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

            Button {
                previewController.toggle(fileName: stem.fileName, archiveURL: archive.url)
            } label: {
                Group {
                    if previewController.isLoading(stem.fileName) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.studioAccent)
                    } else {
                        Image(systemName: previewController.isPlaying(stem.fileName) ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.studioAccent)
                    }
                }
                .frame(width: 40, height: 40)
                .background(Color.studioAccent.opacity(0.12), in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(previewController.accessibilityLabel(for: stem.trackName, fileName: stem.fileName))

            Button {
                prepareShare(for: stem)
            } label: {
                Group {
                    if shareFileName == stem.fileName, sharePreparationTask != nil {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.studioAccent)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.studioAccent)
                    }
                }
                .frame(width: 40, height: 40)
                .background(Color.studioAccent.opacity(0.12), in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(sharePreparationTask != nil || shareItem != nil)
            .accessibilityLabel("Share \(stem.trackName)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 19))
        .overlay {
            RoundedRectangle(cornerRadius: 19)
                .stroke(Color.white.opacity(0.045), lineWidth: 1)
        }
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var verificationSection: some View {
        Group {
            if isVerifyingArchive {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("VERIFYING ARCHIVE")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(verificationProgress.fraction * 100))%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.studioAccent)
                    }
                    ProgressView(value: verificationProgress.fraction)
                        .tint(Color.studioAccent)
                    if !verificationProgress.currentEntry.isEmpty {
                        Text("Checking \(verificationProgress.currentEntry)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 18))
            } else if let verificationResult {
                VStack(alignment: .leading, spacing: 9) {
                    Label(
                        verificationResult.isIntact ? "Archive Intact" : "Verification Failed",
                        systemImage: verificationResult.isIntact ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(verificationResult.isIntact ? Color.green : Color.orange)

                    Text(verificationResult.isIntact
                         ? "All \(verificationResult.entryCount) ZIP entries passed size and checksum checks."
                         : "\(verificationResult.verifiedEntryCount) of \(verificationResult.entryCount) entries passed. Affected entries:")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !verificationResult.isIntact {
                        ForEach(verificationResult.failures) { failure in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(failure.entryName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(failure.reason)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 3)
                        }
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(verificationResult.isIntact ? Color.green.opacity(0.35) : Color.orange.opacity(0.35), lineWidth: 1)
                }
            } else if let verificationError {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Archive Could Not Be Verified", systemImage: "exclamationmark.shield.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.orange)
                    Text(verificationError)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private func verifyArchive() {
        guard !isVerifyingArchive else { return }
        let requestID = UUID()
        verificationRequestID = requestID
        isVerifyingArchive = true
        verificationResult = nil
        verificationError = nil
        verificationProgress.reset(for: requestID)

        let progress = verificationProgress
        let archiveURL = archive.url
        let worker = Task.detached(priority: .utility) {
            try StemArchive.verifyArchive(at: archiveURL) { fraction, entryName in
                Task { @MainActor in
                    progress.update(fraction: fraction, entryName: entryName, requestID: requestID)
                }
            }
        }
        verificationWorkerTask = worker

        Task { @MainActor in
            do {
                let result = try await worker.value
                guard verificationRequestID == requestID else { return }
                verificationResult = result
            } catch {
                guard verificationRequestID == requestID else { return }
                if !(error is CancellationError) {
                    verificationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
            guard verificationRequestID == requestID else { return }
            isVerifyingArchive = false
            verificationWorkerTask = nil
        }
    }

    private func prepareShare(for stem: StemArchiveManifest.Stem) {
        guard sharePreparationTask == nil, shareItem == nil else { return }
        shareError = nil
        shareFileName = stem.fileName
        let archiveURL = archive.url
        let fileName = stem.fileName
        let trackName = stem.trackName

        sharePreparationTask = Task {
            defer {
                sharePreparationTask = nil
                shareFileName = nil
            }

            do {
                let extraction = Task.detached(priority: .userInitiated) {
                    try StemArchive.extractStem(from: archiveURL, fileName: fileName, named: trackName)
                }
                let extractedURL = try await extraction.value
                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: extractedURL)
                    return
                }
                temporaryShareURL = extractedURL
                shareItem = ShareItem(url: extractedURL)
            } catch {
                guard !Task.isCancelled else { return }
                shareError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func cleanupShareFile(at url: URL? = nil) {
        let fileURL = url ?? temporaryShareURL
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
        if temporaryShareURL == fileURL {
            temporaryShareURL = nil
        }
        if shareItem?.url == fileURL {
            shareItem = nil
        }
    }

    private func loadManifest() {
        do {
            manifest = try StemArchive.readManifest(from: archive.url)
        } catch {
            manifestError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

@MainActor
private final class StemArchiveVerificationProgress: ObservableObject {
    @Published private(set) var fraction = 0.0
    @Published private(set) var currentEntry = ""

    private var requestID = UUID()

    func reset(for requestID: UUID) {
        self.requestID = requestID
        fraction = 0
        currentEntry = ""
    }

    func update(fraction: Double, entryName: String, requestID: UUID) {
        guard self.requestID == requestID else { return }
        self.fraction = min(1, max(0, fraction))
        currentEntry = entryName
    }
}

@MainActor
private final class StemArchivePreviewController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var errorMessage: String?
    @Published private(set) var activeFileName: String?
    @Published private(set) var isLoadingPreview = false
    @Published private(set) var isPreviewPlaying = false

    private var player: AVAudioPlayer?
    private var previewFileURL: URL?
    private var extractionTask: Task<Void, Never>?
    private var requestID = UUID()

    func isLoading(_ fileName: String) -> Bool {
        activeFileName == fileName && isLoadingPreview
    }

    func isPlaying(_ fileName: String) -> Bool {
        activeFileName == fileName && isPreviewPlaying
    }

    func accessibilityLabel(for trackName: String, fileName: String) -> String {
        if isLoading(fileName) { return "Cancel preview of \(trackName)" }
        return isPlaying(fileName) ? "Pause \(trackName)" : "Play \(trackName)"
    }

    func toggle(fileName: String, archiveURL: URL) {
        errorMessage = nil

        if activeFileName == fileName {
            if isLoadingPreview {
                stop()
            } else if isPreviewPlaying {
                player?.pause()
                isPreviewPlaying = false
            } else if let player {
                isPreviewPlaying = player.play()
            }
            return
        }

        stop()
        errorMessage = nil
        let requestID = UUID()
        self.requestID = requestID
        activeFileName = fileName
        isLoadingPreview = true

        extractionTask = Task { [weak self] in
            do {
                let extraction = Task.detached(priority: .userInitiated) {
                    try StemArchive.extractStem(from: archiveURL, fileName: fileName)
                }
                let extractedURL = try await extraction.value
                guard let self, self.requestID == requestID else {
                    try? FileManager.default.removeItem(at: extractedURL)
                    return
                }
                self.extractionTask = nil

                do {
                    let audioPlayer = try AVAudioPlayer(contentsOf: extractedURL)
                    audioPlayer.delegate = self
                    audioPlayer.prepareToPlay()
                    guard audioPlayer.play() else {
                        audioPlayer.delegate = nil
                        try? FileManager.default.removeItem(at: extractedURL)
                        self.finishWithError("This stem could not be played.")
                        return
                    }
                    self.player = audioPlayer
                    self.previewFileURL = extractedURL
                    self.isLoadingPreview = false
                    self.isPreviewPlaying = true
                } catch {
                    try? FileManager.default.removeItem(at: extractedURL)
                    self.finishWithError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            } catch {
                guard let self, self.requestID == requestID else { return }
                self.extractionTask = nil
                self.finishWithError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func stop() {
        requestID = UUID()
        extractionTask?.cancel()
        extractionTask = nil
        player?.delegate = nil
        player?.stop()
        player = nil
        removePreviewFile()
        activeFileName = nil
        isLoadingPreview = false
        isPreviewPlaying = false
        errorMessage = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player else { return }
        player.delegate = nil
        self.player = nil
        removePreviewFile()
        activeFileName = nil
        isLoadingPreview = false
        isPreviewPlaying = false
        if !flag {
            errorMessage = "Stem playback ended unexpectedly."
        }
    }

    private func finishWithError(_ message: String) {
        player?.delegate = nil
        player?.stop()
        player = nil
        removePreviewFile()
        activeFileName = nil
        isLoadingPreview = false
        isPreviewPlaying = false
        errorMessage = message
    }

    private func removePreviewFile() {
        if let previewFileURL {
            try? FileManager.default.removeItem(at: previewFileURL)
            self.previewFileURL = nil
        }
    }
}
