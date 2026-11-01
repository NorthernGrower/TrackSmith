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

    var body: some View {
        ZStack {
            Color.studioBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if model.tracks.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    WaveformTimeline(model: model) { trackID in
                        selectedEQTrackID = trackID
                        activeSheet = .trackEQ
                    }
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
                InstrumentRackView(model: model)
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
            }
        }
        .onChange(of: model.lastExportURL) { _, exportURL in
            if exportURL != nil {
                activeSheet = .exports
            }
        }
        .alert(Text(model.bounceError == nil ? "Separation Failed" : "Bounce Failed"), isPresented: studioErrorBinding) {
            Button("OK", role: .cancel) {
                model.separationError = nil
                model.clearBounceError()
            }
        } message: {
            Text(model.bounceError ?? model.separationError ?? "")
        }
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

                Menu {
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
                } label: {
                    StudioToolbarButton(title: "Add Track", systemImage: "plus", isProminent: true)
                }

                Button {
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

                Button {
                    model.bounceMix()
                } label: {
                    StudioToolbarButton(title: "Bounce", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.plain)
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
            } label: {
                StudioToolbarButton(title: "Add Track", systemImage: "plus", isProminent: true)
            }
            .padding(.top, 3)
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
                    Text("Bouncing Mix")
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

    private var studioErrorBinding: Binding<Bool> {
        Binding(
            get: { model.separationError != nil || model.bounceError != nil },
            set: { shouldShow in
                if !shouldShow {
                    model.separationError = nil
                    model.clearBounceError()
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

    var id: String { rawValue }
}
