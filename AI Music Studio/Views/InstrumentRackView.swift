//
//  InstrumentRackView.swift
//  AI Music Studio
//

import SwiftUI
import UniformTypeIdentifiers

struct InstrumentRackView: View {
    @ObservedObject var model: MixerViewModel
    var initialTrackID: UUID? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var selectedInstrument = InstrumentSelection.synth
    @State private var drumDisplayMode = DrumDisplayMode.pads
    @State private var selectedTrackID: UUID?
    @State private var drumVolume = 0.8
    @State private var drumTuning = 1.0
    @State private var drumDecay = 1.0
    @State private var drumTone = 0.65
    @State private var waveform = SynthWaveform.saw
    @State private var cutoff = 6_500.0
    @State private var attack = 0.02
    @State private var release = 0.28
    @State private var tb303Waveform = TB303Waveform.saw
    @State private var tb303Cutoff = 1_250.0
    @State private var tb303Resonance = 0.68
    @State private var tb303Envelope = 0.58
    @State private var tb303Decay = 0.42
    @State private var tb303Tuning = 1.0
    @State private var tb303Level = 0.8
    @State private var tb303Accent = false
    @State private var showSamplerImporter = false
    @State private var showSampleLibrary = false
    @State private var countInValue: Int?
    @State private var countInTask: Task<Void, Never>?

