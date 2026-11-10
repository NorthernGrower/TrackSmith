//
//  MixerView.swift
//  AI Music Studio
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension Color {
    static let studioBackground = Color(red: 0.075, green: 0.075, blue: 0.085)
    static let studioPanel = Color(white: 0.115)
    static let studioPanelHighlight = Color(white: 0.22)
    static let studioAccent = Color(red: 0.96, green: 0.62, blue: 0.16)
    static let studioPanAutomation = Color(red: 0.36, green: 0.56, blue: 0.93)

    /// The compact palette users pick track colors from.
    private static let studioPalette: [Color] = [
        Color(red: 0.98, green: 0.64, blue: 0.18),
        Color(red: 0.16, green: 0.66, blue: 0.60),
        Color(red: 0.36, green: 0.56, blue: 0.93),
        Color(red: 0.80, green: 0.42, blue: 0.78),
    ]

    static var studioTrackPalette: [Color] { studioPalette }

    /// One restrained color per track, cycling for larger sessions.
    static func studioTrackColor(for index: Int) -> Color {
        let slots = studioPalette.count
        return studioPalette[((index % slots) + slots) % slots]
    }

    /// The color shown for a track: its chosen palette slot, else the default cycling color.
    static func studioTrackColor(for track: Track, index: Int) -> Color {
        if track.colorIndex >= 0, track.colorIndex < studioPalette.count {
            return studioPalette[track.colorIndex]
        }
        return studioTrackColor(for: index)
    }
}

struct MixerView: View {
    @StateObject private var model = MixerViewModel()
    @State private var showImporter = false
    @State private var showSplitPicker = false
    @State private var showStemArchiveImporter = false
    @State private var selectedSongURL: URL?
    @StateObject private var chat = AgentChatViewModel()
    @State private var activeSheet: StudioSheet?
    @State private var selectedEQTrackID: UUID?
    @State private var selectedEffectsTrackID: UUID?
    @State private var selectedPianoRollTrackID: UUID?
    @State private var instrumentDestinationTrackID: UUID?
    @State private var bounceMode: BounceSettingsView.Mode = .mix
    @State private var crashReportText: String?

