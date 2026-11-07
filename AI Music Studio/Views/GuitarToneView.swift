//
//  GuitarToneView.swift
//  AI Music Studio
//

import SwiftUI

/// Amp and pickup controls for a guitar track, with named presets.
struct GuitarToneView: View {
    @ObservedObject var model: MixerViewModel
    let trackID: UUID

    @Environment(\.dismiss) private var dismiss

    private var track: Track? {
        model.tracks.first { $0.id == trackID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    Text("PRESETS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(GuitarTonePresets.all) { preset in
                            presetButton(preset)
                        }
                    }

                    VStack(spacing: 14) {
                        knob(
                            title: "GAIN",
                            detail: "Drive into the amp",
                            value: binding(for: \.gain)
                        )
                        knob(
                            title: "BRIGHTNESS",
                            detail: "Brightness of the speaker",
                            value: binding(for: \.brightness)
                        )
                        knob(
                            title: "PICKUP",
                            detail: "Neck to bridge position",
                            value: binding(for: \.pickup)
                        )
                    }
                    .padding(14)
                    .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 14))

                    if let track {
                        Text("\(track.voice.title)  ·  Saved with this track")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .background(Color.studioBackground)
            .navigationTitle("Guitar Tone")
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

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "guitars")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.studioAccent)
                .frame(width: 40, height: 40)
                .background(Color.studioAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(track?.guitarTone.matchedPreset?.name ?? "Custom Tone")
                    .font(.system(size: 14, weight: .semibold))
                Text(track?.name ?? "Guitar track")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private func presetButton(_ preset: GuitarTonePreset) -> some View {
        let isSelected = track?.guitarTone.matchedPreset?.id == preset.id

        return Button {
            model.updateGuitarTone(preset.tone, for: trackID)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                    .font(.system(size: 12, weight: .semibold))
                Text(preset.detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                isSelected ? Color.studioAccent.opacity(0.16) : Color.studioPanelHighlight,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? Color.studioAccent : Color.white.opacity(0.06),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.name) preset")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func knob(title: String, detail: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.studioAccent)

                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: 0...1)
                .tint(Color.studioAccent)
                .accessibilityLabel(title)
        }
    }

    private func binding(for keyPath: WritableKeyPath<GuitarTone, Double>) -> Binding<Double> {
        Binding(
            get: { track?.guitarTone[keyPath: keyPath] ?? 0.5 },
            set: { newValue in
                guard var current = track?.guitarTone else { return }
                current[keyPath: keyPath] = newValue
                model.updateGuitarTone(current, for: trackID)
            }
        )
    }
}
