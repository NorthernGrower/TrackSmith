//
//  TrackEQView.swift
//  AI Music Studio
//

import SwiftUI

struct TrackEQView: View {
    @ObservedObject var model: MixerViewModel
    let trackID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var settings: TrackEQSettings
    @State private var compressorSettings: TrackCompressorSettings
    @State private var showingPresets = false

    init(model: MixerViewModel, trackID: UUID) {
        self.model = model
        self.trackID = trackID
        let track = model.tracks.first(where: { $0.id == trackID })
        _settings = State(initialValue: track?.eqSettings ?? TrackEQSettings())
        _compressorSettings = State(initialValue: track?.compressorSettings ?? TrackCompressorSettings())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    responseDisplay

                    Toggle(isOn: $settings.isBypassed) {
                        Label("EQ Bypass", systemImage: "power")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .tint(Color.studioAccent)
                    .padding(13)
                    .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 11))

                    bandPanel(
                        title: "LOW",
                        subtitle: "Low shelf",
                        frequency: $settings.lowFrequency,
                        frequencyRange: 40...500,
                        gain: $settings.lowGain
                    )
                    bandPanel(
                        title: "MID",
                        subtitle: "Parametric",
                        frequency: $settings.midFrequency,
                        frequencyRange: 200...8_000,
                        gain: $settings.midGain
                    )
                    bandPanel(
                        title: "HIGH",
                        subtitle: "High shelf",
                        frequency: $settings.highFrequency,
                        frequencyRange: 1_000...18_000,
                        gain: $settings.highGain
                    )
                    compressorPanel
                }
                .padding(16)
            }
            .background(Color.studioBackground)
            .navigationTitle("Track EQ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingPresets = true
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .accessibilityLabel("Channel presets")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Track EQ")
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
            model.setTrackEQ(trackID, settings: newSettings)
        }
        .onChange(of: compressorSettings) { _, newSettings in
            model.setTrackCompressor(trackID, settings: newSettings)
        }
        .sheet(isPresented: $showingPresets) {
            ChannelPresetsView(model: model, initialTrackID: trackID)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    private var trackName: String {
        model.tracks.first(where: { $0.id == trackID })?.name ?? "Track"
    }

    private var responseDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FREQUENCY RESPONSE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(settings.isBypassed ? "BYPASSED" : "ACTIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(settings.isBypassed ? Color.secondary : Color.studioAccent)
            }

            Canvas { context, size in
                for line in 0..<5 {
                    let y = CGFloat(line) * size.height / 4
                    var grid = Path()
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(grid, with: .color(Color.white.opacity(line == 2 ? 0.18 : 0.07)), lineWidth: 1)
                }

                var curve = Path()
                let low = CGFloat(settings.lowGain / 12)
                let mid = CGFloat(settings.midGain / 12)
                let high = CGFloat(settings.highGain / 12)
                let points = [
                    CGPoint(x: 0, y: size.height * (0.5 - low * 0.35)),
                    CGPoint(x: size.width * 0.28, y: size.height * 0.5),
                    CGPoint(x: size.width * 0.5, y: size.height * (0.5 - mid * 0.42)),
                    CGPoint(x: size.width * 0.76, y: size.height * 0.5),
                    CGPoint(x: size.width, y: size.height * (0.5 - high * 0.35)),
                ]
                curve.move(to: points[0])
                curve.addCurve(to: points[1], control1: CGPoint(x: size.width * 0.12, y: points[0].y), control2: CGPoint(x: size.width * 0.18, y: points[1].y))
                curve.addCurve(to: points[2], control1: CGPoint(x: size.width * 0.38, y: points[1].y), control2: CGPoint(x: size.width * 0.42, y: points[2].y))
                curve.addCurve(to: points[3], control1: CGPoint(x: size.width * 0.58, y: points[2].y), control2: CGPoint(x: size.width * 0.66, y: points[3].y))
                curve.addCurve(to: points[4], control1: CGPoint(x: size.width * 0.86, y: points[3].y), control2: CGPoint(x: size.width * 0.92, y: points[4].y))
                context.stroke(curve, with: .color(settings.isBypassed ? Color.secondary : Color.studioAccent), lineWidth: 2)
            }
            .frame(height: 92)
            .overlay(alignment: .bottom) {
                HStack {
                    Text("20 Hz")
                    Spacer()
                    Text("1 kHz")
                    Spacer()
                    Text("20 kHz")
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .offset(y: 14)
            }
            .padding(.bottom, 10)
        }
        .padding(13)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var compressorPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("COMPRESSOR")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Color.studioAccent)
                    Text("Dynamics control")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.1f:1", compressorSettings.ratio))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }

            Toggle(isOn: $compressorSettings.isBypassed) {
                Text("Bypass Compressor")
                    .font(.system(size: 11, weight: .medium))
            }
            .tint(Color.studioAccent)

            compressorSlider(
                title: "Threshold",
                value: $compressorSettings.thresholdDB,
                range: -48...0,
                valueText: String(format: "%.1f dB", compressorSettings.thresholdDB)
            )
            compressorSlider(
                title: "Ratio",
                value: $compressorSettings.ratio,
                range: 1...20,
                valueText: String(format: "%.1f:1", compressorSettings.ratio)
            )
            compressorSlider(
                title: "Attack",
                value: $compressorSettings.attackMilliseconds,
                range: 0.1...100,
                valueText: String(format: "%.1f ms", compressorSettings.attackMilliseconds)
            )
            compressorSlider(
                title: "Release",
                value: $compressorSettings.releaseMilliseconds,
                range: 10...1_000,
                valueText: String(format: "%.0f ms", compressorSettings.releaseMilliseconds)
            )
        }
        .padding(13)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    private func compressorSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
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
            Slider(value: value, in: range)
        }
    }

    private func bandPanel(
        title: String,
        subtitle: String,
        frequency: Binding<Double>,
        frequencyRange: ClosedRange<Double>,
        gain: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.studioAccent)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%+.1f dB", gain.wrappedValue))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }

            HStack {
                Text("FREQ")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(frequency.wrappedValue >= 1_000
                     ? String(format: "%.1f kHz", frequency.wrappedValue / 1_000)
                     : String(format: "%.0f Hz", frequency.wrappedValue))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: frequency, in: frequencyRange)

            HStack {
                Text("GAIN")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("−12 dB")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Slider(value: gain, in: -12...12)
                    .frame(maxWidth: 220)
                Text("+12 dB")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(13)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}
