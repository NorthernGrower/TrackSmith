//
//  MasterEffectsView.swift
//  AI Music Studio
//

import SwiftUI

/// Reverb and delay on the master output.
struct MasterEffectsView: View {
    @ObservedObject var model: MixerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    bypassCard
                    reverbPanel
                    delayPanel

                    Text("Applied to playback and the mix bounce.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(16)
            }
            .background(Color.studioBackground)
            .navigationTitle("Master Effects")
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

    private var bypassCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MASTER FX")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(model.masterEffects.isBypassed ? Color.secondary : Color.studioAccent)

                Text(model.masterEffects.isBypassed
                    ? "Bypassed · playback and bounce stay dry"
                    : "Reverb and delay on the master output")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Toggle("", isOn: Binding(
                get: { !model.masterEffects.isBypassed },
                set: { isOn in
                    var settings = model.masterEffects
                    settings.isBypassed = !isOn
                    model.updateMasterEffects(settings)
                    model.commitSession()
                }
            ))
            .labelsHidden()
            .tint(Color.studioAccent)
            .accessibilityLabel("Master effects on or off")
        }
        .padding(14)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(model.masterEffects.isBypassed ? Color.white.opacity(0.07) : Color.studioAccent.opacity(0.35), lineWidth: 1)
        }
    }

    private var reverbPanel: some View {
        panel(title: "REVERB", detail: model.masterEffects.reverbRoomName) {
            EffectKnobView(
                title: "Mix",
                valueText: "\(Int(model.masterEffects.reverbMix * 100))%",
                value: Binding(
                    get: { model.masterEffects.reverbMix },
                    set: { newValue in
                        var settings = model.masterEffects
                        settings.reverbMix = newValue
                        model.updateMasterEffects(settings)
                    }
                ),
                range: 0...1,
                step: 0.01,
                onChange: {},
                onCommit: { model.commitSession() }
            )

            if model.isProMode {
                EffectKnobView(
                    title: "Decay",
                    valueText: String(format: "%.1f s", model.masterEffects.reverbDecay),
                    value: Binding(
                        get: { model.masterEffects.reverbDecay },
                        set: { newValue in
                            var settings = model.masterEffects
                            settings.reverbDecay = newValue
                            model.updateMasterEffects(settings)
                        }
                    ),
                    range: MasterEffectsSettings.reverbDecayRange,
                    step: 0.1,
                    onChange: {},
                    onCommit: { model.commitSession() }
                )
            }
        }
    }

    private var delayPanel: some View {
        panel(title: "DELAY", detail: "Synced to the tempo") {
            EffectKnobView(
                title: "Time",
                valueText: model.masterEffects.delayBeatLabel,
                value: Binding(
                    get: { model.masterEffects.delayTimeBeats },
                    set: { newValue in
                        var settings = model.masterEffects
                        settings.delayTimeBeats = nearestBeatChoice(newValue)
                        model.updateMasterEffects(settings)
                    }
                ),
                range: MasterEffectsSettings.delayBeatsRange,
                step: 0.25,
                onChange: {},
                onCommit: { model.commitSession() }
            )

            if model.isProMode {
                EffectKnobView(
                    title: "Feedback",
                    valueText: "\(Int(model.masterEffects.delayFeedback * 100))%",
                    value: Binding(
                        get: { model.masterEffects.delayFeedback },
                        set: { newValue in
                            var settings = model.masterEffects
                            settings.delayFeedback = newValue
                            model.updateMasterEffects(settings)
                        }
                    ),
                    range: 0...0.9,
                    step: 0.01,
                    onChange: {},
                    onCommit: { model.commitSession() }
                )
            }

            EffectKnobView(
                title: "Mix",
                valueText: "\(Int(model.masterEffects.delayMix * 100))%",
                value: Binding(
                    get: { model.masterEffects.delayMix },
                    set: { newValue in
                        var settings = model.masterEffects
                        settings.delayMix = newValue
                        model.updateMasterEffects(settings)
                    }
                ),
                range: 0...1,
                step: 0.01,
                onChange: {},
                onCommit: { model.commitSession() }
            )
        }
    }

    private func nearestBeatChoice(_ value: Double) -> Double {
        MasterEffectsSettings.delayBeatChoices.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
    }

    private func panel<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.studioAccent)

                Spacer(minLength: 4)

                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 22) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
        }
        .padding(16)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}

/// Large rotary control used by the master effects.
private struct EffectKnobView: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var onChange: () -> Void = {}
    var onCommit: () -> Void = {}

    @State private var dragStart: Double?

    private let size: CGFloat = 92

    var body: some View {
        VStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .fill(Color(white: 0.13))

                Circle()
                    .trim(from: 0.125, to: 0.125 + 0.75 * progress)
                    .stroke(Color.studioAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .padding(5)

                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)

                Rectangle()
                    .fill(Color.studioAccent)
                    .frame(width: 2.5, height: size * 0.3)
                    .offset(y: -size * 0.2)
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
                        let delta = -Double(gesture.translation.height / 170)
                        setValue(origin + delta * span)
                        onChange()
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
                    onChange()
                    onCommit()
                case .decrement:
                    setValue(value - step)
                    onChange()
                    onCommit()
                @unknown default:
                    break
                }
            }

            Text(valueText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.studioAccent)
        }
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
