//
//  MixerView.swift
//  AI Music Studio
//

import SwiftUI
import UniformTypeIdentifiers

extension Color {
    static let studioBackground = Color(red: 0.075, green: 0.075, blue: 0.085)
    static let studioPanel = Color(white: 0.115)
    static let studioPanelHighlight = Color(white: 0.22)
    static let studioAccent = Color(red: 0.96, green: 0.62, blue: 0.16)
    static let studioPanAutomation = Color(red: 0.36, green: 0.56, blue: 0.93)

    /// One restrained color per track, cycling for larger sessions.
    static func studioTrackColor(for index: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.98, green: 0.64, blue: 0.18),
            Color(red: 0.16, green: 0.66, blue: 0.60),
            Color(red: 0.36, green: 0.56, blue: 0.93),
            Color(red: 0.80, green: 0.42, blue: 0.78),
        ]
        return palette[index % palette.count]
    }
}

struct MixerView: View {
    @State private var model = MixerViewModel()
    @State private var showImporter = false
    @State private var showSplitPicker = false
    @State private var showChat = false
    @State private var chat = AgentChatViewModel()
    @State private var activeSheet: StudioSheet?
    @State private var selectedEQTrackID: UUID?
    @State private var selectedPianoRollTrackID: UUID?
    @State private var instrumentDestinationTrackID: UUID?
    @State private var bounceMode: BounceSettingsView.Mode = .mix

