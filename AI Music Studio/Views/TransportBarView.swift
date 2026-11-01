//
//  TransportBarView.swift
//  AI Music Studio
//

import SwiftUI

struct TransportBarView: View {
    @ObservedObject var model: MixerViewModel
    @State private var showingTempoEditor = false
    @State private var tempoDraft = ""

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.studioPanelHighlight)
                        .frame(height: 2)
                    Rectangle()
                        .fill(Color.studioAccent)
                        .frame(width: max(0, geo.size.width * playheadFraction), height: 2)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 2)
            .padding(.horizontal, 15)

            HStack(spacing: 10) {
                Text(studioTimeString(displayTime))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.studioAccent)
                    .frame(width: 74, alignment: .leading)
                    .accessibilityLabel("Current time \(studioTimeString(displayTime))")

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    transportButton(symbol: "backward.end.fill", label: "Return to start") {
                        model.stop()
                    }

                    Button {
                        model.togglePlay()
                    } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(width: 48, height: 48)
                            .background(Color.studioAccent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

                    transportButton(symbol: "stop.fill", label: "Stop") {
                        model.stop()
                    }
                }
                .foregroundStyle(Color.white.opacity(0.88))
                .disabled(model.tracks.isEmpty)

                Spacer(minLength: 0)

                Text(studioTimeString(model.duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .trailing)
                    .accessibilityLabel("Session duration \(studioTimeString(model.duration))")
            }
            .padding(.horizontal, 15)
            .padding(.bottom, 8)

            tempoControls
        }
        .padding(.top, 10)
        .background(Color.studioPanel)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
        }
        .alert("Session Tempo", isPresented: $showingTempoEditor) {
            TextField("BPM", text: $tempoDraft)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) { }
            Button("Set") {
                if let bpm = Int(tempoDraft) {
                    model.setTempo(bpm)
                }
            }
        } message: {
            Text("Choose a tempo from 60 to 200 BPM.")
        }
    }

    private var tempoControls: some View {
        HStack(spacing: 8) {
            Text("TEMPO")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                model.adjustTempo(by: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 26)
                    .background(Color.studioPanelHighlight, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease tempo")

            Button {
                tempoDraft = String(model.tempoBPM)
                showingTempoEditor = true
            } label: {
                Text("\(model.tempoBPM) BPM")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .frame(width: 76, height: 26)
                    .foregroundStyle(Color.studioAccent)
                    .background(Color.studioAccent.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit session tempo, \(model.tempoBPM) beats per minute")

            Button {
                model.adjustTempo(by: 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 26)
                    .background(Color.studioPanelHighlight, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase tempo")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 15)
        .padding(.bottom, 8)
    }

    private var displayTime: TimeInterval {
        model.scrubTime ?? model.currentTime
    }

    private var playheadFraction: CGFloat {
        guard model.duration > 0 else { return 0 }
        return CGFloat(min(1, model.currentTime / model.duration))
    }

    private func transportButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Formats a time interval as mm:ss.t, the studio convention.
func studioTimeString(_ time: TimeInterval) -> String {
    let clamped = max(0, time)
    let minutes = Int(clamped) / 60
    let seconds = Int(clamped) % 60
    let tenths = Int((clamped.truncatingRemainder(dividingBy: 1)) * 10)
    return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
}
