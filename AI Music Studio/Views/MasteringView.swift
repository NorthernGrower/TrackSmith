//
//  MasteringView.swift
//  AI Music Studio
//

import SwiftUI

/// Master EQ, bus compressor, limiter and loudness meters for the whole mix.
struct MasteringView: View {
    @ObservedObject var model: MixerViewModel
    @Environment(\.dismiss) private var dismiss

    private let knobColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    chainCard
                    targetPicker
                    loudnessCard
                    eqPanel
                    compressorPanel
                    limiterPanel

                    Text("Applied to playback and the mix bounce. Stems print the same chain.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(16)
            }
            .background(Color.studioBackground)
            .navigationTitle("Mastering")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.commitSession()
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    // MARK: - Header

    private var chainCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MASTER CHAIN")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(model.mastering.isBypassed ? Color.secondary : Color.studioAccent)

                Text(model.mastering.isBypassed
                    ? "Bypassed · EQ, compressor and limiter are off"
                    : "EQ · bus compressor · limiter")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Toggle("", isOn: Binding(
                get: { !model.mastering.isBypassed },
                set: { isOn in
                    var settings = model.mastering
                    settings.isBypassed = !isOn
                    model.updateMastering(settings)
                    model.commitSession()
                }
            ))
            .labelsHidden()
            .tint(Color.studioAccent)
            .accessibilityLabel("Master chain on or off")
        }
        .padding(14)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(model.mastering.isBypassed ? Color.white.opacity(0.07) : Color.studioAccent.opacity(0.35), lineWidth: 1)
        }
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TARGET")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(MasteringTarget.allCases) { target in
                    let isSelected = model.mastering.target == target
                    Button {
                        var settings = model.mastering
                        settings.target = target
                        settings.limiter.ceilingDB = target.truePeakCeiling
                        model.updateMastering(settings)
                        model.commitSession()
                    } label: {
                        VStack(spacing: 3) {
                            Text(target.title)
                                .font(.system(size: 11, weight: .semibold))
                            Text(String(format: "%.0f LUFS", target.loudness))
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(isSelected ? Color.black.opacity(0.7) : Color.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            isSelected ? Color.studioAccent : Color.studioPanelHighlight,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .foregroundStyle(isSelected ? Color.black : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            HStack(spacing: 6) {
                Text(model.mastering.target.detail.uppercased())
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(model.mastering.target.summary)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.studioAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(14)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    // MARK: - Loudness

    private var loudnessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("LOUDNESS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button {
                    model.resetLoudness()
                } label: {
                    Text("RESET")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.studioAccent)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset loudness measurement")
            }

            HStack(alignment: .top, spacing: 12) {
                loudnessCell(
                    title: "INTEGRATED",
                    value: model.loudness.integrated,
                    unit: "LUFS",
                    target: model.mastering.target.loudness,
                    range: -36...0
                )
                loudnessCell(
                    title: "SHORT-TERM",
                    value: model.loudness.shortTerm,
                    unit: "LUFS",
                    target: model.mastering.target.loudness,
                    range: -36...0
                )
                loudnessCell(
                    title: "TRUE PEAK",
                    value: model.loudness.truePeak,
                    unit: "dBTP",
                    target: model.mastering.target.truePeakCeiling,
                    range: -12...0,
                    isPeak: true
                )
            }
        }
        .padding(14)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    private func loudnessCell(
        title: String,
        value: Double?,
        unit: String,
        target: Double,
        range: ClosedRange<Double>,
        isPeak: Bool = false
    ) -> some View {
        let tint = tint(for: value, target: target, isPeak: isPeak)
        return VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(value.map { String(format: "%.1f", $0) } ?? "—")
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())

            Text(unit)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)

            GeometryReader { proxy in
                let span = max(0.001, range.upperBound - range.lowerBound)
                let progress = value.map { min(1, max(0, ($0 - range.lowerBound) / span)) } ?? 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(3, proxy.size.width * progress))
                }
            }
            .frame(height: 4)

            Text(String(format: "TARGET %.0f", target))
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tint(for value: Double?, target: Double, isPeak: Bool) -> Color {
        guard let value else { return Color.secondary }
        if isPeak {
            return value > target ? Color.red : Color.studioAccent
        }
        return abs(value - target) <= 3 ? Color.studioAccent : Color.secondary
    }

    // MARK: - Chain panels

    private var eqPanel: some View {
        panel(
            title: "MASTER EQ",
            subtitle: "Three bands",
            isBypassed: model.mastering.eq.isBypassed,
            onToggleBypass: {
                update { $0.eq.isBypassed.toggle() }
                model.commitSession()
            }
        ) {
            LazyVGrid(columns: knobColumns, spacing: 14) {
                MasteringKnobView(
                    title: "Low",
                    valueText: dbText(model.mastering.eq.lowGain),
                    value: Binding(
                        get: { model.mastering.eq.lowGain },
                        set: { newValue in update { $0.eq.lowGain = newValue } }
                    ),
                    range: MasterEQSettings.gainRange,
                    step: 0.5,
                    onCommit: { model.commitSession() }
                )
                MasteringKnobView(
                    title: "Mid freq",
                    valueText: "\(Int(model.mastering.eq.midFrequency)) Hz",
                    value: Binding(
                        get: { model.mastering.eq.midFrequency },
                        set: { newValue in update { $0.eq.midFrequency = newValue } }
                    ),
                    range: MasterEQSettings.midFrequencyRange,
                    step: 10,
                    onCommit: { model.commitSession() }
                )
                MasteringKnobView(
                    title: "Mid gain",
                    valueText: dbText(model.mastering.eq.midGain),
                    value: Binding(
                        get: { model.mastering.eq.midGain },
                        set: { newValue in update { $0.eq.midGain = newValue } }
                    ),
                    range: MasterEQSettings.gainRange,
                    step: 0.5,
                    onCommit: { model.commitSession() }
                )
                MasteringKnobView(
                    title: "High",
                    valueText: dbText(model.mastering.eq.highGain),
                    value: Binding(
                        get: { model.mastering.eq.highGain },
                        set: { newValue in update { $0.eq.highGain = newValue } }
                    ),
                    range: MasterEQSettings.gainRange,
                    step: 0.5,
                    onCommit: { model.commitSession() }
                )
            }
        }
    }

    private var compressorPanel: some View {
        panel(
            title: "BUS COMPRESSOR",
            subtitle: String(format: "%.1f:1 glue", model.mastering.compressor.ratio),
            isBypassed: model.mastering.compressor.isBypassed,
            onToggleBypass: {
                update { $0.compressor.isBypassed.toggle() }
                model.commitSession()
            }
        ) {
            LazyVGrid(columns: knobColumns, spacing: 14) {
                MasteringKnobView(
                    title: "Threshold",
                    valueText: String(format: "%.0f dB", model.mastering.compressor.thresholdDB),
                    value: Binding(
                        get: { model.mastering.compressor.thresholdDB },
                        set: { newValue in update { $0.compressor.thresholdDB = newValue } }
                    ),
                    range: MasterCompressorSettings.thresholdRange,
                    step: 0.5,
                    onCommit: { model.commitSession() }
                )
                MasteringKnobView(
                    title: "Ratio",
                    valueText: String(format: "%.1f:1", model.mastering.compressor.ratio),
                    value: Binding(
                        get: { model.mastering.compressor.ratio },
                        set: { newValue in update { $0.compressor.ratio = newValue } }
                    ),
                    range: MasterCompressorSettings.ratioRange,
                    step: 0.1,
                    onCommit: { model.commitSession() }
                )
                MasteringKnobView(
                    title: "Attack",
                    valueText: String(format: "%.0f ms", model.mastering.compressor.attackMilliseconds),
                    value: Binding(
                        get: { model.mastering.compressor.attackMilliseconds },
                        set: { newValue in update { $0.compressor.attackMilliseconds = newValue } }
                    ),
                    range: MasterCompressorSettings.attackRange,
                    step: 1,
                    onCommit: { model.commitSession() }
                )
                MasteringKnobView(
                    title: "Release",
                    valueText: String(format: "%.0f ms", model.mastering.compressor.releaseMilliseconds),
                    value: Binding(
                        get: { model.mastering.compressor.releaseMilliseconds },
                        set: { newValue in update { $0.compressor.releaseMilliseconds = newValue } }
                    ),
                    range: MasterCompressorSettings.releaseRange,
                    step: 5,
                    onCommit: { model.commitSession() }
                )
            }
        }
    }

    private var limiterPanel: some View {
        panel(
            title: "LIMITER",
            subtitle: String(format: "Ceiling %.1f dB", model.mastering.limiter.ceilingDB),
            isBypassed: model.mastering.limiter.isBypassed,
            onToggleBypass: {
                update { $0.limiter.isBypassed.toggle() }
                model.commitSession()
            }
        ) {
            LazyVGrid(columns: knobColumns, spacing: 14) {
                MasteringKnobView(
                    title: "Drive",
                    valueText: dbText(model.mastering.limiter.driveDB),
                    value: Binding(
                        get: { model.mastering.limiter.driveDB },
                        set: { newValue in update { $0.limiter.driveDB = newValue } }
                    ),
                    range: MasterLimiterSettings.driveRange,
                    step: 0.5,
                    onCommit: { model.commitSession() }
                )
                MasteringKnobView(
                    title: "Ceiling",
                    valueText: String(format: "%.1f dB", model.mastering.limiter.ceilingDB),
                    value: Binding(
                        get: { model.mastering.limiter.ceilingDB },
                        set: { newValue in update { $0.limiter.ceilingDB = newValue } }
                    ),
                    range: MasterLimiterSettings.ceilingRange,
                    step: 0.1,
                    onCommit: { model.commitSession() }
                )
                MasteringKnobView(
                    title: "Release",
                    valueText: String(format: "%.0f ms", model.mastering.limiter.releaseMilliseconds),
                    value: Binding(
                        get: { model.mastering.limiter.releaseMilliseconds },
                        set: { newValue in update { $0.limiter.releaseMilliseconds = newValue } }
                    ),
                    range: MasterLimiterSettings.releaseRange,
                    step: 5,
                    onCommit: { model.commitSession() }
                )
            }
        }
    }

    private func update(_ transform: (inout MasteringSettings) -> Void) {
        var settings = model.mastering
        transform(&settings)
        model.updateMastering(settings)
    }

    private func dbText(_ value: Double) -> String {
        String(format: "%+.1f dB", value)
    }

    private func panel<Content: View>(
        title: String,
        subtitle: String,
        isBypassed: Bool,
        onToggleBypass: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(isBypassed ? Color.secondary : Color.studioAccent)

                Spacer(minLength: 4)

                Text(subtitle)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button(action: onToggleBypass) {
                    Text(isBypassed ? "BYP" : "ON")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .frame(width: 36, height: 24)
                        .foregroundStyle(isBypassed ? Color.secondary : Color.black)
                        .background(
                            isBypassed ? Color.studioPanelHighlight : Color.studioAccent,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) on or bypassed")
            }

            content()
        }
        .padding(16)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}