    var body: some View {
        ZStack {
            Color.studioBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if model.tracks.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    WaveformTimeline(
                        model: model,
                        onOpenTrackEQ: { trackID in
                            selectedEQTrackID = trackID
                            activeSheet = .trackEQ
                        },
                        onOpenPianoRoll: { trackID in
                            selectedPianoRollTrackID = trackID
                            activeSheet = .pianoRoll
                        },
                        onOpenInstrumentsForTrack: { trackID in
                            instrumentDestinationTrackID = trackID
                            activeSheet = .instruments
                        },
                        onAddInstrumentTrack: createInstrumentLayerAndOpen
                    )
                }

                TransportBarView(model: model)
            }
        }
        .overlay {
            if model.isSeparating {
                separationProgressCard
            }
        }
        .overlay {
            if model.isBouncing {
                bounceProgressCard
            }
        }
        .overlay {
            if model.isFreezingTrack {
                freezeProgressCard
            }
        }
        .overlay {
            if showChat {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.42)
                        .ignoresSafeArea()
                        .onTapGesture { showChat = false }

                    AgentChatDrawer(chat: chat, onClose: { showChat = false })
                        .frame(maxHeight: 460)
                        .transition(.move(edge: .bottom))
                }
            }
        }
        .animation(.spring(duration: 0.35), value: showChat)
        .onAppear {
            chat.mixer = model
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio, .mp3],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.importTracks(from: urls)
            }
        }
        .fileImporter(
            isPresented: $showSplitPicker,
            allowedContentTypes: [.audio, .mp3],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let songURL = urls.first {
                model.separateStems(from: songURL)
            }
        }
        .sheet(item: $activeSheet) { destination in
            switch destination {
            case .settings:
                SettingsView()
            case .instruments:
                InstrumentRackView(model: model, initialTrackID: instrumentDestinationTrackID)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .exports:
                ExportLibraryView(model: model)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .trackEQ:
                if let selectedEQTrackID {
                    TrackEQView(model: model, trackID: selectedEQTrackID)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                } else {
                    Color.clear
                }
            case .sessions:
                SessionLibraryView(model: model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .templates:
                TemplatesView(model: model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .mixer:
                ChannelMixerView(model: model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .masterEffects:
                MasterEffectsView(model: model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .channelPresets:
                ChannelPresetsView(model: model, initialTrackID: nil)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .bounce:
                BounceSettingsView(
                    mode: bounceMode,
                    sessionName: model.sessionName,
                    duration: model.duration,
                    trackCount: model.tracks.count,
                    settings: model.bounceSettings
                ) { settings in
                    switch bounceMode {
                    case .mix:
                        model.bounceMix(settings: settings)
                    case .stems:
                        model.bounceStems(settings: settings)
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .pianoRoll:
                if let selectedPianoRollTrackID {
                    PianoRollView(model: model, trackID: selectedPianoRollTrackID)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                } else {
                    Color.clear
                }
            }
        }
        .onChange(of: model.lastExportURL) { _, exportURL in
            if exportURL != nil {
                activeSheet = .exports
            }
        }
        .alert(Text(alertTitle), isPresented: studioErrorBinding) {
            Button("OK", role: .cancel) {
                model.separationError = nil
                model.clearBounceError()
                model.clearFreezeError()
                model.audioError = nil
            }
        } message: {
            Text(model.audioError ?? model.freezeError ?? model.bounceError ?? model.separationError ?? "")
        }
    }

    private func createInstrumentLayerAndOpen() {
        instrumentDestinationTrackID = model.addInstrumentTrack()
        activeSheet = .instruments
    }

    // MARK: - Session header

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.studioAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.studioAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.sessionName)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Text(sessionSubtitle.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    model.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canUndo)
                .opacity(model.canUndo ? 1 : 0.35)
                .accessibilityLabel("Undo")

                Button {
                    model.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canRedo)
                .opacity(model.canRedo ? 1 : 0.35)
                .accessibilityLabel("Redo")

                Button {
                    activeSheet = .mixer
                } label: {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 38, height: 38)
                        .background(Color.studioPanelHighlight.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Channel mixer")

                Button {
                    activeSheet = .masterEffects
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 38, height: 38)
                        .background(Color.studioPanelHighlight.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topTrailing) {
                            if !model.masterEffects.isBypassed {
                                Circle()
                                    .fill(Color.studioAccent)
                                    .frame(width: 6, height: 6)
                                    .padding(6)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Master effects")

                Menu {
                    Button {
                        activeSheet = .templates
                    } label: {
                        Label("New from Template", systemImage: "square.grid.2x2")
                    }
                    Button {
                        activeSheet = .sessions
                    } label: {
                        Label("Sessions", systemImage: "folder")
                    }
                    Button {
                        model.refreshExports()
                        activeSheet = .exports
                    } label: {
                        Label("Mix Exports", systemImage: "square.stack")
                    }
                    Button {
                        activeSheet = .channelPresets
                    } label: {
                        Label("Channel Presets", systemImage: "bookmark")
                    }
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 38, height: 38)
                        .background(Color.studioPanelHighlight.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Session and export library")

                Button {
                    activeSheet = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 38, height: 38)
                        .background(Color.studioPanelHighlight.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Studio settings")
            }

            HStack(spacing: 8) {
                Menu {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import Audio Tracks", systemImage: "waveform")
                    }

                    Button {
                        showSplitPicker = true
                    } label: {
                        Label("Split Song Into Stems", systemImage: "waveform.path.ecg")
                    }

                    Button(action: createInstrumentLayerAndOpen) {
                        Label("New Instrument Layer", systemImage: "pianokeys")
                    }
                } label: {
                    StudioToolbarButton(title: "Add Track", systemImage: "plus", isProminent: true)
                }

                Button {
                    instrumentDestinationTrackID = nil
                    activeSheet = .instruments
                } label: {
                    StudioToolbarButton(title: "Instruments", systemImage: "pianokeys")
                }
                .buttonStyle(.plain)

                Button {
                    chat.mixer = model
                    showChat = true
                } label: {
                    StudioToolbarButton(title: "Agent", systemImage: "text.bubble")
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        bounceMode = .mix
                        activeSheet = .bounce
                    } label: {
                        Label("Bounce Mix", systemImage: "arrow.down.to.line")
                    }
                    Button {
                        bounceMode = .stems
                        activeSheet = .bounce
                    } label: {
                        Label("Bounce Stems", systemImage: "square.stack.3d.up")
                    }
                } label: {
                    StudioToolbarButton(title: "Bounce", systemImage: "arrow.down.to.line")
                }
                .disabled(model.isBouncing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 12)
        .background(Color.studioPanel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
    }

    private var sessionSubtitle: String {
        let count = model.tracks.count
        let tracksText = count == 1 ? "1 track" : "\(count) tracks"
        return "\(tracksText)  ·  \(studioTimeString(model.duration))"
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.studioAccent)

            Text("Start a session")
                .font(.system(size: 20, weight: .semibold))

            Text("Import audio tracks or split a song into stems to build your arrangement.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)

            Menu {
                Button {
                    showImporter = true
                } label: {
                    Label("Import Audio Tracks", systemImage: "waveform")
                }

                Button {
                    showSplitPicker = true
                } label: {
                    Label("Split Song Into Stems", systemImage: "waveform.path.ecg")
                }

                Button(action: createInstrumentLayerAndOpen) {
                    Label("New Instrument Layer", systemImage: "pianokeys")
                }
            } label: {
                StudioToolbarButton(title: "Add Track", systemImage: "plus", isProminent: true)
            }
            .padding(.top, 3)

            Button {
                activeSheet = .templates
            } label: {
                Label("Start from a Template", systemImage: "square.grid.2x2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.studioAccent)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Separation progress

    private var separationProgressCard: some View {
        VStack(spacing: 14) {
            ProgressView(value: model.separationProgress)
                .progressViewStyle(.linear)
            Text(model.separationStatus)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var bounceProgressCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .foregroundStyle(Color.studioAccent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isStemBounce ? "Bouncing Stems" : "Bouncing Mix")
                        .font(.system(size: 14, weight: .semibold))
                    Text(model.bounceStatus)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(model.bounceProgress * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.studioAccent)
            }
            ProgressView(value: model.bounceProgress)
                .progressViewStyle(.linear)
                .tint(Color.studioAccent)
        }
        .padding(20)
        .frame(maxWidth: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var alertTitle: String {
        if model.audioError != nil { return "Audio Unavailable" }
        if model.freezeError != nil { return "Freeze Failed" }
        if model.bounceError != nil { return "Bounce Failed" }
        return "Separation Failed"
    }

    private var freezeProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "snowflake")
                    .foregroundStyle(Color.studioAccent)
                Text(model.freezeStatus)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                ProgressView()
                    .tint(Color.studioAccent)
            }
            Text("Rendering the track through its mixer settings.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var studioErrorBinding: Binding<Bool> {
        Binding(
            get: { model.separationError != nil || model.bounceError != nil || model.freezeError != nil || model.audioError != nil },
            set: { shouldShow in
                if !shouldShow {
                    model.separationError = nil
                    model.clearBounceError()
                    model.clearFreezeError()
                    model.audioError = nil
                }
            }
        )
    }
}

private struct StudioToolbarButton: View {
    let title: String
    let systemImage: String
    var isProminent = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 38)
            .foregroundStyle(isProminent ? Color.black : Color.primary)
            .padding(.horizontal, 8)
            .background(
                isProminent ? Color.studioAccent : Color.studioPanelHighlight.opacity(0.65),
                in: RoundedRectangle(cornerRadius: 9)
            )
    }
}

private enum StudioSheet: String, Identifiable {
    case settings
    case instruments
    case exports
    case trackEQ
    case sessions
    case templates
    case mixer
    case masterEffects
    case channelPresets
    case pianoRoll
    case bounce

    var id: String { rawValue }
}
