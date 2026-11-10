//
//  SeparateSongView.swift
//  AI Music Studio
//

import AVFoundation
import SwiftUI

struct SeparateSongView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: MixerViewModel

    let sourceURL: URL

    @State private var source: StemSeparationSource?
    @State private var selectedTargets = AudioShakeStemTarget.defaultSelection
    @State private var isPreparingSource = true
    @State private var isPreviewPlaying = false
    @State private var isAdditionalExpanded = true
    @State private var preparationError: String?
    @State private var operationError: String?
    @State private var completionMessage: String?
    @State private var previewPlayer: AVAudioPlayer?

    private var primaryTargets: [AudioShakeStemTarget] {
        [.vocals, .drums, .bass, .guitar, .keys, .residual]
    }

    private var additionalTargets: [AudioShakeStemTarget] {
        [.piano, .strings, .wind, .drumKit]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 11) {
                        sourceCard
                        stemSection(title: "Stems", targets: primaryTargets)
                        additionalInstrumentsSection
                        estimateCard
                        uploadDisclosure
                        actionButtons

                        if model.isSeparating {
                            progressCard
                        }
                        if let completionMessage {
                            noticeCard(completionMessage, symbol: "checkmark.circle.fill", color: .green)
                        }
                        if let preparationError {
                            noticeCard(preparationError, symbol: "exclamationmark.triangle.fill", color: .orange)
                        }
                        if let operationError {
                            VStack(alignment: .leading, spacing: 8) {
                                noticeCard(operationError, symbol: "exclamationmark.triangle.fill", color: .orange)
                                if operationError.localizedCaseInsensitiveContains("API key") {
                                    Link(destination: URL(string: "https://dashboard.audioshake.ai")!) {
                                        Label("Create an AudioShake API key", systemImage: "arrow.up.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color.studioAccent)
                                    }
                                    Text("Enter it with the secure key-entry prompt in this chat.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
            .background(Color.studioBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task(id: sourceURL) {
            await prepareSource()
        }
        .onDisappear {
            previewPlayer?.stop()
            previewPlayer = nil
            isPreviewPlaying = false
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                previewPlayer?.stop()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(spacing: 3) {
                Text("Separate Your Song")
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Choose the parts to extract")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Menu {
                Button("Close", systemImage: "xmark") {
                    previewPlayer?.stop()
                    dismiss()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var sourceCard: some View {
        HStack(spacing: 13) {
            Image(systemName: "music.note")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(Color.studioAccent)
                .frame(width: 50, height: 50)
                .background(Color.studioAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 5) {
                Text(source?.originalFileName ?? sourceURL.lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 7) {
                    if isPreparingSource {
                        Text("Preparing song…")
                    } else if let source {
                        Text(durationString(source.duration))
                        Text("•")
                        Text("Uploaded song")
                    } else {
                        Text("Source unavailable")
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button(action: togglePreview) {
                Image(systemName: isPreviewPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(source == nil || model.isSeparating)
            .accessibilityLabel(isPreviewPlaying ? "Stop source preview" : "Preview source song")
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func stemSection(title: String, targets: [AudioShakeStemTarget]) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.top, 13)
                .padding(.bottom, 7)

            ForEach(Array(targets.enumerated()), id: \.element.id) { index, target in
                targetRow(target)
                if index < targets.count - 1 {
                    Divider()
                        .overlay(Color.white.opacity(0.035))
                        .padding(.leading, 65)
                        .padding(.trailing, 14)
                }
            }
        }
        .padding(.bottom, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
        }
    }

    private var additionalInstrumentsSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isAdditionalExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("More instruments")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: isAdditionalExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 15)
                .frame(height: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isAdditionalExpanded {
                Divider().overlay(Color.white.opacity(0.04))
                ForEach(Array(additionalTargets.enumerated()), id: \.element.id) { index, target in
                    targetRow(target)
                    if index < additionalTargets.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.035))
                            .padding(.leading, 65)
                            .padding(.trailing, 14)
                    }
                }
                .padding(.bottom, 7)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
        }
    }

    private func targetRow(_ target: AudioShakeStemTarget) -> some View {
        HStack(spacing: 11) {
            Image(systemName: target.symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.studioAccent)
                .frame(width: 39, height: 39)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))

            Text(target.title)
                .font(.system(size: 14, weight: .medium))

            Spacer(minLength: 8)

            Toggle(target.title, isOn: targetBinding(target))
                .labelsHidden()
                .tint(Color.studioAccent)
                .disabled(model.isSeparating)
                .accessibilityLabel("Separate \(target.title)")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 55)
    }

    private var estimateCard: some View {
        let billedMinutes = source.map { max(1, Int(ceil($0.duration / 60))) } ?? 0
        let credits = billedMinutes * selectedTargets.count

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Image(systemName: "circle.stack.fill")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Color.studioAccent)
                    .frame(width: 48, height: 48)
                    .background(Color.studioAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text("Estimated cost")
                            .font(.system(size: 14, weight: .semibold))
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text("\(credits) credits")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.studioAccent)
                            .contentTransition(.numericText())
                    }
                    Text("\(selectedTargets.count) stems  ·  \(billedMinutes) \(billedMinutes == 1 ? "minute" : "minutes")")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(Color.white.opacity(0.05))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.studioAccent)
                Text("Credits are charged per minute for each selected stem. Source duration rounds up to the next whole minute.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
        }
    }

    private var uploadDisclosure: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.studioAccent)
                .frame(width: 46, height: 46)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 4) {
                Text("Your song is uploaded to AudioShake.")
                    .font(.system(size: 12, weight: .medium))
                Text("Separated stems are AI estimates and may contain some bleed.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 9) {
            Button(action: startAISeparation) {
                Text("Separate Stems")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.9))
                    .frame(maxWidth: .infinity, minHeight: 55)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 1, green: 0.76, blue: 0.24), Color(red: 0.97, green: 0.57, blue: 0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(source == nil || selectedTargets.isEmpty || model.isSeparating || isPreparingSource)
            .opacity(source == nil || selectedTargets.isEmpty || model.isSeparating || isPreparingSource ? 0.55 : 1)

            Button(action: startOfflineSplit) {
                Text("Use Offline Band Split")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        LinearGradient(
                            colors: [Color.white.opacity(0.11), Color.white.opacity(0.035)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(source == nil || model.isSeparating || isPreparingSource)
            .opacity(source == nil || model.isSeparating || isPreparingSource ? 0.55 : 1)
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(Color.studioAccent)
                Text(model.separationStatus)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text("\(Int(model.separationProgress * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.studioAccent)
            }
            ProgressView(value: model.separationProgress)
                .tint(Color.studioAccent)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func noticeCard(_ message: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @MainActor
    private func prepareSource() async {
        isPreparingSource = true
        preparationError = nil
        do {
            source = try await AudioShakeStemSeparator.prepareSource(from: sourceURL)
        } catch {
            preparationError = (error as? LocalizedError)?.errorDescription ?? "The selected song could not be prepared."
            source = nil
        }
        isPreparingSource = false
    }

    private func targetBinding(_ target: AudioShakeStemTarget) -> Binding<Bool> {
        Binding(
            get: { selectedTargets.contains(target) },
            set: { isSelected in
                guard !model.isSeparating else { return }
                if isSelected {
                    selectedTargets.insert(target)
                } else {
                    selectedTargets.remove(target)
                }
                completionMessage = nil
                operationError = nil
            }
        )
    }

    private func togglePreview() {
        guard let source else { return }
        if isPreviewPlaying {
            previewPlayer?.stop()
            previewPlayer = nil
            isPreviewPlaying = false
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: source.fileURL)
            previewPlayer = player
            isPreviewPlaying = player.play()
            let playbackDuration = player.duration
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(playbackDuration))
                guard previewPlayer === player else { return }
                previewPlayer = nil
                isPreviewPlaying = false
            }
        } catch {
            operationError = "The source preview could not be played."
        }
    }

    private func startAISeparation() {
        guard let source else { return }
        completionMessage = nil
        operationError = nil
        model.separateStems(from: source, targets: selectedTargets) { addedCount, failures, error in
            if let error {
                operationError = error
                return
            }
            guard addedCount > 0 else { return }
            if failures.isEmpty {
                completionMessage = "Added \(addedCount) AI-separated \(addedCount == 1 ? "stem" : "stems") to your session."
            } else {
                completionMessage = "Added \(addedCount) AI stem(s). Some targets could not be separated: \(failures.joined(separator: "; "))"
            }
        }
    }

    private func startOfflineSplit() {
        guard let source else { return }
        completionMessage = nil
        operationError = nil
        model.separateOfflineStems(from: source) { addedCount, error in
            if let error {
                operationError = error
            } else if addedCount > 0 {
                completionMessage = "Added \(addedCount) offline frequency-band tracks to your session."
            }
        }
    }

    private func durationString(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
