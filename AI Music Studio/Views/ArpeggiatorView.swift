//
//  ArpeggiatorView.swift
//  AI Music Studio
//

import SwiftUI

/// Settings for the arpeggiator on one instrument track's piano roll.
struct ArpeggiatorView: View {
    @ObservedObject var model: MixerViewModel
    let trackID: UUID

    @Environment(\.dismiss) private var dismiss

    private var settings: ArpeggiatorSettings {
        model.tracks.first(where: { $0.id == trackID })?.arpeggiator ?? ArpeggiatorSettings()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    toggleCard
                    patternPanel
                    ratePanel
                    shapePanel

                    Text("Arpeggiates held chord notes during playback, freezing and the mix bounce.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(16)
            }
            .background(Color.studioBackground)
            .navigationTitle("Arpeggiator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    private var toggleCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ARPEGGIATOR")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(settings.isEnabled ? Color.studioAccent : Color.secondary)

                Text(settings.isEnabled
                    ? "\(settings.pattern.title) · \(settings.rate.title)"
                    : "Off · the notes play as drawn")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Toggle("", isOn: binding(\.isEnabled))
                .labelsHidden()
                .tint(Color.studioAccent)
                .accessibilityLabel("Arpeggiator on or off")
        }
        .padding(14)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(settings.isEnabled ? Color.studioAccent.opacity(0.35) : Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var patternPanel: some View {
        panel(title: "PATTERN") {
            Picker("Pattern", selection: binding(\.pattern)) {
                ForEach(ArpeggiatorPattern.allCases) { pattern in
                    Text(pattern.title).tag(pattern)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.isEnabled)
            .accessibilityLabel("Arpeggiator pattern")
        }
    }

    private var ratePanel: some View {
        panel(title: "RATE") {
            Picker("Rate", selection: binding(\.rate)) {
                ForEach(ArpeggiatorRate.allCases) { rate in
                    Text(rate.title).tag(rate)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.isEnabled)
            .accessibilityLabel("Arpeggiator rate")
        }
    }

    private var shapePanel: some View {
        panel(title: "SHAPE") {
            HStack(spacing: 10) {
                Text("OCTAVES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Text("\(settings.octaveRange)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.studioAccent)

                Stepper("", value: binding(\.octaveRange), in: ArpeggiatorSettings.octaveRangeRange)
                    .labelsHidden()
                    .disabled(!settings.isEnabled)
                    .accessibilityLabel("Arpeggiator octave range")
            }

            sliderRow(
                title: "GATE",
                value: binding(\.gate),
                range: ArpeggiatorSettings.gateRange,
                text: "\(Int((settings.gate * 100).rounded()))%"
            )

            sliderRow(
                title: "SWING",
                value: binding(\.swing),
                range: ArpeggiatorSettings.swingRange,
                text: "\(Int((settings.swing * 100).rounded()))%"
            )
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Text(text)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range)
                .tint(Color.studioAccent)
                .disabled(!settings.isEnabled)
        }
    }

    private func panel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.studioAccent)

            content()
        }
        .padding(14)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<ArpeggiatorSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                var copy = settings
                copy[keyPath: keyPath] = newValue
                model.updateArpeggiator(copy, for: trackID)
            }
        )
    }
}
