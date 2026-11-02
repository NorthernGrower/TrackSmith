//
//  TransportBarView.swift
//  AI Music Studio
//

import SwiftUI

struct TransportBarView: View {
    @ObservedObject var model: MixerViewModel
    @State private var showingTempoEditor = false
    @State private var tempoDraft = ""
    @State private var showingSectionName = false
    @State private var sectionDraft = ""
    @State private var newSectionID: UUID?

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
                Text(model.isCountingIn ? "COUNT-IN \(model.countInBeatsRemaining)" : studioTimeString(displayTime))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.studioAccent)
                    .frame(width: 84, alignment: .leading)
                    .accessibilityLabel(
                        model.isCountingIn
                            ? "Count-in, \(model.countInBeatsRemaining) beats remaining"
                            : "Current time \(studioTimeString(displayTime))"
                    )

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    transportButton(symbol: "backward.end.fill", label: "Return to start") {
                        model.stop()
                    }

                    Button {
                        model.togglePlay()
                    } label: {
                        Image(systemName: model.isPlaying || model.isCountingIn ? "pause.fill" : "play.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(width: 48, height: 48)
                            .background(Color.studioAccent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.isCountingIn ? "Cancel count-in" : (model.isPlaying ? "Pause" : "Play"))

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

            loopControls

            metronomeControls

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
        .alert("Name Section", isPresented: $showingSectionName) {
            TextField("Section name", text: $sectionDraft)
            Button("Cancel", role: .cancel) { newSectionID = nil }
            Button("Save") {
                if let id = newSectionID {
                    model.renameSection(id, to: sectionDraft)
                }
                newSectionID = nil
            }
        } message: {
            Text("Give this part of the song a name.")
        }
    }

    private var loopControls: some View {
        HStack(spacing: 8) {
            Button {
                model.toggleLoop()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "repeat")
                        .font(.system(size: 10, weight: .bold))
                    Text(model.isLoopEnabled ? "LOOP ON" : "LOOP")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                }
                .foregroundStyle(model.isLoopEnabled ? Color.black : Color.white.opacity(0.7))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    model.isLoopEnabled ? Color.studioAccent : Color.studioPanelHighlight,
                    in: RoundedRectangle(cornerRadius: 7)
                )
            }
            .buttonStyle(.plain)
            .disabled(!model.hasLoopRange)
            .opacity(model.hasLoopRange ? 1 : 0.4)
            .accessibilityLabel(model.isLoopEnabled ? "Turn loop playback off" : "Turn loop playback on")
            .accessibilityAddTraits(model.isLoopEnabled ? .isSelected : [])

            Text(model.hasLoopRange
                ? "\(studioTimeString(model.loopStart)) – \(studioTimeString(model.loopEnd))"
                : "Drag markers on the ruler")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                addSection()
            } label: {
                Text("+ SECTION")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Color.studioAccent)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Color.studioAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(model.duration <= 0)
            .accessibilityLabel("Add a song section at the playhead")
        }
        .padding(.horizontal, 15)
        .padding(.bottom, 8)
    }

    private func addSection() {
        guard let id = model.addSection(at: model.currentTime) else { return }
        newSectionID = id
        sectionDraft = model.sections.first(where: { $0.id == id })?.name ?? "Section"
        showingSectionName = true
    }

    private var metronomeControls: some View {
        HStack(spacing: 8) {
            Button {
                model.toggleMetronome()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "metronome")
                        .font(.system(size: 10, weight: .bold))
                    Text(model.isMetronomeEnabled ? "CLICK ON" : "CLICK")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                }
                .foregroundStyle(model.isMetronomeEnabled ? Color.black : Color.white.opacity(0.7))
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(
                    model.isMetronomeEnabled ? Color.studioAccent : Color.studioPanelHighlight,
                    in: RoundedRectangle(cornerRadius: 7)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isMetronomeEnabled ? "Turn metronome off" : "Turn metronome on")
            .accessibilityAddTraits(model.isMetronomeEnabled ? .isSelected : [])

            Slider(
                value: Binding(
                    get: { Double(model.metronomeLevel) },
                    set: { model.setMetronomeLevel(Float($0)) }
                ),
                in: 0...1,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        model.commitSession()
                    }
                }
            )
            .frame(width: 86)
            .tint(Color.studioAccent)
            .accessibilityLabel("Metronome level")

            Button {
                model.toggleCountIn()
            } label: {
                Text(model.isCountInEnabled ? "COUNT-IN ON" : "COUNT-IN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(model.isCountInEnabled ? Color.black : Color.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(
                        model.isCountInEnabled ? Color.studioAccent : Color.studioPanelHighlight,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isCountInEnabled ? "Turn count-in off" : "Turn count-in on")
            .accessibilityAddTraits(model.isCountInEnabled ? .isSelected : [])

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.bottom, 8)
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