    private let pianoNotes: [PianoNote] = [
        PianoNote(title: "C4", frequency: 261.63),
        PianoNote(title: "D4", frequency: 293.66),
        PianoNote(title: "E4", frequency: 329.63),
        PianoNote(title: "F4", frequency: 349.23),
        PianoNote(title: "G4", frequency: 392.00),
        PianoNote(title: "A4", frequency: 440.00),
        PianoNote(title: "B4", frequency: 493.88),
        PianoNote(title: "C5", frequency: 523.25),
    ]
    private let bassNotes: [PianoNote] = [
        PianoNote(title: "C2", frequency: 65.41),
        PianoNote(title: "D2", frequency: 73.42),
        PianoNote(title: "E2", frequency: 82.41),
        PianoNote(title: "F2", frequency: 87.31),
        PianoNote(title: "G2", frequency: 98.00),
        PianoNote(title: "A2", frequency: 110.00),
        PianoNote(title: "B2", frequency: 123.47),
        PianoNote(title: "C3", frequency: 130.81),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    destinationPicker
                    recordingControls

                    Picker("Instrument", selection: $selectedInstrument) {
                        ForEach(InstrumentSelection.allCases) { instrument in
                            Text(instrument.title).tag(instrument)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch selectedInstrument {
                    case .synth:
                        synthPanel
                    case .drums:
                        drumPanel
                    case .tb303:
                        tb303Panel
                    case .sampler:
                        samplerPanel
                    case .microphone:
                        microphonePanel
                    }
                }
                .padding(16)
            }
            .background(Color.studioBackground)
            .navigationTitle("Instruments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            selectedTrackID = initialTrackID.flatMap { id in
                model.tracks.contains(where: { $0.id == id }) ? id : nil
            } ?? model.tracks.first?.id
        }
        .onChange(of: model.tracks.map(\.id)) { _, trackIDs in
            if let selectedTrackID, trackIDs.contains(selectedTrackID) { return }
            selectedTrackID = trackIDs.first
        }
        .fileImporter(
            isPresented: $showSamplerImporter,
            allowedContentTypes: [.audio, .mp3],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.loadSampler(from: url)
            }
        }
        .sheet(isPresented: $showSampleLibrary) {
            SampleLibraryView(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onDisappear {
            cancelCountIn()
            if model.isRecordingInstrument {
                model.stopInstrumentRecording()
            }
        }
        .alert("Instrument Recording", isPresented: instrumentErrorBinding) {
            Button("OK", role: .cancel) {
                model.clearSamplerError()
                model.clearRecordingError()
                model.clearMicrophoneError()
            }
        } message: {
            Text(model.recordingError ?? model.microphoneError ?? model.samplerError ?? "")
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    private var destinationPicker: some View {
        HStack(spacing: 10) {
            Label("Destination", systemImage: "arrow.turn.down.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 5)

            Picker("Destination", selection: $selectedTrackID) {
                Text("Master Output").tag(Optional<UUID>.none)
                ForEach(model.tracks) { track in
                    Text(track.name).tag(Optional(track.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background {
            WoodGrainSurface()
                .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color(red: 0.62, green: 0.42, blue: 0.25).opacity(0.55), lineWidth: 1)
        }
    }

    private var synthPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("POLYPHONIC SYNTH", systemImage: "waveform")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(Color.studioAccent)
                Spacer()
                Text("8 voices")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(SynthWaveform.allCases) { option in
                    Button {
                        waveform = option
                    } label: {
                        Text(option.title)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(waveform == option ? Color.black : Color.primary)
                            .background(
                                waveform == option ? Color.studioAccent : Color.studioPanelHighlight,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            sliderControl(title: "Cutoff", valueText: "\(Int(cutoff)) Hz", value: $cutoff, range: 180...9_000)
            sliderControl(title: "Attack", valueText: String(format: "%.2f s", attack), value: $attack, range: 0.005...0.45)
            sliderControl(title: "Release", valueText: String(format: "%.2f s", release), value: $release, range: 0.04...0.75)

            VStack(alignment: .leading, spacing: 7) {
                Text("PLAY NOTES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                HStack(spacing: 2) {
                    ForEach(pianoNotes) { note in
                        Button {
                            model.playSynthNote(
                                frequency: note.frequency,
                                waveform: waveform,
                                cutoff: cutoff,
                                attack: attack,
                                release: release,
                                destinationTrackID: selectedTrackID
                            )
                        } label: {
                            VStack {
                                Spacer()
                                Text(note.title)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color.black.opacity(0.72))
                                    .padding(.bottom, 8)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 116)
                            .background(Color(white: 0.9), in: RoundedRectangle(cornerRadius: 5))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.black.opacity(0.28), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play note \(note.title)")
                    }
                }
            }
        }
        .padding(14)
        .background {
            WoodGrainSurface()
                .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color(red: 0.62, green: 0.42, blue: 0.25).opacity(0.55), lineWidth: 1)
        }
    }

    private var tb303Panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TB-303")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .tracking(0.8)
                    Text("MONOPHONIC ACID BASS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "waveform.path")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.studioAccent)
            }

            HStack(spacing: 7) {
                ForEach(TB303Waveform.allCases) { option in
                    Button {
                        tb303Waveform = option
                    } label: {
                        Text(option.title)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(tb303Waveform == option ? Color.black : Color.primary)
                            .background(
                                tb303Waveform == option ? Color.studioAccent : Color.studioPanelHighlight,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 12) {
                InstrumentKnob(title: "TUNE", valueText: String(format: "%.2f×", tb303Tuning), value: $tb303Tuning, range: 0.5...1.5)
                InstrumentKnob(title: "CUTOFF", valueText: "\(Int(tb303Cutoff)) Hz", value: $tb303Cutoff, range: 100...5_000)
                InstrumentKnob(title: "RESONANCE", valueText: "\(Int(tb303Resonance * 100))%", value: $tb303Resonance, range: 0...0.96)
                InstrumentKnob(title: "ENV MOD", valueText: "\(Int(tb303Envelope * 100))%", value: $tb303Envelope, range: 0...1)
                InstrumentKnob(title: "DECAY", valueText: String(format: "%.2f s", tb303Decay), value: $tb303Decay, range: 0.16...1.2)
                InstrumentKnob(title: "LEVEL", valueText: "\(Int(tb303Level * 100))%", value: $tb303Level, range: 0...1)
            }

            Toggle(isOn: $tb303Accent) {
                HStack {
                    Text("Accent")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("ACCENT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.studioAccent)

            VStack(alignment: .leading, spacing: 7) {
                Text("BASS KEYS · C2–C3")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)

                HStack(spacing: 2) {
                    ForEach(bassNotes) { note in
                        Button {
                            model.playTB303Note(
                                frequency: note.frequency,
                                waveform: tb303Waveform,
                                cutoff: tb303Cutoff,
                                resonance: tb303Resonance,
                                envelopeAmount: tb303Envelope,
                                decay: tb303Decay,
                                accent: tb303Accent,
                                tuning: tb303Tuning,
                                level: tb303Level,
                                destinationTrackID: selectedTrackID
                            )
                        } label: {
                            VStack {
                                Spacer()
                                Text(note.title)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color.black.opacity(0.72))
                                    .padding(.bottom, 8)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 106)
                            .background(Color(white: 0.9), in: RoundedRectangle(cornerRadius: 5))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.black.opacity(0.28), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play TB-303 note \(note.title)")
                    }
                }
            }
        }
        .padding(14)
        .background {
            WoodGrainSurface()
                .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color(red: 0.67, green: 0.47, blue: 0.28).opacity(0.75), lineWidth: 1)
        }
    }

    private var drumPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 11) {
                Text("808")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Color(red: 0.96, green: 0.86, blue: 0.69))
                Rectangle()
                    .fill(Color(red: 0.90, green: 0.70, blue: 0.42).opacity(0.45))
                    .frame(width: 1, height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("RHYTHM MACHINE")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Color(red: 0.96, green: 0.86, blue: 0.69))
                    Text("11 ANALOG-STYLE VOICES")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color(red: 0.88, green: 0.77, blue: 0.62).opacity(0.84))
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(Color(red: 0.82, green: 0.18, blue: 0.12))
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.red.opacity(0.5), radius: 4)
            }

            Rectangle()
                .fill(Color(red: 0.90, green: 0.70, blue: 0.42).opacity(0.35))
                .frame(height: 1)

            Picker("Drum Mode", selection: $drumDisplayMode) {
                Text("Pads").tag(DrumDisplayMode.pads)
                Text("16-Step Pattern").tag(DrumDisplayMode.pattern)
            }
            .pickerStyle(.segmented)
            .tint(Color(red: 0.82, green: 0.18, blue: 0.12))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 10) {
                InstrumentKnob(title: "LEVEL", valueText: "\(Int(drumVolume * 100))%", value: $drumVolume, range: 0...1)
                InstrumentKnob(title: "TUNE", valueText: String(format: "%.2f×", drumTuning), value: $drumTuning, range: 0.5...1.5)
                InstrumentKnob(title: "DECAY", valueText: "\(Int(drumDecay * 100))%", value: $drumDecay, range: 0.4...2)
                InstrumentKnob(title: "TONE", valueText: "\(Int(drumTone * 100))%", value: $drumTone, range: 0...1)
            }

            if drumDisplayMode == .pads {
                drumPadGrid
            } else {
                drumSequencer
            }
        }
        .padding(14)
        .background {
            WoodGrainSurface()
                .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color(red: 0.67, green: 0.47, blue: 0.28).opacity(0.75), lineWidth: 1)
        }
    }

    private var drumPadGrid: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("TAP A PAD TO AUDITION")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color(red: 0.88, green: 0.77, blue: 0.62).opacity(0.86))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
                ForEach(Array(DrumPad.allCases.enumerated()), id: \.element.id) { index, pad in
                    Button {
                        model.playDrumPad(
                            pad,
                            destinationTrackID: selectedTrackID,
                            volume: drumVolume,
                            tuning: drumTuning,
                            decay: drumDecay,
                            tone: drumTone
                        )
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: pad.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                            Text(pad.title.uppercased())
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(Color(red: 0.96, green: 0.86, blue: 0.69))
                        .frame(maxWidth: .infinity)
                        .frame(height: 65)
                        .background(Color(red: 0.24, green: 0.14, blue: 0.09), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .topTrailing) {
                            Circle()
                                .fill(Color(red: 0.82, green: 0.18, blue: 0.12))
                                .frame(width: 5, height: 5)
                                .padding(6)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.black.opacity(0.16), lineWidth: 1)
                        }
                        .shadow(color: Color.black.opacity(0.18), radius: 2, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play \(pad.title) drum pad")
                }
            }
        }
    }

    private var drumSequencer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Button {
                    if model.isDrumSequencerPlaying {
                        model.stopDrumSequencer()
                    } else {
                        model.startDrumSequencer(
                            destinationTrackID: selectedTrackID,
                            volume: drumVolume,
                            tuning: drumTuning,
                            decay: drumDecay,
                            tone: drumTone
                        )
                    }
                } label: {
                    Label(
                        model.isDrumSequencerPlaying ? "Stop Pattern" : "Play Pattern",
                        systemImage: model.isDrumSequencerPlaying ? "stop.fill" : "play.fill"
                    )
                    .font(.system(size: 10, weight: .bold))
                    .frame(height: 34)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.82, green: 0.18, blue: 0.12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("PATTERN 1")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                    Text("\(model.tempoBPM) BPM · 4/4")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.88, green: 0.77, blue: 0.62).opacity(0.86))
                }

                Spacer(minLength: 0)

                if let step = model.currentDrumStep {
                    Text(String(format: "%02d", step + 1))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.82, green: 0.18, blue: 0.12))
                }
            }

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Text("VOICE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .frame(width: 72, alignment: .leading)
                        ForEach(0..<DrumPattern.stepCount, id: \.self) { step in
                            Text(String(format: "%02d", step + 1))
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundStyle(step % 4 == 0 ? Color(red: 0.98, green: 0.87, blue: 0.67) : Color(red: 0.90, green: 0.78, blue: 0.62).opacity(0.62))
                                .frame(width: 21)
                        }
                    }

                    ForEach(DrumPad.allCases) { pad in
                        HStack(spacing: 4) {
                            Text(pad.title.uppercased())
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .foregroundStyle(Color(red: 0.96, green: 0.86, blue: 0.69))
                                .frame(width: 72, alignment: .leading)

                            ForEach(0..<DrumPattern.stepCount, id: \.self) { step in
                                let isActive = model.drumPattern.contains(pad, step: step)
                                let isPlayhead = model.currentDrumStep == step
                                Button {
                                    model.toggleDrumStep(pad, step: step)
                                } label: {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(isActive ? Color.studioAccent : Color.white.opacity(step % 4 == 0 ? 0.22 : 0.11))
                                        .frame(width: 21, height: 24)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(isPlayhead ? Color.studioAccent : Color.white.opacity(0.16), lineWidth: isPlayhead ? 1.5 : 0.6)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(pad.title), step \(step + 1), \(isActive ? "on" : "off")")
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Text("Tap steps to toggle hits · 16 steps per bar")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(red: 0.88, green: 0.77, blue: 0.62).opacity(0.86))
        }
    }

    private var microphonePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("MICROPHONE INPUT", systemImage: "mic.fill")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(Color.studioAccent)

            HStack(spacing: 12) {
                Image(systemName: model.microphonePermissionGranted ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(model.microphonePermissionGranted ? Color.green : Color.studioAccent)
                    .frame(width: 48, height: 48)
                    .background(Color.studioBackground, in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.microphonePermissionGranted ? "Microphone ready" : "Allow microphone access")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Record live audio into the selected session track.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.studioBackground, in: RoundedRectangle(cornerRadius: 10))

            if !model.microphonePermissionGranted {
                Button {
                    model.requestMicrophonePermission()
                } label: {
                    Label("Enable Microphone", systemImage: "mic")
                        .font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(Color.black)
                        .background(Color.studioAccent, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)

                Text("Microphone access is only used when you record a take.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Label("Ready for the count-in and record button above.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let microphoneError = model.microphoneError {
                Text(microphoneError)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.red)
            }
        }
        .padding(14)
        .background {
            WoodGrainSurface()
                .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color(red: 0.62, green: 0.42, blue: 0.25).opacity(0.55), lineWidth: 1)
        }
    }

    private var samplerPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("SAMPLER", systemImage: "waveform.badge.mic")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(Color.studioAccent)

            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.studioAccent)
                    .frame(width: 48, height: 48)
                    .background(Color.studioAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.samplerDisplayName ?? "No sample loaded")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(model.samplerDisplayName == nil ? "Load an audio file to play it from the sampler." : "Sample ready to trigger")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.studioBackground, in: RoundedRectangle(cornerRadius: 10))

            Button {
                showSampleLibrary = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Browse Sample Library")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(Color.studioAccent)
                .padding(.horizontal, 11)
                .frame(height: 40)
                .background(Color.studioBackground, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Browse sample library")

            HStack(spacing: 9) {
                Button {
                    showSamplerImporter = true
                } label: {
                    Label("Load Sample", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.studioPanelHighlight, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)

                Button {
                    model.playSampler(destinationTrackID: selectedTrackID)
                } label: {
                    Label("Trigger", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(Color.black)
                        .background(Color.studioAccent, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(model.samplerDisplayName == nil)
                .opacity(model.samplerDisplayName == nil ? 0.45 : 1)
            }
        }
        .padding(14)
        .background {
            WoodGrainSurface()
                .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color(red: 0.62, green: 0.42, blue: 0.25).opacity(0.55), lineWidth: 1)
        }
    }

    private var recordingControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(model.isRecordingInstrument ? Color.red : Color.studioAccent)
                    .frame(width: 8, height: 8)
                    .shadow(color: model.isRecordingInstrument ? Color.red.opacity(0.6) : .clear, radius: 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isRecordingInstrument ? "RECORDING TAKE" : countInValue == nil ? "TAKE RECORD" : "COUNT-IN")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                    Text(recordingStatusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if let countInValue {
                    Text("\(countInValue)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.studioAccent)
                        .frame(width: 42)
                } else if model.isRecordingInstrument {
                    Text(studioTimeString(model.recordingElapsed))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.red)
                }
            }

            Button(action: performRecordAction) {
                Label(recordButtonTitle, systemImage: recordButtonSymbol)
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .foregroundStyle(model.isRecordingInstrument ? Color.white : Color.black)
                    .background(recordButtonColor, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(!model.isRecordingInstrument && countInValue == nil && !canStartRecording)
            .opacity(!model.isRecordingInstrument && countInValue == nil && !canStartRecording ? 0.45 : 1)
        }
        .padding(12)
        .background {
            WoodGrainSurface()
                .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(model.isRecordingInstrument ? Color.red.opacity(0.55) : Color(red: 0.62, green: 0.42, blue: 0.25).opacity(0.55), lineWidth: 1)
        }
    }

    private var canStartRecording: Bool {
        selectedTrackID != nil
            && (selectedInstrument != .sampler || model.samplerDisplayName != nil)
            && (selectedInstrument != .microphone || model.microphonePermissionGranted)
    }

    private var recordingStatusText: String {
        if model.isRecordingInstrument {
            return "Capturing to \(selectedTrackName ?? "session track")"
        }
        if let countInValue {
            return "Starting in \(countInValue)"
        }
        return selectedTrackName.map { "Armed for \($0)" } ?? "Choose a session track to arm a take"
    }

    private var selectedTrackName: String? {
        model.tracks.first(where: { $0.id == selectedTrackID })?.name
    }

    private var recordButtonTitle: String {
        if model.isRecordingInstrument { return "Stop Recording" }
        if countInValue != nil { return "Cancel Count-In" }
        return selectedInstrument == .microphone ? "Record Mic Take" : "Record Performance"
    }

    private var recordButtonSymbol: String {
        if model.isRecordingInstrument { return "stop.fill" }
        if countInValue != nil { return "xmark" }
        return "record.circle.fill"
    }

    private var recordButtonColor: Color {
        if model.isRecordingInstrument { return .red }
        if countInValue != nil { return Color.studioPanelHighlight }
        return Color.studioAccent
    }

    private func performRecordAction() {
        if model.isRecordingInstrument {
            model.stopInstrumentRecording()
        } else if countInValue != nil {
            cancelCountIn()
        } else {
            startCountIn()
        }
    }

    private func startCountIn() {
        guard canStartRecording else { return }
        let usesClick = model.isCountInEnabled
        let beats = 4
        if usesClick {
            model.playMetronomeCountIn(beats: beats)
        }

        countInTask = Task { @MainActor in
            if usesClick {
                let beatLength = model.beatDuration
                for beat in stride(from: beats, through: 1, by: -1) {
                    guard !Task.isCancelled else {
                        countInValue = nil
                        countInTask = nil
                        model.stopMetronomeCountIn()
                        return
                    }
                    countInValue = beat
                    try? await Task.sleep(for: .seconds(beatLength))
                }
            } else {
                for count in [3, 2, 1] {
                    guard !Task.isCancelled else {
                        countInValue = nil
                        countInTask = nil
                        return
                    }
                    countInValue = count
                    try? await Task.sleep(for: .seconds(1))
                }
            }

            guard !Task.isCancelled else {
                countInValue = nil
                countInTask = nil
                return
            }
            countInValue = nil
            if selectedInstrument == .microphone {
                model.startMicrophoneRecording(destinationTrackID: selectedTrackID)
            } else {
                model.startInstrumentRecording(destinationTrackID: selectedTrackID)
            }
            countInTask = nil
        }
    }

    private func cancelCountIn() {
        countInTask?.cancel()
        countInTask = nil
        countInValue = nil
        model.stopMetronomeCountIn()
    }

    private func sliderControl(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(valueText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private var instrumentErrorBinding: Binding<Bool> {
        Binding(
            get: { model.samplerError != nil || model.recordingError != nil || model.microphoneError != nil },
            set: { newValue in
                if !newValue {
                    model.clearSamplerError()
                    model.clearRecordingError()
                    model.clearMicrophoneError()
                }
            }
        )
    }
}

private enum DrumDisplayMode: String, Identifiable {
    case pads
    case pattern

    var id: String { rawValue }
}

private enum InstrumentSelection: String, CaseIterable, Identifiable {
    case synth
    case drums
    case tb303
    case sampler
    case microphone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .synth: return "Synth"
        case .drums: return "808 Drums"
        case .tb303: return "TB-303"
        case .sampler: return "Sampler"
        case .microphone: return "Mic"
        }
    }
}

private struct PianoNote: Identifiable {
    let title: String
    let frequency: Double

    var id: String { title }
}



private struct WoodGrainSurface: View {
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(
                Path(bounds),
                with: .color(Color(red: 0.22, green: 0.13, blue: 0.09))
            )

            guard size.width > 0, size.height > 0 else { return }

            let rowCount = Int(size.height / 6) + 2
            for row in 0..<rowCount {
                let baseline = CGFloat(row) * 6
                var grain = Path()
                grain.move(to: CGPoint(x: 0, y: baseline))
                let wave = CGFloat(sin(Double(row) * 0.63)) * 1.4
                grain.addCurve(
                    to: CGPoint(x: size.width, y: baseline + wave),
                    control1: CGPoint(x: size.width * 0.28, y: baseline - wave * 0.7),
                    control2: CGPoint(x: size.width * 0.72, y: baseline + wave * 0.8)
                )
                let warmth = 0.34 + Double((row * 7) % 11) / 45
                context.stroke(
                    grain,
                    with: .color(Color(red: 0.72, green: 0.45, blue: 0.25).opacity(warmth)),
                    lineWidth: row % 5 == 0 ? 1.2 : 0.45
                )
            }

            for knot in 0..<2 {
                let center = CGPoint(
                    x: size.width * (knot == 0 ? 0.31 : 0.78),
                    y: size.height * (knot == 0 ? 0.38 : 0.72)
                )
                for ring in 0..<4 {
                    let width = CGFloat(13 + ring * 7)
                    let height = CGFloat(4 + ring * 2)
                    let oval = CGRect(
                        x: center.x - width / 2,
                        y: center.y - height / 2,
                        width: width,
                        height: height
                    )
                    var path = Path()
                    path.addEllipse(in: oval)
                    context.stroke(
                        path,
                        with: .color(Color(red: 0.78, green: 0.51, blue: 0.30).opacity(0.18)),
                        lineWidth: 0.55
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}



private struct InstrumentKnob: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    @State private var dragStartValue: Double?

    private var angle: Double {
        let span = range.upperBound - range.lowerBound
        let progress = span > 0 ? (value - range.lowerBound) / span : 0.5
        return -135 + min(1, max(0, progress)) * 270
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.47, green: 0.42, blue: 0.35), Color(red: 0.13, green: 0.13, blue: 0.13)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .stroke(Color(red: 0.74, green: 0.56, blue: 0.33).opacity(0.75), lineWidth: 1)
                Capsule()
                    .fill(Color(red: 0.98, green: 0.76, blue: 0.43))
                    .frame(width: 2, height: 12)
                    .offset(y: -10)
                    .rotationEffect(.degrees(angle))
                Circle()
                    .fill(Color(red: 0.22, green: 0.20, blue: 0.17))
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
            }
            .frame(width: 46, height: 46)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if dragStartValue == nil { dragStartValue = value }
                        let span = range.upperBound - range.lowerBound
                        let delta = -Double(gesture.translation.height) / 120 * span
                        value = min(range.upperBound, max(range.lowerBound, (dragStartValue ?? value) + delta))
                    }
                    .onEnded { _ in dragStartValue = nil }
            )
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityValue(valueText)
            .accessibilityAdjustableAction { direction in
                let step = (range.upperBound - range.lowerBound) / 100
                switch direction {
                case .increment: value = min(range.upperBound, value + step)
                case .decrement: value = max(range.lowerBound, value - step)
                @unknown default: break
                }
            }

            Text(title)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.25)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color(red: 0.92, green: 0.82, blue: 0.66))
            Text(valueText)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color(red: 0.75, green: 0.64, blue: 0.49))
        }
        .frame(maxWidth: .infinity)
    }
}
