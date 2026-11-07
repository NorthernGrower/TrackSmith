//
//  TrackEffectsView.swift
//  AI Music Studio
//

import SwiftUI

struct TrackEffectsView: View {
    @ObservedObject var model: MixerViewModel
    let trackID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var settings: TrackEffectsRack

    init(model: MixerViewModel, trackID: UUID) {
        self.model = model
        self.trackID = trackID
        _settings = State(initialValue: model.tracks.first(where: { $0.id == trackID })?.effectsRack ?? TrackEffectsRack())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    effectPanel(title: "CHORUS", subtitle: "Modulated stereo width", isEnabled: Binding(
                        get: { !settings.chorus.isBypassed },
                        set: { settings.chorus.isBypassed = !$0 }
                    )) {
                        slider("Rate", value: $settings.chorus.rateHz, range: 0.1...5, step: 0.1, valueText: String(format: "%.1f Hz", settings.chorus.rateHz))
                        slider("Depth", value: $settings.chorus.depthMilliseconds, range: 0...12, step: 0.5, valueText: String(format: "%.1f ms", settings.chorus.depthMilliseconds))
                        slider("Mix", value: $settings.chorus.mix, range: 0...1, step: 0.01, valueText: "\(Int(settings.chorus.mix * 100))%")
                    }

                    effectPanel(title: "DISTORTION", subtitle: "Drive and blend", isEnabled: Binding(
                        get: { !settings.distortion.isBypassed },
                        set: { settings.distortion.isBypassed = !$0 }
                    )) {
                        slider("Drive", value: $settings.distortion.driveDB, range: 0...20, step: 0.5, valueText: String(format: "%.1f dB", settings.distortion.driveDB))
                        slider("Mix", value: $settings.distortion.mix, range: 0...1, step: 0.01, valueText: "\(Int(settings.distortion.mix * 100))%")
                    }

                    effectPanel(title: "STEREO DELAY", subtitle: "Tempo-synced repeats", isEnabled: Binding(
                        get: { !settings.stereoDelay.isBypassed },
                        set: { settings.stereoDelay.isBypassed = !$0 }
                    )) {
                        slider("Time", value: $settings.stereoDelay.timeBeats, range: 0.25...2, step: 0.25, valueText: String(format: "%.2g beats", settings.stereoDelay.timeBeats))
                        slider("Feedback", value: $settings.stereoDelay.feedback, range: 0...0.9, step: 0.01, valueText: "\(Int(settings.stereoDelay.feedback * 100))%")
                        slider("Mix", value: $settings.stereoDelay.mix, range: 0...1, step: 0.01, valueText: "\(Int(settings.stereoDelay.mix * 100))%")
                    }
                }
                .padding(16)
            }
            .background(Color.studioBackground)
            .navigationTitle("Track Effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Track Effects")
                            .font(.system(size: 15, weight: .semibold))
                        Text(trackName.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: settings) { _, newSettings in
            model.setTrackEffects(trackID, settings: newSettings)
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    private var trackName: String {
        model.tracks.first(where: { $0.id == trackID })?.name ?? "Track"
    }

    private func effectPanel<Content: View>(
        title: String,
        subtitle: String,
        isEnabled: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Color.studioAccent)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .tint(Color.studioAccent)
                    .accessibilityLabel("Enable \(title.lowercased())")
            }
            content()
                .disabled(!isEnabled.wrappedValue)
                .opacity(isEnabled.wrappedValue ? 1 : 0.55)
        }
        .padding(13)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                Text(valueText)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
