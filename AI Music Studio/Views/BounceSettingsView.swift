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
    @ObservedObject var model: MixerViewModel
    let sessionName: String
    let duration: TimeInterval
    let loopStart: TimeInterval
    let loopEnd: TimeInterval
    let hasLoopRange: Bool
    let onRender: (BounceSettings, Set<UUID>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings: BounceSettings
    @State private var presets = BouncePresetStorage.load()
    @State private var namePrompt: PresetNamePrompt?
    @State private var presetNameDraft = ""
    @State private var pendingDeletePreset: BouncePreset?
    @State private var selectedTrackIDs: Set<UUID> = []

    init(
        mode: Mode,
        model: MixerViewModel,
        sessionName: String,
        duration: TimeInterval,
        loopStart: TimeInterval = 0,
        loopEnd: TimeInterval = 0,
        hasLoopRange: Bool = false,
        settings: BounceSettings,
        onRender: @escaping (BounceSettings, Set<UUID>) -> Void
    ) {
        self.mode = mode
        self.model = model
        self.sessionName = sessionName
        self.duration = duration
        self.loopStart = loopStart
        self.loopEnd = loopEnd
        self.hasLoopRange = hasLoopRange
        self.onRender = onRender
        var initialSettings = settings
        if !hasLoopRange { initialSettings.range = .entireSession }
        _settings = State(initialValue: initialSettings)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    presetsSection
                    stemTrackChecklist
                    rangeSection
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
        .onAppear {
            if mode == .stems { selectedTrackIDs = eligibleTrackIDs }
        }
        .onChange(of: settings.range) { _, _ in
            if mode == .stems { selectedTrackIDs = eligibleTrackIDs }
        }
        .alert(namePrompt?.title ?? "Bounce Preset", isPresented: namePromptBinding) {
            TextField("Preset name", text: $presetNameDraft)
            Button("Cancel", role: .cancel) { namePrompt = nil }
            Button(namePrompt?.actionTitle ?? "Save", action: commitPresetName)
                .disabled(presetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text(namePrompt?.message ?? "")
        }
        .confirmationDialog(
            "Delete this bounce preset?",
            isPresented: Binding(
                get: { pendingDeletePreset != nil },
                set: { if !$0 { pendingDeletePreset = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDeletePreset { deletePreset(pendingDeletePreset) }
            }
            Button("Cancel", role: .cancel) { pendingDeletePreset = nil }
        } message: {
            Text(pendingDeletePreset?.name ?? "")
        }
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

            Text(studioTimeString(selectedDuration))
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.studioAccent)
        }
        .padding(13)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
    }

    private var namePromptBinding: Binding<Bool> {
        Binding(
            get: { namePrompt != nil },
            set: { isPresented in if !isPresented { namePrompt = nil } }
        )
    }

    private func beginSavePreset() {
        presetNameDraft = ""
        namePrompt = .save
    }

    private func commitPresetName() {
        let name = presetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let namePrompt else { return }

        switch namePrompt {
        case .save:
            presets.append(BouncePreset(name: name, settings: settings))
        case .rename(let id):
            guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
            presets[index].name = name
        }
        BouncePresetStorage.save(presets)
        self.namePrompt = nil
    }

    private func deletePreset(_ preset: BouncePreset) {
        presets.removeAll { $0.id == preset.id }
        BouncePresetStorage.save(presets)
        pendingDeletePreset = nil
    }

    private func matchesCurrentSettings(_ preset: BouncePreset) -> Bool {
        let presetRange = preset.range == .loopRange && !hasLoopRange ? .entireSession : preset.range
        return settings.range == presetRange
            && settings.format == preset.format
            && settings.sampleRate == preset.sampleRate
            && settings.bitDepth == preset.bitDepth
            && settings.normalize == preset.normalize
    }

    private func presetSummary(_ preset: BouncePreset) -> String {
        let normalizeText = preset.normalize ? "NORMALIZE ON" : "NORMALIZE OFF"
        return "\(preset.range.title.uppercased()) · \(preset.format.title) · \(preset.sampleRate.title) · \(preset.bitDepth.title) · \(normalizeText)"
    }

    private var eligibleTracks: [Track] {
        mode == .stems ? model.eligibleStemTracks(for: settings) : []
    }

    private var eligibleTrackIDs: Set<UUID> {
        Set(eligibleTracks.map(\.id))
    }

    private var selectedEligibleTrackIDs: Set<UUID> {
        selectedTrackIDs.intersection(eligibleTrackIDs)
    }

    private var summarySubtitle: String {
        let channel = "STEREO · \(settings.sampleRate.title)"
        if mode == .stems {
            return "\(selectedEligibleTrackIDs.count)/\(eligibleTracks.count) STEMS · \(channel)"
        }
        return channel
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("PRESETS")
                Spacer()
                Button(action: beginSavePreset) {
                    Label("Save Current", systemImage: "bookmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.studioAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save current bounce settings as a preset")
            }

            if presets.isEmpty {
                Text("Save these render options to reuse them on future bounces.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 7) {
                    ForEach(presets) { preset in
                        HStack(spacing: 8) {
                            Button {
                                settings = preset.applying(to: settings, hasLoopRange: hasLoopRange)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(preset.name)
                                            .font(.system(size: 12, weight: .semibold))
                                            .lineLimit(1)
                                        if matchesCurrentSettings(preset) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(Color.studioAccent)
                                        }
                                    }
                                    Text(presetSummary(preset))
                                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Use bounce preset \(preset.name)")

                            Menu {
                                Button {
                                    presetNameDraft = preset.name
                                    namePrompt = .rename(preset.id)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    pendingDeletePreset = preset
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 32, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Actions for \(preset.name)")
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stemTrackChecklist: some View {
        if mode == .stems {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionTitle("TRACKS TO EXPORT")
                    Spacer()
                    Button("All") { selectedTrackIDs = eligibleTrackIDs }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.studioAccent)
                        .buttonStyle(.plain)
                        .disabled(eligibleTracks.isEmpty)
                    Button("None") { selectedTrackIDs = [] }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.studioAccent)
                        .buttonStyle(.plain)
                        .disabled(eligibleTracks.isEmpty)
                }

                if eligibleTracks.isEmpty {
                    Text("No tracks have audio or notes in this render range.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                } else {
                    VStack(spacing: 0) {
                        ForEach(eligibleTracks) { track in
                            let isSelected = selectedTrackIDs.contains(track.id)
                            Button {
                                if isSelected {
                                    selectedTrackIDs.remove(track.id)
                                } else {
                                    selectedTrackIDs.insert(track.id)
                                }
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(isSelected ? Color.studioAccent : Color.secondary)
                                    Text(track.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(isSelected ? "Deselect" : "Select") \(track.name) for stem export")

                            if track.id != eligibleTracks.last?.id {
                                Divider().overlay(Color.white.opacity(0.06))
                            }
                        }
                    }
                }

                if !eligibleTracks.isEmpty && selectedEligibleTrackIDs.isEmpty {
                    Text("Select at least one track to render stems.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var rangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("RENDER RANGE")
            Picker("Render range", selection: $settings.range) {
                ForEach(BounceRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                        .disabled(range == .loopRange && !hasLoopRange)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!hasLoopRange)
            if !hasLoopRange {
                Text("Set a loop on the timeline to render a loop range.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if settings.range == .loopRange {
                Text("\(studioTimeString(loopStart)) – \(studioTimeString(loopEnd))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
    }

    private var selectedDuration: TimeInterval {
        settings.range == .loopRange && hasLoopRange ? loopEnd - loopStart : duration
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
                onRender(final, selectedEligibleTrackIDs)
                dismiss()
            } label: {
                Text(mode.actionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color.studioAccent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(mode == .stems && selectedEligibleTrackIDs.isEmpty)
            .opacity(mode == .stems && selectedEligibleTrackIDs.isEmpty ? 0.45 : 1)
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
        let files = mode == .stems ? selectedEligibleTrackIDs.count : 1
        let bytes = settings.estimatedBytes(duration: selectedDuration) * Int64(files)
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



private enum PresetNamePrompt {
    case save
    case rename(UUID)

    var title: String {
        switch self {
        case .save: return "Save Bounce Preset"
        case .rename: return "Rename Bounce Preset"
        }
    }

    var actionTitle: String {
        switch self {
        case .save: return "Save"
        case .rename: return "Rename"
        }
    }

    var message: String {
        switch self {
        case .save: return "Name this set of render options."
        case .rename: return "Choose a new name for this preset."
        }
    }
}