    var body: some View {
        let core = studioScroll
            .overlay(alignment: .top) {
                if let crashReportText {
                    CrashReportBanner(text: crashReportText, onDismiss: clearCrashReport)
                }
            }
            .onAppear {
                chat.mixer = model
                CrashReporter.shared.mark("Studio timeline")
                crashReportText = CrashReporter.shared.takePendingReport()
            }
            .studioAgentAccess(context: "Studio Mixer")
            .environmentObject(chat)
            .preferredColorScheme(.dark)
            .tint(Color.studioAccent)
        return core
            .sheet(item: $activeSheet) { destination in
                sheetContent(for: destination)
            }
            .onChange(of: model.lastExportURL) { _, exportURL in
                if exportURL != nil {
                    activeSheet = .exports
                }
            }
            .onChange(of: activeSheet) { _, sheet in
                if let sheet {
                    CrashReporter.shared.mark("Presenting sheet \(sheet.assistantContext)")
                } else {
                    CrashReporter.shared.mark("Studio timeline")
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
                Text(studioErrorMessage)
            }
    }

    private var studioScroll: some View {
        ScrollView(.vertical) {
            if model.isInitializing {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(Color.studioAccent)
                    Text("Preparing Studio…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 500)
            } else {
                VStack(spacing: 0) {
                    header

                    if model.tracks.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, minHeight: 360)
                    } else {
                        WaveformTimeline(
                            model: model,
                            onOpenTrackEQ: { trackID in
                                selectedEQTrackID = trackID
                                activeSheet = .trackEQ
                            },
                            onOpenTrackEffects: { trackID in
                                selectedEffectsTrackID = trackID
                                activeSheet = .trackEffects
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
                        .frame(minHeight: 420)
                    }

                    TransportBarView(model: model)
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(Color.studioBackground.ignoresSafeArea())
        .background {
            StemArchiveImportCoordinator(
                model: model,
                isImporterPresented: $showStemArchiveImporter
            )
        }
        .background {
            AudioImportCoordinator(
                model: model,
                isPresented: $showImporter
            )
        }
        .background {
            SplitSongCoordinator(
                isPresented: $showSplitPicker,
                selectedSongURL: $selectedSongURL,
                onSongPicked: { activeSheet = .separateSong }
            )
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
    }

    private func clearCrashReport() {
        crashReportText = nil
    }

    private var studioErrorMessage: String {
        if let audioError = model.audioError { return audioError }
        if let freezeError = model.freezeError { return freezeError }
        if let bounceError = model.bounceError { return bounceError }
        return model.separationError ?? ""
    }

    private func sheetContent(for destination: StudioSheet) -> some View {
        Group {
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
            case .trackEffects:
                if let selectedEffectsTrackID {
                    TrackEffectsView(model: model, trackID: selectedEffectsTrackID)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                } else {
                    Color.clear
                }
            case .sessions:
                SessionLibraryView(model: model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .sessionVersions:
                SessionVersionsView(model: model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .templates:
                TemplatesView(model: model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .songwriter:
                SongwriterView(model: model)
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
            case .mastering:
                MasteringView(model: model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .channelPresets:
                ChannelPresetsView(model: model, initialTrackID: nil)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .bounce:
                BounceSettingsView(
                    mode: bounceMode,
                    model: model,
                    sessionName: model.sessionName,
                    duration: model.duration,
                    loopStart: model.loopStart,
                    loopEnd: model.loopEnd,
                    hasLoopRange: model.hasLoopRange,
                    settings: model.bounceSettings
                ) { settings, selectedTrackIDs in
                    switch bounceMode {
                    case .mix:
                        model.bounceMix(settings: settings)
                    case .stems:
                        model.bounceStems(settings: settings, selectedTrackIDs: selectedTrackIDs)
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
            case .separateSong:
                if let selectedSongURL {
                    SeparateSongView(model: model, sourceURL: selectedSongURL)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                } else {
                    Color.clear
                }
            }
        }
        .studioAgentAccess(context: destination.assistantContext)
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
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.8)
                    Text(sessionSubtitle.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                modeSwitch

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

                Menu {
                    Button {
                        activeSheet = .mixer
                    } label: {
                        Label("Channel Mixer", systemImage: "slider.vertical.3")
                    }
                    Button {
                        activeSheet = .masterEffects
                    } label: {
                        Label("Master Effects", systemImage: "speaker.wave.2")
                    }
                    Button {
                        activeSheet = .mastering
                    } label: {
                        Label("Mastering", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        activeSheet = .channelPresets
                    } label: {
                        Label("Channel Presets", systemImage: "bookmark")
                    }
                    Button {
                        activeSheet = .songwriter
                    } label: {
                        Label("AI Songwriter", systemImage: "sparkles")
                    }
                    Divider()
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
                        activeSheet = .sessionVersions
                    } label: {
                        Label("Session Versions", systemImage: "clock.arrow.circlepath")
                    }
                    Button {
                        model.refreshExports()
                        activeSheet = .exports
                    } label: {
                        Label("Mix Exports", systemImage: "square.stack")
                    }
                    Divider()
                    Button {
                        activeSheet = .settings
                    } label: {
                        Label("Studio Settings", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 38, height: 38)
                        .background(Color.studioPanelHighlight.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Studio menu")
            }

            HStack(spacing: 8) {
                Menu {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import Audio Tracks", systemImage: "waveform")
                    }

                    Button {
                        showStemArchiveImporter = true
                    } label: {
                        Label("Import Stems from ZIP", systemImage: "waveform.badge.plus")
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

    // MARK: - Studio mode

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            ForEach(StudioMode.allCases) { mode in
                Button {
                    model.setStudioMode(mode)
                } label: {
                    Text(mode.title.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.4)
                        .frame(width: 34, height: 26)
                        .foregroundStyle(model.studioMode == mode ? Color.black : Color.white.opacity(0.7))
                        .background(
                            model.studioMode == mode ? Color.studioAccent : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.title) studio mode")
                .accessibilityAddTraits(model.studioMode == mode ? .isSelected : [])
            }
        }
        .background(Color.studioPanelHighlight.opacity(0.7), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Studio mode")
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
                    showStemArchiveImporter = true
                } label: {
                    Label("Import Stems from ZIP", systemImage: "waveform.badge.plus")
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

            Button {
                activeSheet = .songwriter
            } label: {
                Label("Write a Song with AI", systemImage: "sparkles")
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

private struct CrashReportBanner: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Last crash report", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.studioAccent)
                Spacer()
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Text("Copy")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.studioAccent, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button("Dismiss", action: onDismiss)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }

            ScrollView {
                Text(text)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)
        }
        .padding(12)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.studioAccent.opacity(0.4), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}

/// Keeps the audio-file importer on its own background child so the studio
/// view chain never carries more than one fileImporter modifier.
private struct AudioImportCoordinator: View {
    @ObservedObject var model: MixerViewModel
    @Binding var isPresented: Bool

    var body: some View {
        Color.clear
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.audio, .mp3, UTType(filenameExtension: "wav") ?? .audio],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    model.importTracks(from: urls)
                }
            }
    }
}

/// Same pattern for the split-song picker.
private struct SplitSongCoordinator: View {
    @Binding var isPresented: Bool
    @Binding var selectedSongURL: URL?
    let onSongPicked: () -> Void

    var body: some View {
        Color.clear
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.audio, .mp3, UTType(filenameExtension: "wav") ?? .audio],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let songURL = urls.first {
                    selectedSongURL = songURL
                    onSongPicked()
                }
            }
    }
}

private enum StudioSheet: String, Identifiable {
    case settings
    case instruments
    case exports
    case trackEQ
    case trackEffects
    case sessions
    case sessionVersions
    case templates
    case mixer
    case masterEffects
    case mastering
    case channelPresets
    case pianoRoll
    case bounce
    case songwriter
    case separateSong

    var id: String { rawValue }

    var assistantContext: String {
        switch self {
        case .settings: return "Studio Settings"
        case .instruments: return "Instruments"
        case .exports: return "Mix Exports"
        case .trackEQ: return "Track EQ"
        case .trackEffects: return "Track Effects"
        case .sessions: return "Sessions"
        case .sessionVersions: return "Session Versions"
        case .templates: return "Templates"
        case .mixer: return "Channel Mixer"
        case .masterEffects: return "Master Effects"
        case .mastering: return "Mastering"
        case .channelPresets: return "Channel Presets"
        case .pianoRoll: return "Piano Roll"
        case .bounce: return "Bounce Settings"
        case .songwriter: return "AI Songwriter"
        case .separateSong: return "Separate Your Song"
        }
    }
}