/// Rotary control used by the mastering chain.
private struct MasteringKnobView: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var onCommit: () -> Void = {}

    @State private var dragStart: Double?

    private let size: CGFloat = 64

    var body: some View {
        VStack(spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            ZStack {
                Circle()
                    .fill(Color(white: 0.13))

                Circle()
                    .trim(from: 0.125, to: 0.125 + 0.75 * progress)
                    .stroke(Color.studioAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .padding(4)

                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)

                Rectangle()
                    .fill(Color.studioAccent)
                    .frame(width: 2, height: size * 0.28)
                    .offset(y: -size * 0.18)
                    .rotationEffect(.degrees(-135 + 270 * Double(progress)))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if dragStart == nil { dragStart = value }
                        let origin = dragStart ?? value
                        let span = range.upperBound - range.lowerBound
                        let delta = -Double(gesture.translation.height / 150)
                        setValue(origin + delta * span)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        onCommit()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityValue(valueText)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    setValue(value + step)
                    onCommit()
                case .decrement:
                    setValue(value - step)
                    onCommit()
                @unknown default:
                    break
                }
            }

            Text(valueText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.studioAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var progress: CGFloat {
        let span = max(0.0001, range.upperBound - range.lowerBound)
        return CGFloat(min(1, max(0, (value - range.lowerBound) / span)))
    }

    private func setValue(_ raw: Double) {
        let clamped = min(range.upperBound, max(range.lowerBound, raw))
        let snapped = (clamped / step).rounded() * step
        value = min(range.upperBound, max(range.lowerBound, snapped))
    }
}
