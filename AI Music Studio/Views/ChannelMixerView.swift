//
//  ChannelMixerView.swift
//  AI Music Studio
//

import Foundation
import SwiftUI

/// Full channel mixer: one vertical strip per track plus the master output.
struct ChannelMixerView: View {
    @ObservedObject var model: MixerViewModel
    @Environment(\.dismiss) private var dismiss

    private let stripWidth: CGFloat = 84
    private let masterWidth: CGFloat = 96
    private let meterHeight: CGFloat = 168

    var body: some View {
        NavigationStack {
            Group {
                if model.tracks.isEmpty {
                    ContentUnavailableView(
                        "No Tracks Yet",
                        systemImage: "slider.vertical.3",
                        description: Text("Import audio or split a song into stems to fill the mixer.")
                    )
                } else {
                    mixerBoard
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.studioBackground)
            .navigationTitle("Mixer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { transportFooter }
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    private var mixerBoard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(model.sessionName.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(model.tracks.count) \(model.tracks.count == 1 ? "CHANNEL" : "CHANNELS")")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.studioAccent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 9) {
                    ForEach(Array(model.tracks.enumerated()), id: \.element.id) { index, track in
                        channelStrip(track, index: index)
                    }

                    masterStrip
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
    }

    // MARK: - Channel strips

    private func channelStrip(_ track: Track, index: Int) -> some View {
        let color = Color.studioTrackColor(for: index)

        return VStack(spacing: 8) {
            VStack(spacing: 3) {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)

                Text(track.name)
                    .font(.system(size: 10, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .frame(height: 37)

            PanKnobView(
                value: Binding(
                    get: { track.pan },
                    set: { model.setPan(track.id, $0) }
                ),
                color: color,
                onCommit: { model.commitSession() }
            )
            .frame(width: 36, height: 36)

            Text(panLabel(track.pan))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(height: 10)

            HStack(spacing: 6) {
                CompactFaderView(
                    value: Binding(
                        get: { track.volume },
                        set: { model.setVolume(track.id, $0) }
                    ),
                    onCommit: { model.commitSession() },
                    color: color
                )
                .frame(width: 28, height: meterHeight)
                .accessibilityLabel("Volume for \(track.name)")

                MiniLevelMeterView(level: model.levels[track.id] ?? 0, color: color)
                    .frame(width: 5, height: meterHeight)
                    .accessibilityHidden(true)
            }

            Text(dbLabel(track.volume))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.85))
                .frame(height: 10)

            HStack(spacing: 5) {
                stripToggle("M", isOn: track.isMuted, accessibilityLabel: "Mute \(track.name)") {
                    model.toggleMute(track.id)
                }
                stripToggle("S", isOn: track.isSoloed, accessibilityLabel: "Solo \(track.name)") {
                    model.toggleSolo(track.id)
                }
            }
            .frame(height: 22)
        }
        .padding(.vertical, 12)
        .frame(width: stripWidth)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Channel \(track.name)")
    }

    private var masterStrip: some View {
        VStack(spacing: 8) {
            Text("MASTER")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.studioAccent)
                .frame(height: 37)

            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.studioAccent)
                .frame(width: 36, height: 36)
                .background(Color.studioAccent.opacity(0.12), in: Circle())

            Text("OUTPUT")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(height: 10)

            HStack(spacing: 6) {
                CompactFaderView(
                    value: Binding(
                        get: { model.masterVolume },
                        set: { model.setMasterVolume($0) }
                    ),
                    onCommit: { model.commitSession() },
                    color: .studioAccent
                )
                .frame(width: 34, height: meterHeight)
                .accessibilityLabel("Master output level")

                MiniLevelMeterView(level: model.masterLevel, color: .studioAccent)
                    .frame(width: 6, height: meterHeight)
                    .accessibilityHidden(true)
            }

            Text(dbLabel(model.masterVolume))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.9))
                .frame(height: 10)

            Text("ST")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(width: masterWidth)
        .background(Color.studioPanelHighlight.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.studioAccent.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Master channel")
    }

    // MARK: - Transport

    private var transportFooter: some View {
        HStack(spacing: 12) {
            Button {
                model.togglePlay()
            } label: {
                Image(systemName: model.isPlaying || model.isCountingIn ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 44, height: 44)
                    .background(Color.studioAccent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.tracks.isEmpty)
            .accessibilityLabel(model.isCountingIn ? "Cancel count-in" : (model.isPlaying ? "Pause" : "Play"))

            Button {
                model.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 36, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.tracks.isEmpty)
            .accessibilityLabel("Stop")

            Text(studioTimeString(model.currentTime))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.studioAccent)

            Spacer(minLength: 0)

            Text(studioTimeString(model.duration))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.studioPanel)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
        }
    }

    private func stripToggle(
        _ title: String,
        isOn: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .frame(width: 30, height: 22)
                .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.75))
                .background(isOn ? Color.studioAccent : Color.studioPanelHighlight.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func dbLabel(_ volume: Float) -> String {
        let clamped = min(1, max(0, volume))
        guard clamped > 0.0001 else { return "-∞ dB" }
        return String(format: "%.1f dB", 20 * log10(clamped))
    }

    private func panLabel(_ pan: Float) -> String {
        let clamped = min(1, max(-1, pan))
        guard abs(clamped) >= 0.005 else { return "C" }
        return clamped < 0 ? "L\(Int(abs(clamped) * 100))" : "R\(Int(clamped * 100))"
    }
}

/// Rotary pan control: drag horizontally to place a track in the stereo field.
private struct PanKnobView: View {
    @Binding var value: Float
    var color: Color = .studioAccent
    var onCommit: () -> Void = {}

    @State private var dragStart: Float?

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                Circle()
                    .fill(Color(white: 0.17))
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                Rectangle()
                    .fill(color)
                    .frame(width: 2, height: size * 0.26)
                    .offset(y: -size * 0.20)
                    .rotationEffect(.degrees(Double(value) * 135))
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if dragStart == nil {
                            dragStart = value
                        }
                        let origin = dragStart ?? value
                        value = min(1, max(-1, origin + Float(gesture.translation.width / 80)))
                    }
                    .onEnded { _ in
                        dragStart = nil
                        onCommit()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Pan")
            .accessibilityValue(panText(value))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value = min(1, value + 0.1)
                case .decrement: value = max(-1, value - 0.1)
                @unknown default: break
                }
                onCommit()
            }
        }
    }

    private func panText(_ pan: Float) -> String {
        let clamped = min(1, max(-1, pan))
        guard abs(clamped) >= 0.005 else { return "Center" }
        return clamped < 0 ? "Left \(Int(abs(clamped) * 100)) percent" : "Right \(Int(clamped * 100)) percent"
    }
}
