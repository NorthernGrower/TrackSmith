//
//  PianoRollView.swift
//  AI Music Studio
//

import Foundation
import SwiftUI

/// Sequencer grid where notes for the built-in synth are drawn for one track.
struct PianoRollView: View {
    @ObservedObject var model: MixerViewModel
    let trackID: UUID

    @Environment(\.dismiss) private var dismiss

    @State private var selectedNoteID: UUID?
    @State private var noteStep = PianoRollStep.eighth
    @State private var chordType = ChordType.single
    @State private var dragOrigin: SynthNote?
    @State private var resizeOrigin: SynthNote?

    private let rowHeight: CGFloat = 24
    private let keyboardWidth: CGFloat = 46
    private let beatWidth: CGFloat = 76

    private var pitchRows: [Int] {
        Array((SynthNote.lowestPitch...SynthNote.highestPitch).reversed())
    }

    var body: some View {
        NavigationStack {
            Group {
                if let track {
                    editor(track)
                } else {
                    ContentUnavailableView(
                        "Track Removed",
                        systemImage: "pianokeys",
                        description: Text("This track is no longer part of the session.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.studioBackground)
            .navigationTitle("Piano Roll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        if let id = selectedNoteID {
                            model.deleteSynthNote(trackID: trackID, noteID: id)
                            selectedNoteID = nil
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedNoteID == nil)
                    .accessibilityLabel("Delete selected note")
                }
            }
            .safeAreaInset(edge: .bottom) { transportFooter }
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    // MARK: - Layout

    private func editor(_ track: Track) -> some View {
        VStack(spacing: 0) {
            header(track)

            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    keyboard

                    ScrollView(.horizontal, showsIndicators: false) {
                        grid(track)
                            .frame(width: contentWidth, height: gridHeight)
                    }
                }
            }
        }
    }

    private func header(_ track: Track) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(Color.studioAccent)
                        .lineLimit(1)
                    Text("\(model.tempoBPM) BPM  ·  TAP GRID TO ADD")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Picker("Note length", selection: $noteStep) {
                    ForEach(PianoRollStep.allCases) { step in
                        Text(step.rawValue).tag(step)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 148)
                .accessibilityLabel("Note length")
            }

            HStack(spacing: 10) {
                Text("CHORD")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                Picker("Chord type", selection: $chordType) {
                    ForEach(ChordType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Chord type")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.studioPanel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    private var keyboard: some View {
        VStack(spacing: 0) {
            ForEach(pitchRows, id: \.self) { pitch in
                ZStack(alignment: .trailing) {
                    Rectangle()
                        .fill(SynthNote.isBlackKey(pitch) ? Color(white: 0.15) : Color(white: 0.82))

                    if pitch % 12 == 0 {
                        Text(SynthNote.name(for: pitch))
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.black.opacity(0.7))
                            .padding(.trailing, 4)
                    }
                }
                .frame(height: rowHeight)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.black.opacity(0.18)).frame(height: 0.5)
                }
            }
        }
        .frame(width: keyboardWidth)
    }

    private func grid(_ track: Track) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                for pitch in SynthNote.lowestPitch...SynthNote.highestPitch {
                    let y = CGFloat(SynthNote.highestPitch - pitch) * rowHeight
                    if SynthNote.isBlackKey(pitch) {
                        context.fill(
                            Path(CGRect(x: 0, y: y, width: size.width, height: rowHeight)),
                            with: .color(Color.white.opacity(0.03))
                        )
                    }
                    var rowLine = Path()
                    rowLine.move(to: CGPoint(x: 0, y: y))
                    rowLine.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(rowLine, with: .color(Color.white.opacity(0.05)), lineWidth: 1)
                }

                var beatIndex = 0
                var x: CGFloat = 0
                while x <= size.width {
                    let isBar = beatIndex % 4 == 0
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(
                        line,
                        with: .color(isBar ? Color.white.opacity(0.22) : Color.white.opacity(0.08)),
                        lineWidth: isBar ? 1.2 : 1
                    )

                    if isBar {
                        context.draw(
                            Text("\(beatIndex / 4 + 1)")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary),
                            at: CGPoint(x: x + 3, y: 6),
                            anchor: .leading
                        )
                    }

                    beatIndex += 1
                    x += beatWidth
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        selectedNoteID = model.addSynthChord(
                            trackID: trackID,
                            pitch: pitch(atY: value.location.y),
                            startTime: snappedTime(atX: value.location.x),
                            duration: snapDuration,
                            chordType: chordType,
                            snapInterval: snapDuration
                        ).first
                    }
            )

            ForEach(track.notes) { note in
                noteLayer(note)
            }

            Rectangle()
                .fill(Color.studioAccent)
                .frame(width: 1.5, height: gridHeight)
                .offset(x: CGFloat(model.currentTime) * pixelsPerSecond)
                .allowsHitTesting(false)
        }
    }

    private func noteLayer(_ note: SynthNote) -> some View {
        let isSelected = selectedNoteID == note.id
        let width = max(12, CGFloat(note.duration) * pixelsPerSecond)
        let y = CGFloat(SynthNote.highestPitch - note.pitch) * rowHeight

        return RoundedRectangle(cornerRadius: 4)
            .fill(Color.studioAccent.opacity(isSelected ? 0.95 : 0.72))
            .overlay(alignment: .bottomLeading) {
                Text(SynthNote.name(for: note.pitch))
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .padding(.leading, 3)
                    .padding(.bottom, 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.white.opacity(0.85) : Color.clear, lineWidth: 1)
            }
            .overlay(alignment: .trailing) {
                if isSelected {
                    resizeHandle(note)
                }
            }
            .frame(width: width, height: rowHeight - 3)
            .offset(x: CGFloat(note.startTime) * pixelsPerSecond, y: y + 1.5)
            .contentShape(Rectangle())
            .onTapGesture { selectedNoteID = note.id }
            .highPriorityGesture(moveGesture(note))
            .accessibilityLabel("Note \(SynthNote.name(for: note.pitch))")
    }

    private func resizeHandle(_ note: SynthNote) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.4))
            .frame(width: 6, height: rowHeight - 9)
            .frame(width: 16, height: rowHeight - 3)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        selectedNoteID = note.id
                        if resizeOrigin == nil { resizeOrigin = note }
                        guard let origin = resizeOrigin else { return }
                        model.resizeSynthNote(
                            trackID: trackID,
                            noteID: origin.id,
                            duration: origin.duration + Double(value.translation.width / pixelsPerSecond),
                            snapInterval: snapDuration
                        )
                    }
                    .onEnded { _ in
                        resizeOrigin = nil
                        model.commitSession()
                    }
            )
            .accessibilityLabel("Resize note")
    }

    private func moveGesture(_ note: SynthNote) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                selectedNoteID = note.id
                if dragOrigin == nil { dragOrigin = note }
                guard let origin = dragOrigin else { return }

                let newStart = origin.startTime + Double(value.translation.width / pixelsPerSecond)
                let pitchDelta = -Int((value.translation.height / rowHeight).rounded())
                model.moveSynthNote(
                    trackID: trackID,
                    noteID: origin.id,
                    startTime: newStart,
                    pitch: origin.pitch + pitchDelta,
                    snapInterval: snapDuration
                )
            }
            .onEnded { _ in
                dragOrigin = nil
                model.commitSession()
            }
    }

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

            Text("\(model.tempoBPM) BPM")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.studioPanel)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
        }
    }

    // MARK: - Geometry helpers

    private var track: Track? {
        model.tracks.first { $0.id == trackID }
    }

    private var beatDuration: TimeInterval {
        60.0 / Double(max(60, model.tempoBPM))
    }

    private var snapDuration: TimeInterval {
        beatDuration / noteStep.divisionsPerBeat
    }

    private var pixelsPerSecond: CGFloat {
        beatWidth / CGFloat(beatDuration)
    }

    private var gridHeight: CGFloat {
        CGFloat(SynthNote.highestPitch - SynthNote.lowestPitch + 1) * rowHeight
    }

    private var contentWidth: CGFloat {
        let beats = max(16, ceil(max(model.duration, beatDuration * 16) / beatDuration) + 4)
        return CGFloat(beats) * beatWidth
    }

    private func pitch(atY y: CGFloat) -> Int {
        let row = Int(floor(max(0, y) / rowHeight))
        return min(SynthNote.highestPitch, max(SynthNote.lowestPitch, SynthNote.highestPitch - row))
    }

    private func snappedTime(atX x: CGFloat) -> TimeInterval {
        let seconds = Double(max(0, x) / pixelsPerSecond)
        return max(0, (seconds / snapDuration).rounded() * snapDuration)
    }
}

private enum PianoRollStep: String, CaseIterable, Identifiable {
    case quarter = "1/4"
    case eighth = "1/8"
    case sixteenth = "1/16"

    var id: String { rawValue }

    var divisionsPerBeat: Double {
        switch self {
        case .quarter: return 1
        case .eighth: return 2
        case .sixteenth: return 4
        }
    }
}
