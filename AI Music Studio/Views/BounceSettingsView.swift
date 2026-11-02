//
//  BounceSettingsView.swift
//  AI Music Studio
//

import SwiftUI

/// Sheet shown before a bounce: format, quality, level and file name.
struct BounceSettingsView: View {
    enum Mode: String {
        case mix
        case stems

        var actionTitle: String {
            switch self {
            case .mix: return "Render Mix"
            case .stems: return "Render Stems"
            }
        }
    }

    let mode: Mode
    let sessionName: String
    let duration: TimeInterval
    let trackCount: Int
    let onRender: (BounceSettings) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings: BounceSettings

    init(
        mode: Mode,
        sessionName: String,
        duration: TimeInterval,
        trackCount: Int,
        settings: BounceSettings,
        onRender: @escaping (BounceSettings) -> Void
    ) {
        self.mode = mode
        self.sessionName = sessionName
        self.duration = duration
        self.trackCount = trackCount
        self.onRender = onRender
        _settings = State(initialValue: settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    formatSection
                    rateSection
                    normalizeRow
                    nameSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }
            .scrollContentBackground(.hidden)

            footer
        }
        .background(Color.studioBackground)
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BOUNCE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.studioAccent)

                Text("Bounce Settings")
                    .font(.system(size: 18, weight: .semibold))
            }

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.studioPanelHighlight.opacity(0.7), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close bounce settings")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(sessionName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(summarySubtitle)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(studioTimeString(duration))
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.studioAccent)
        }
        .padding(13)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
    }

    private var summarySubtitle: String {
        let channel = "STEREO · \(settings.sampleRate.title)"
        if mode == .stems {
            let count = max(1, trackCount)
            return "\(count) \(count == 1 ? "STEM" : "STEMS") · \(channel)"
        }
        return channel
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("FORMAT")

            Picker("Format", selection: $settings.format) {
                ForEach(BounceFormat.allCases, id: \.self) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var rateSection: some View {
        HStack(spacing: 10) {
            stepField(
                title: "SAMPLE RATE",
                value: settings.sampleRate.title,
                isEnabled: true,
                onDecrease: { adjustSampleRate(-1) },
                onIncrease: { adjustSampleRate(1) }
            )

            stepField(
                title: "BIT DEPTH",
                value: settings.format == .m4a ? "—" : settings.bitDepth.title,
                isEnabled: settings.format == .wav,
                onDecrease: { adjustBitDepth(-1) },
                onIncrease: { adjustBitDepth(1) }
            )
        }
    }

    private func stepField(
        title: String,
        value: String,
        isEnabled: Bool,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                stepButton(systemImage: "minus", isEnabled: isEnabled, action: onDecrease)

                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .minimumScaleFactor(0.8)

                stepButton(systemImage: "plus", isEnabled: isEnabled, action: onIncrease)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func stepButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Color.studioPanelHighlight.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(systemImage == "minus" ? "Decrease" : "Increase")
    }

    private var normalizeRow: some View {
        Toggle(isOn: $settings.normalize) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Normalize to -1 dB")
                    .font(.system(size: 12, weight: .semibold))
                Text("Raises the mix to a consistent level")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .tint(Color.studioAccent)
        .padding(12)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("FILE NAME")

            TextField("Mix", text: $settings.fileName)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(11)
                .background(Color.studioPanelHighlight.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    private var footer: some View {
        VStack(spacing: 9) {
            Text(estimatedText)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            Button {
                var final = settings
                let trimmed = final.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                final.fileName = trimmed.isEmpty ? "Mix" : trimmed
                onRender(final)
                dismiss()
            } label: {
                Text(mode.actionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color.studioAccent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(Color.studioPanel)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
    }

    private var estimatedText: String {
        let files = mode == .stems ? max(1, trackCount) : 1
        let bytes = settings.estimatedBytes(duration: duration) * Int64(files)
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        let size = formatter.string(fromByteCount: bytes)

        if mode == .stems {
            return "ESTIMATED \(files) \(files == 1 ? "FILE" : "FILES") · \(size)"
        }
        return "ESTIMATED SIZE · \(size)"
    }

    private func adjustSampleRate(_ direction: Int) {
        let all = BounceSampleRate.allCases
        guard let index = all.firstIndex(of: settings.sampleRate) else { return }
        settings.sampleRate = all[min(all.count - 1, max(0, index + direction))]
    }

    private func adjustBitDepth(_ direction: Int) {
        let all = BounceBitDepth.allCases
        guard let index = all.firstIndex(of: settings.bitDepth) else { return }
        settings.bitDepth = all[min(all.count - 1, max(0, index + direction))]
    }
}
