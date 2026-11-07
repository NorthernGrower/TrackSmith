//
//  PianoRollView.swift
//  AI Music Studio
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Sequencer grid where notes for the built-in synth are drawn for one track.
struct PianoRollView: View {
    @ObservedObject var model: MixerViewModel
    let trackID: UUID

    @Environment(\.dismiss) private var dismiss

    @State private var selectedNoteIDs: Set<UUID> = []
    @State private var noteStep = PianoRollStep.eighth
    @State private var chordType = ChordType.single
    @State private var quantizeStrength: Double = 0.75
    @State private var showingSounds = false
    @State private var showingGuitarTone = false
    @State private var showingArpeggiator = false
    @State private var showingMIDIImporter = false
    @State private var showingMIDIImportChoice = false
    @State private var pendingMIDIImport: MIDIFile.Imported?
    @State private var midiShareItem: ShareItem?
    @State private var midiMessage: String?
    @State private var dragOrigin: SynthNote?
    @State private var resizeOrigin: SynthNote?
    @State private var velocityOrigin: Float?

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
                    Button {
                        showingArpeggiator = true
                    } label: {
                        Image(systemName: (track?.arpeggiator.isEnabled ?? false)
                            ? "arrow.up.arrow.down.circle.fill"
                            : "arrow.up.arrow.down.circle")
                    }
                    .accessibilityLabel("Arpeggiator")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingMIDIImporter = true
                        } label: {
                            Label("Import MIDI…", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            model.exportMIDI(trackID: trackID)
                        } label: {
                            Label("Export MIDI", systemImage: "square.and.arrow.up")
                        }
                        .disabled(track?.notes.isEmpty ?? true)
                    } label: {
                        Image(systemName: "music.note.list")
                    }
                    .accessibilityLabel("MIDI import and export")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        model.deleteSynthNotes(trackID: trackID, noteIDs: selectedNoteIDs)
                        selectedNoteIDs.removeAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedNoteIDs.isEmpty)
                    .accessibilityLabel("Delete selected notes")
                }
            }
            .safeAreaInset(edge: .bottom) { transportFooter }
            .sheet(isPresented: $showingSounds) {
                InstrumentSoundView(model: model, trackID: trackID)
                    .studioAgentAccess(context: "Instrument Sound")
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingGuitarTone) {
                GuitarToneView(model: model, trackID: trackID)
                    .studioAgentAccess(context: "Guitar Tone")
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingArpeggiator) {
                ArpeggiatorView(model: model, trackID: trackID)
                    .studioAgentAccess(context: "Arpeggiator")
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .fileImporter(
                isPresented: $showingMIDIImporter,
                allowedContentTypes: [.midi],
                allowsMultipleSelection: false
            ) { result in
                handleMIDISelection(result)
            }
            .confirmationDialog(
                "Import MIDI",
                isPresented: $showingMIDIImportChoice,
                titleVisibility: .visible
            ) {
                Button("New Instrument Track") { importMIDIAsNewTrack() }
                Button("Replace These Notes", role: .destructive) { importMIDIReplacingNotes() }
                Button("Cancel", role: .cancel) { pendingMIDIImport = nil }
            } message: {
                Text(midiImportMessage)
            }
            .alert("MIDI", isPresented: midiAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.midiError ?? midiMessage ?? "")
            }
            .sheet(item: $midiShareItem) { item in
                ShareSheet(items: [item.url])
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: model.midiExportURL) { _, url in
                guard let url else { return }
                midiShareItem = ShareItem(url: url)
                model.clearMIDIExportURL()
            }
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
            .defaultScrollAnchor(.center)
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

            HStack(spacing: 10) {
                Text("SOUND")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                Button {
                    showingSounds = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: track.voice.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(track.soundPreset.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Color.studioAccent)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.studioAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sound: \(track.soundPreset.name)")

                if track.voice.isGuitar {
                    Button {
                        showingGuitarTone = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "guitars")
                                .font(.system(size: 11, weight: .semibold))
                            Text(track.guitarTone.matchedPreset?.name ?? "Custom")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.studioPanelHighlight, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Guitar tone")
                }

                Spacer(minLength: 4)

                Text(track.voice.title.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                Text("QUANTIZE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                Slider(value: $quantizeStrength, in: 0...1)
                    .frame(maxWidth: 120)
                    .tint(Color.studioAccent)
                    .accessibilityLabel("Quantize strength")

                Text("\(Int((quantizeStrength * 100).rounded()))%")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)

                Spacer(minLength: 4)

                Button {
                    model.quantizeSynthNotes(
                        trackID: trackID,
                        noteIDs: selectedNoteIDs,
                        grid: snapDuration,
                        strength: quantizeStrength
                    )
                } label: {
                    Text("Quantize")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selectedNoteIDs.isEmpty ? Color.white.opacity(0.4) : Color.black)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(
                            selectedNoteIDs.isEmpty ? Color.studioPanelHighlight.opacity(0.6) : Color.studioAccent,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
                .disabled(selectedNoteIDs.isEmpty)
                .accessibilityLabel("Quantize selected notes")
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
                        let ids = model.addSynthChord(
                            trackID: trackID,
                            pitch: pitch(atY: value.location.y),
                            startTime: snappedTime(atX: value.location.x),
                            duration: snapDuration,
                            chordType: chordType,
                            snapInterval: snapDuration
                        )
                        selectedNoteIDs = Set(ids)
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
        let isSelected = selectedNoteIDs.contains(note.id)
        let width = max(12, CGFloat(note.duration) * pixelsPerSecond)
        let y = CGFloat(SynthNote.highestPitch - note.pitch) * rowHeight

        return RoundedRectangle(cornerRadius: 4)
            .fill(Color.studioAccent.opacity(isSelected ? 0.95 : 0.72))
            .overlay(alignment: .topLeading) {
                Text(SynthNote.name(for: note.pitch))
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .padding(.leading, 3)
                    .padding(.top, 1)
            }
            .overlay(alignment: .bottom) {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: max(1, geometry.size.width * CGFloat(note.velocity)))
                        Spacer(minLength: 0)
                    }
                    .frame(height: 2.5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.white.opacity(0.85) : Color.clear, lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    resizeHandle(note)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                velocityHandle(note)
            }
            .frame(width: width, height: rowHeight - 3)
            .offset(x: CGFloat(note.startTime) * pixelsPerSecond, y: y + 1.5)
            .contentShape(Rectangle())
            .onTapGesture { toggleSelection(note.id) }
            .highPriorityGesture(moveGesture(note))
            .accessibilityLabel("Note \(SynthNote.name(for: note.pitch))")
            .accessibilityValue("Velocity \(Int(note.velocity * 100)) percent")
    }

    private func resizeHandle(_ note: SynthNote) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.45))
            .frame(width: 12, height: 8)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        selectedNoteIDs = [note.id]
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

    private func velocityHandle(_ note: SynthNote) -> some View {
        Image(systemName: "arrow.up.and.down")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.55))
            .frame(width: 14, height: 10)
            .contentShape(Rectangle())
            .highPriorityGesture(velocityGesture(note))
            .accessibilityLabel("Velocity of \(SynthNote.name(for: note.pitch))")
    }

    private func velocityGesture(_ note: SynthNote) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                selectedNoteIDs.insert(note.id)
                if velocityOrigin == nil { velocityOrigin = note.velocity }
                guard let origin = velocityOrigin else { return }
                let next = min(1, max(0.05, origin - Float(value.translation.height / 70)))
                model.setSynthNoteVelocity(trackID: trackID, noteID: note.id, velocity: next)
            }
            .onEnded { _ in
                velocityOrigin = nil
                model.commitSession()
            }
    }

    private func moveGesture(_ note: SynthNote) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                selectedNoteIDs = [note.id]
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

    private func toggleSelection(_ noteID: UUID) {
        if selectedNoteIDs.contains(noteID) {
            selectedNoteIDs.remove(noteID)
        } else {
            selectedNoteIDs.insert(noteID)
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
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
        }
    }

    // MARK: - MIDI

    private var midiImportMessage: String {
        guard let imported = pendingMIDIImport else { return "" }
        let count = imported.notes.count
        let notesText = count == 1 ? "1 note" : "\(count) notes"
        let name = imported.name ?? "This file"
        return "“\(name)” has \(notesText). Add it as a new instrument track, or replace the notes on this track?"
    }

    private var midiAlert: Binding<Bool> {
        Binding(
            get: { midiMessage != nil || model.midiError != nil },
            set: { presenting in
                if !presenting {
                    midiMessage = nil
                    model.midiError = nil
                }
            }
        )
    }

    private func handleMIDISelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let imported = try MIDIFile.importFile(at: url)
                pendingMIDIImport = imported
                showingMIDIImportChoice = true
            } catch {
                midiMessage = (error as? LocalizedError)?.errorDescription
                    ?? "That MIDI file could not be read."
            }
        case .failure:
            midiMessage = "That file could not be opened."
        }
    }

    private func importMIDIAsNewTrack() {
        guard let imported = pendingMIDIImport else { return }
        pendingMIDIImport = nil
        model.addMIDITrack(imported)
        midiMessage = "Imported \(midiNoteCount(imported.notes.count)) as a new track."
    }

    private func importMIDIReplacingNotes() {
        guard let imported = pendingMIDIImport else { return }
        pendingMIDIImport = nil
        model.replaceSynthNotes(trackID: trackID, with: imported.notes, tempoBPM: imported.tempoBPM)
        midiMessage = "Replaced this track's notes with \(midiNoteCount(imported.notes.count))."
    }

    private func midiNoteCount(_ count: Int) -> String {
        count == 1 ? "1 note" : "\(count) notes"
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
