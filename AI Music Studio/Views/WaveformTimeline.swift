//
//  WaveformTimeline.swift
//  AI Music Studio
//

import SwiftUI

/// Mobile multitrack arrangement with fixed track controls and a shared timeline.
struct WaveformTimeline: View {
    @ObservedObject var model: MixerViewModel
    var onOpenTrackEQ: (UUID) -> Void = { _ in }
    var onOpenTrackEffects: (UUID) -> Void = { _ in }
    var onOpenPianoRoll: (UUID) -> Void = { _ in }
    var onOpenInstrumentsForTrack: (UUID) -> Void = { _ in }
    var onAddInstrumentTrack: () -> Void = {}

    @State private var zoom: CGFloat = 24
    @State private var pinchBase: CGFloat?
    @State private var isScrubbing = false
    @State private var selectedClipID: UUID?
    @State private var automationTrackID: UUID?
    @State private var selectedAutomationPointID: UUID?
    @State private var takeLaneTrackID: UUID?
    @State private var fadeDragOrigins: [UUID: (in: TimeInterval, out: TimeInterval)] = [:]
    @State private var moveOrigins: [UUID: TimeInterval] = [:]
    @State private var leftTrimOrigins: [UUID: AudioClip] = [:]
    @State private var rightTrimOrigins: [UUID: AudioClip] = [:]
    @State private var loopDragAnchor: TimeInterval?
    @State private var sectionDragOrigins: [UUID: TimeInterval] = [:]
    @State private var renameSectionID: UUID?
    @State private var renameDraft = ""
    @State private var showingRename = false
    @State private var automationParameter = AutomationParameter.volume

    private let gutterWidth: CGFloat = 122
    private let rowHeight: CGFloat = 92
    private let rulerHeight: CGFloat = 62
    private let loopStripHeight: CGFloat = 14
    private let sectionStripHeight: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            if model.isProMode,
               let automationTrack = model.tracks.first(where: { $0.id == automationTrackID }) {
                automationEditToolbar(for: automationTrack)
            }
            if let selectedClipInfo {
                clipEditToolbar(for: selectedClipInfo)
            }

            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    tracksHeader
                        .frame(height: rulerHeight)

                    ForEach(Array(model.tracks.enumerated()), id: \.element.id) { index, track in
                        controlStrip(for: track, index: index)
                            .frame(height: rowHeight)
                    }
                }
                .frame(width: gutterWidth)
                .background(Color.studioPanel)

                ScrollView(.horizontal, showsIndicators: false) {
                    timelineContent
                }
                .defaultScrollAnchor(.leading)
                .overlay(alignment: .topTrailing) { zoomControls }
            }
            .frame(maxHeight: .infinity)
        }
        .background(Color.studioBackground)
        .onChange(of: model.studioMode) { _, mode in
            if mode == .simple {
                automationTrackID = nil
                selectedAutomationPointID = nil
            }
        }
        .alert("Rename Section", isPresented: $showingRename) {
            TextField("Section name", text: $renameDraft)
            Button("Cancel", role: .cancel) { renameSectionID = nil }
            Button("Save") {
                if let id = renameSectionID {
                    model.renameSection(id, to: renameDraft)
                }
                renameSectionID = nil
            }
        } message: {
            Text("Name this part of the song.")
        }
        .sheet(isPresented: Binding(
            get: { takeLaneTrackID != nil },
            set: { isPresented in
                if !isPresented { takeLaneTrackID = nil }
            }
        )) {
            if let trackID = takeLaneTrackID {
                TakeLaneView(model: model, trackID: trackID)
                    .studioAgentAccess(context: "Take Lane")
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func takeBadgeLabel(_ track: Track) -> String {
        let number = track.takes.firstIndex(where: { $0.id == track.activeTakeID }).map { $0 + 1 } ?? 1
        return "T\(number) · \(track.takes.count)"
    }

    private var contentWidth: CGFloat {
        max(300, CGFloat(model.duration) * zoom)
    }

    private var timelineHeight: CGFloat {
        rulerHeight + CGFloat(model.tracks.count) * rowHeight
    }

    private var playheadTime: TimeInterval {
        model.scrubTime ?? model.currentTime
    }

    private var beatDuration: TimeInterval {
        60.0 / Double(model.tempoBPM)
    }

    private var snapInterval: TimeInterval {
        beatDuration
    }

    private var selectedClipInfo: (trackID: UUID, clip: AudioClip)? {
        guard let selectedClipID else { return nil }
        for track in model.tracks {
            if let clip = track.clips.first(where: { $0.id == selectedClipID }) {
                return (track.id, clip)
            }
        }
        return nil
    }

    private func clipEditToolbar(for selection: (trackID: UUID, clip: AudioClip)) -> some View {
        let clipLength = selection.clip.timelineDuration(tempoBPM: model.tempoBPM)
        let canSplit = playheadTime > selection.clip.startTime + 0.05
            && playheadTime < selection.clip.startTime + clipLength - 0.05

        return VStack(spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "waveform.path")
                    .foregroundStyle(Color.studioAccent)
                Text(selection.clip.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    model.previewClip(trackID: selection.trackID, clipID: selection.clip.id)
                } label: {
                    Label("Preview", systemImage: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .accessibilityLabel("Preview selected clip in the session")

                Button {
                    if let splitID = model.splitClip(
                        trackID: selection.trackID,
                        clipID: selection.clip.id,
                        at: playheadTime,
                        snapInterval: snapInterval
                    ) {
                        selectedClipID = splitID
                    }
                } label: {
                    Label("Split", systemImage: "scissors")
                        .font(.system(size: 10, weight: .semibold))
                }
                .disabled(!canSplit)
                .accessibilityLabel("Split selected clip at playhead")

                Button {
                    if let duplicateID = model.duplicateClip(
                        trackID: selection.trackID,
                        clipID: selection.clip.id,
                        snapInterval: snapInterval
                    ) {
                        selectedClipID = duplicateID
                    }
                } label: {
                    Image(systemName: "plus.square.on.square")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Duplicate selected clip")

                Button(role: .destructive) {
                    model.deleteClip(trackID: selection.trackID, clipID: selection.clip.id)
                    selectedClipID = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Delete selected clip")
            }

            HStack(spacing: 9) {
                Label("PITCH", systemImage: "tuningfork")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("−") {
                    model.setClipTransposeSemitones(
                        trackID: selection.trackID,
                        clipID: selection.clip.id,
                        semitones: selection.clip.transposeSemitones - 1
                    )
                }
                .accessibilityLabel("Transpose down one semitone")
                Text(String(format: "%+d st", selection.clip.transposeSemitones))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .frame(minWidth: 42)
                Button("+") {
                    model.setClipTransposeSemitones(
                        trackID: selection.trackID,
                        clipID: selection.clip.id,
                        semitones: selection.clip.transposeSemitones + 1
                    )
                }
                .accessibilityLabel("Transpose up one semitone")
                .disabled(selection.clip.transposeSemitones >= 12)

                Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 18)

                Button {
                    model.setClipSourceTempo(
                        trackID: selection.trackID,
                        clipID: selection.clip.id,
                        bpm: selection.clip.sourceTempoBPM == nil ? Double(model.tempoBPM) : nil
                    )
                } label: {
                    Text(selection.clip.sourceTempoBPM == nil ? "SYNC OFF" : "SYNC ON")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(selection.clip.sourceTempoBPM == nil ? Color.white.opacity(0.65) : Color.studioAccent)
                }
                .accessibilityLabel(selection.clip.sourceTempoBPM == nil ? "Enable tempo sync for clip" : "Disable tempo sync for clip")

                if let sourceTempo = selection.clip.sourceTempoBPM {
                    Button("−") {
                        model.setClipSourceTempo(
                            trackID: selection.trackID,
                            clipID: selection.clip.id,
                            bpm: sourceTempo - 1
                        )
                    }
                    .accessibilityLabel("Decrease clip source tempo")
                    Text("\(Int(sourceTempo.rounded())) → \(model.tempoBPM) BPM")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button("+") {
                        model.setClipSourceTempo(
                            trackID: selection.trackID,
                            clipID: selection.clip.id,
                            bpm: sourceTempo + 1
                        )
                    }
                    .accessibilityLabel("Increase clip source tempo")
                } else {
                    Text("NATURAL TEMPO")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.studioPanel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    private func automationEditToolbar(for track: Track) -> some View {
        HStack(spacing: 8) {
            Image(systemName: automationParameter == .volume ? "chart.xyaxis.line" : "arrow.left.and.right")
                .foregroundStyle(automationColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(automationParameter.title) · \(track.name.uppercased())")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                Text("Tap to add · drag to edit · select a point to delete")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                automationParameterButton(.volume)
                automationParameterButton(.pan)
            }

            if let pointID = selectedAutomationPointID {
                Button(role: .destructive) {
                    deleteAutomationPoint(track: track, pointID: pointID)
                    selectedAutomationPointID = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete selected automation point")
            }

            Button("Done") {
                automationTrackID = nil
                selectedAutomationPointID = nil
            }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.studioAccent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.studioPanel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    private func automationParameterButton(_ parameter: AutomationParameter) -> some View {
        Button {
            automationParameter = parameter
            selectedAutomationPointID = nil
        } label: {
            Text(parameter.shortTitle)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(automationParameter == parameter ? Color.black : Color.white.opacity(0.7))
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    automationParameter == parameter ? automationColor : Color.studioPanelHighlight,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(parameter.accessibilityTitle)
        .accessibilityAddTraits(automationParameter == parameter ? .isSelected : [])
    }

    private var automationColor: Color {
        automationParameter == .volume ? Color.studioAccent : Color.studioPanAutomation
    }

    private var panAutomationColor: Color {
        Color.studioPanAutomation
    }

    private func automationHandles(for track: Track, parameter: AutomationParameter) -> [AutomationHandle] {
        switch parameter {
        case .volume:
            return track.volumeAutomationPoints.map {
                AutomationHandle(id: $0.id, time: $0.time, value: Double($0.gain))
            }
        case .pan:
            return track.panAutomationPoints.map {
                AutomationHandle(id: $0.id, time: $0.time, value: Double($0.pan))
            }
        }
    }

    private func automationUnit(for parameter: AutomationParameter, value: Double) -> Double {
        switch parameter {
        case .volume:
            return min(1, max(0, value))
        case .pan:
            return min(1, max(0, (value + 1) / 2))
        }
    }

    private func automationValue(for parameter: AutomationParameter, unit: Double) -> Double {
        switch parameter {
        case .volume:
            return min(1, max(0, unit))
        case .pan:
            return min(1, max(-1, unit * 2 - 1))
        }
    }

    private func maximumAutomationTime() -> TimeInterval {
        Double(contentWidth / max(zoom, 1))
    }

    private func addAutomationPoint(track: Track, time: TimeInterval, value: Double) {
        switch automationParameter {
        case .volume:
            model.addVolumeAutomationPoint(
                trackID: track.id,
                at: time,
                gain: Float(value),
                snapInterval: snapInterval,
                maximumTime: maximumAutomationTime()
            )
        case .pan:
            model.addPanAutomationPoint(
                trackID: track.id,
                at: time,
                pan: Float(value),
                snapInterval: snapInterval,
                maximumTime: maximumAutomationTime()
            )
        }
    }

    private func moveAutomationPoint(track: Track, pointID: UUID, time: TimeInterval, value: Double) {
        switch automationParameter {
        case .volume:
            model.moveVolumeAutomationPoint(
                trackID: track.id,
                pointID: pointID,
                to: time,
                gain: Float(value),
                snapInterval: snapInterval,
                maximumTime: maximumAutomationTime()
            )
        case .pan:
            model.movePanAutomationPoint(
                trackID: track.id,
                pointID: pointID,
                to: time,
                pan: Float(value),
                snapInterval: snapInterval,
                maximumTime: maximumAutomationTime()
            )
        }
    }

    private func deleteAutomationPoint(track: Track, pointID: UUID) {
        switch automationParameter {
        case .volume:
            model.deleteVolumeAutomationPoint(trackID: track.id, pointID: pointID)
        case .pan:
            model.deletePanAutomationPoint(trackID: track.id, pointID: pointID)
        }
    }

    private var tracksHeader: some View {
        HStack(spacing: 5) {
            Text("4/4")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.studioAccent)
            Text("TRACKS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onAddInstrumentTrack) {
                Image(systemName: "pianokeys")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.studioAccent)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add instrument layer")
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.studioPanel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    private var timelineContent: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ruler
                    .frame(width: contentWidth, height: rulerHeight)

                ForEach(Array(model.tracks.enumerated()), id: \.element.id) { index, track in
                    lane(for: track, index: index)
                        .frame(width: contentWidth, height: rowHeight)
                }
            }

            if model.hasLoopRange {
                Rectangle()
                    .fill(Color.studioAccent.opacity(model.isLoopEnabled ? 0.075 : 0.035))
                    .frame(width: loopWidth, height: CGFloat(model.tracks.count) * rowHeight)
                    .offset(x: loopStartX, y: rulerHeight)
                    .allowsHitTesting(false)
            }

            playhead
                .frame(width: contentWidth, height: timelineHeight, alignment: .topLeading)
        }
        .frame(width: contentWidth, height: timelineHeight)
        .simultaneousGesture(zoomGesture)
    }

    // MARK: - Track controls

    private func controlStrip(for track: Track, index: Int) -> some View {
        let color = Color.studioTrackColor(for: index)
        let group = model.group(forTrack: track.id)

        return VStack(alignment: .leading, spacing: group == nil ? 7 : 5) {
            HStack(spacing: 5) {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(track.name)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                if model.armedTrackID == track.id {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Armed for punch recording")
                }
                if !track.takes.isEmpty {
                    Button {
                        takeLaneTrackID = track.id
                    } label: {
                        Text(takeBadgeLabel(track))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .frame(height: 18)
                            .foregroundStyle(Color.studioAccent)
                            .background(Color.studioAccent.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Take lane for \(track.name)")
                }
                Button {
                    onOpenTrackEQ(track.id)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.studioAccent)
                .accessibilityLabel("Equalizer for \(track.name)")
                Button {
                    onOpenTrackEffects(track.id)
                } label: {
                    Image(systemName: "pedalboard")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.studioAccent)
                .accessibilityLabel("Effects rack for \(track.name)")
                Button {
                    onOpenPianoRoll(track.id)
                } label: {
                    Image(systemName: "pianokeys")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.studioAccent)
                .disabled(track.isFrozen)
                .opacity(track.isFrozen ? 0.35 : 1)
                .accessibilityLabel("Piano roll for \(track.name)")
                if model.isProMode {
                    Button {
                        automationTrackID = automationTrackID == track.id ? nil : track.id
                        selectedAutomationPointID = nil
                        if automationTrackID == track.id { selectedClipID = nil }
                    } label: {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(automationTrackID == track.id ? Color.studioAccent : Color.white.opacity(0.55))
                    .accessibilityLabel("Volume automation for \(track.name)")
                }
                Spacer(minLength: 0)
            }

            if model.isProMode, let group {
                groupBadge(group)
            }

            HStack(spacing: 7) {
                VStack(spacing: 4) {
                    miniToggle("M", isOn: track.isMuted, accessibilityLabel: "Mute \(track.name)") {
                        model.toggleMute(track.id)
                    }
                    miniToggle("S", isOn: track.isSoloed, accessibilityLabel: "Solo \(track.name)") {
                        model.toggleSolo(track.id)
                    }
                }

                if model.isProMode {
                    Button {
                        model.toggleFreeze(trackID: track.id)
                    } label: {
                        Image(systemName: "snowflake")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 22)
                            .foregroundStyle(track.isFrozen ? Color.black : Color.white.opacity(0.7))
                            .background(
                                track.isFrozen ? Color.studioAccent : Color.studioPanelHighlight.opacity(0.7),
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isFreezingTrack)
                    .accessibilityLabel(track.isFrozen ? "Unfreeze \(track.name)" : "Freeze \(track.name) to audio")
                    .accessibilityAddTraits(track.isFrozen ? .isSelected : [])

                    Button {
                        onOpenInstrumentsForTrack(track.id)
                    } label: {
                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 22)
                            .foregroundStyle(Color.studioAccent)
                            .background(Color.studioPanelHighlight.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open instruments for \(track.name)")
                }

                Spacer(minLength: 2)

                CompactFaderView(
                    value: Binding(
                        get: { track.volume },
                        set: { model.setVolume(track.id, $0) }
                    ),
                    onCommit: { model.commitSession() },
                    color: color
                )
                .frame(width: 22, height: 48)
                .accessibilityLabel("Volume for \(track.name)")

                MiniLevelMeterView(level: model.levels[track.id] ?? 0, color: color)
                    .frame(width: 6, height: 48)
                    .accessibilityLabel("Level for \(track.name)")
            }
            .frame(height: group == nil ? 49 : 42)
        }
        .padding(.leading, 8)
        .padding(.trailing, 7)
        .frame(width: gutterWidth, height: rowHeight, alignment: .center)
        .background(Color.studioPanel)
        .overlay(alignment: .leading) {
            Rectangle().fill(color).frame(width: 3)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    private func groupBadge(_ group: TrackGroup) -> some View {
        let color = Color.studioTrackColor(for: group.colorIndex)

        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)

            Text(group.name.uppercased())
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.15), in: Capsule())
        .accessibilityLabel("Group \(group.name)")
    }

    private func miniToggle(
        _ label: String,
        isOn: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
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

    // MARK: - Time ruler and grid

    private var ruler: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let beatSpacing = CGFloat(beatDuration) * zoom
                let beatCount = Int(ceil(model.duration / beatDuration))

                context.fill(
                    Path(CGRect(x: 0, y: loopStripHeight, width: size.width, height: sectionStripHeight)),
                    with: .color(Color.white.opacity(0.02))
                )

                for section in model.sections {
                    let x = CGFloat(section.time) * zoom
                    guard x <= size.width else { continue }
                    var stem = Path()
                    stem.move(to: CGPoint(x: x, y: loopStripHeight))
                    stem.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(stem, with: .color(Color.studioAccent.opacity(0.45)), lineWidth: 1)
                }

                for beatIndex in 0...max(1, beatCount) {
                    let time = Double(beatIndex) * beatDuration
                    let x = CGFloat(time) * zoom
                    guard x <= size.width else { continue }
                    let isBar = beatIndex % 4 == 0

                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: size.height - (isBar ? 13 : 7)))
                    tick.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(
                        tick,
                        with: .color(isBar ? Color.white.opacity(0.62) : Color.white.opacity(0.25)),
                        lineWidth: isBar ? 1.2 : 1
                    )

                    if isBar || beatSpacing >= 11 {
                        let barNumber = beatIndex / 4 + 1
                        let beatNumber = beatIndex % 4 + 1
                        let label = isBar ? "\(barNumber)" : (beatSpacing >= 34 ? "\(barNumber).\(beatNumber)" : "\(beatNumber)")
                        context.draw(
                            Text(label)
                                .font(.system(size: isBar ? 9 : 8, weight: isBar ? .semibold : .regular, design: .monospaced))
                                .foregroundColor(isBar ? .primary : .secondary),
                            at: CGPoint(x: x + 4, y: loopStripHeight + sectionStripHeight + 8),
                            anchor: .leading
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(scrubGesture)

            sectionMarkers

            if model.isPunchEnabled && model.hasPunchRange {
                punchRangeOverlay
            }

            loopStrip
        }
        .background(Color.studioBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }
    }

    // MARK: - Section markers

    private var punchRangeOverlay: some View {
        let startX = CGFloat(max(0, model.punchIn)) * zoom
        let width = max(1, CGFloat(max(0, model.punchOut - model.punchIn)) * zoom)

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.red.opacity(0.16))
                .frame(width: width, height: rulerHeight)
                .offset(x: startX)
            Rectangle()
                .fill(Color.red.opacity(0.85))
                .frame(width: 1.5, height: rulerHeight)
                .offset(x: startX)
            Rectangle()
                .fill(Color.red.opacity(0.85))
                .frame(width: 1.5, height: rulerHeight)
                .offset(x: startX + width)
        }
        .allowsHitTesting(false)
    }

    private var sectionMarkers: some View {
        let sections = model.sections
        return ZStack(alignment: .topLeading) {
            ForEach(sections) { section in
                sectionMarker(section)
                    .offset(x: CGFloat(section.time) * zoom, y: loopStripHeight + 3)
            }
        }
        .frame(width: contentWidth, height: rulerHeight, alignment: .topLeading)
    }

    private func sectionMarker(_ section: SongSection) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "flag.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.black)
            Text(section.name.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(Color.black)
        }
        .padding(.horizontal, 5)
        .frame(height: 18)
        .background(Color.studioAccent, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture { model.seek(to: section.time) }
        .highPriorityGesture(sectionDragGesture(section))
        .contextMenu {
            Button {
                renameSectionID = section.id
                renameDraft = section.name
                showingRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                model.deleteSection(section.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Section \(section.name)")
        .accessibilityHint("Tap to jump to this section.")
    }

    private func sectionDragGesture(_ section: SongSection) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if sectionDragOrigins[section.id] == nil {
                    sectionDragOrigins[section.id] = section.time
                }
                let origin = sectionDragOrigins[section.id] ?? section.time
                let proposed = origin + Double(value.translation.width / max(zoom, 1))
                model.moveSection(section.id, to: proposed)
            }
            .onEnded { _ in
                sectionDragOrigins[section.id] = nil
                model.commitSections()
            }
    }

    // MARK: - Loop strip

    private var loopStartX: CGFloat {
        CGFloat(max(0, model.loopStart)) * zoom
    }

    private var loopWidth: CGFloat {
        max(0, CGFloat(model.loopEnd - model.loopStart) * zoom)
    }

    private var loopStrip: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.04))

                if model.hasLoopRange {
                    Rectangle()
                        .fill(Color.studioAccent.opacity(model.isLoopEnabled ? 0.26 : 0.12))
                        .frame(width: loopWidth)
                        .offset(x: loopStartX)

                    loopEdge(x: loopStartX, isStart: true)
                    loopEdge(x: CGFloat(model.loopEnd) * zoom, isStart: false)
                } else {
                    Text("DRAG TO SET A LOOP")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color.white.opacity(0.35))
                        .padding(.leading, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geometry.size.width, height: loopStripHeight)
            .contentShape(Rectangle())
            .gesture(loopStripGesture())
        }
        .frame(height: loopStripHeight)
    }

    private func loopEdge(x: CGFloat, isStart: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.studioAccent)
                .frame(width: 2)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.studioAccent)
                .frame(width: 10, height: 7)
        }
        .frame(width: 22, height: loopStripHeight)
        .contentShape(Rectangle())
        .offset(x: max(0, x - 11))
        .gesture(loopHandleGesture(isStart: isStart))
        .accessibilityLabel(isStart ? "Loop start" : "Loop end")
        .accessibilityValue(studioTimeString(isStart ? model.loopStart : model.loopEnd))
    }

    private func loopStripGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard abs(value.translation.width) > 2 else { return }
                if loopDragAnchor == nil {
                    loopDragAnchor = snappedLoopTime(Double(value.startLocation.x) / max(zoom, 1))
                }
                guard let anchor = loopDragAnchor else { return }
                let current = snappedLoopTime(Double(value.location.x) / max(zoom, 1))
                model.setLoopRange(start: min(anchor, current), end: max(anchor, current))
            }
            .onEnded { _ in
                defer { loopDragAnchor = nil }
                guard loopDragAnchor != nil else { return }
                model.commitLoopChange()
            }
    }

    private func loopHandleGesture(isStart: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let origin = isStart ? model.loopStart : model.loopEnd
                let proposed = origin + Double(value.translation.width / max(zoom, 1))
                let time = snappedLoopTime(proposed)
                if isStart {
                    model.setLoopStart(time)
                } else {
                    model.setLoopEnd(time)
                }
            }
            .onEnded { _ in
                model.commitLoopChange()
            }
    }

    private func snappedLoopTime(_ time: TimeInterval) -> TimeInterval {
        let step = max(0.05, snapInterval)
        return max(0, (time / step).rounded() * step)
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !isScrubbing {
                    model.beginScrub()
                    isScrubbing = true
                }
                model.updateScrub(Double(max(0, gesture.location.x) / zoom))
            }
            .onEnded { _ in
                model.endScrub()
                isScrubbing = false
            }
    }

    // MARK: - Waveform lanes and playhead

    private func lane(for track: Track, index: Int) -> some View {
        let color = Color.studioTrackColor(for: index)

        return ZStack(alignment: .leading) {
            Color.white.opacity(0.025)
            timelineGrid

            ForEach(track.playbackClips) { clip in
                editableClip(trackID: track.id, clip: clip, color: color)
                    .offset(x: CGFloat(clip.startTime) * zoom)
                    .allowsHitTesting(automationTrackID != track.id && !track.isFrozen)
            }

            if model.isProMode, automationTrackID == track.id {
                let activeParameter = automationParameter
                let otherParameter: AutomationParameter = activeParameter == .volume ? .pan : .volume
                let otherHandles = automationHandles(for: track, parameter: otherParameter)

                AutomationLaneEditor(
                    handles: automationHandles(for: track, parameter: activeParameter),
                    zoom: zoom,
                    selectedPointID: selectedAutomationPointID,
                    color: automationColor,
                    unitForValue: { automationUnit(for: activeParameter, value: $0) },
                    valueForUnit: { automationValue(for: activeParameter, unit: $0) },
                    onSelect: { selectedAutomationPointID = $0 },
                    onAdd: { time, value in
                        addAutomationPoint(track: track, time: time, value: value)
                    },
                    onMove: { pointID, time, value in
                        moveAutomationPoint(track: track, pointID: pointID, time: time, value: value)
                    },
                    onCommit: { model.commitSession() }
                )
                .frame(width: contentWidth, height: rowHeight)
                .overlay {
                    if !otherHandles.isEmpty {
                        AutomationCurveView(
                            handles: otherHandles,
                            zoom: zoom,
                            color: Color.white.opacity(0.22),
                            unitForValue: { automationUnit(for: otherParameter, value: $0) }
                        )
                        .allowsHitTesting(false)
                    }
                }
            } else if model.isProMode,
                      !track.volumeAutomationPoints.isEmpty || !track.panAutomationPoints.isEmpty {
                ZStack {
                    if !track.volumeAutomationPoints.isEmpty {
                        AutomationCurveView(
                            handles: automationHandles(for: track, parameter: .volume),
                            zoom: zoom,
                            color: .studioAccent,
                            unitForValue: { automationUnit(for: .volume, value: $0) }
                        )
                    }
                    if !track.panAutomationPoints.isEmpty {
                        AutomationCurveView(
                            handles: automationHandles(for: track, parameter: .pan),
                            zoom: zoom,
                            color: panAutomationColor,
                            unitForValue: { automationUnit(for: .pan, value: $0) }
                        )
                    }
                }
                .frame(width: contentWidth, height: rowHeight)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if model.isProMode, !track.takes.isEmpty {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(track.takes.enumerated()), id: \.element.id) { index, take in
                        let isActive = track.activeTakeID == take.id
                        Button {
                            model.auditionTake(trackID: track.id, takeID: take.id)
                        } label: {
                            Text("T\(index + 1)")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .frame(width: max(24, CGFloat(take.duration) * zoom), height: 18, alignment: .leading)
                                .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.82))
                                .background(
                                    isActive ? Color.studioAccent : Color.studioPanelHighlight,
                                    in: RoundedRectangle(cornerRadius: 4)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(isActive ? Color.studioAccent : Color.white.opacity(0.18), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .offset(x: CGFloat(take.startTime) * zoom)
                        .accessibilityLabel("Audition take \(index + 1) of \(track.name)")
                    }
                }
                .frame(width: contentWidth, height: 18, alignment: .topLeading)
                .padding(.bottom, 4)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    private func editableClip(trackID: UUID, clip: AudioClip, color: Color) -> some View {
        let isSelected = selectedClipID == clip.id
        let timelineDuration = clip.timelineDuration(tempoBPM: model.tempoBPM)
        let clipWidth = max(52, CGFloat(timelineDuration) * zoom)

        return HStack(spacing: 0) {
            if isSelected {
                trimHandle(trackID: trackID, clip: clip, edge: .left)
            } else {
                Color.clear.frame(width: 5)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(clip.name.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.primary.opacity(0.88))
                WaveformLane(peaks: model.clipWaveformPeaks[clip.id] ?? [], color: color)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { selectedClipID = clip.id }
            .gesture(moveGesture(trackID: trackID, clip: clip))

            if isSelected {
                trimHandle(trackID: trackID, clip: clip, edge: .right)
            } else {
                Color.clear.frame(width: 5)
            }
        }
        .frame(width: clipWidth, height: rowHeight - 18)
        .background(color.opacity(clip.isOriginal ? 0.16 : 0.30), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? Color.studioAccent : color.opacity(0.68), lineWidth: isSelected ? 1.8 : 1)
        }
        .overlay {
            if model.isProMode, clip.fadeIn > 0 || clip.fadeOut > 0 {
                ClipFadeCurve(
                    fadeIn: clip.fadeIn,
                    fadeOut: clip.fadeOut,
                    duration: timelineDuration
                )
                .stroke(Color.black.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if model.isProMode, isSelected {
                fadeHandle(trackID: trackID, clip: clip, edge: .in)
                    .offset(x: CGFloat(min(clip.fadeIn, timelineDuration * 0.5)) * zoom - 7, y: 4)
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.isProMode, isSelected {
                fadeHandle(trackID: trackID, clip: clip, edge: .out)
                    .offset(x: -CGFloat(min(clip.fadeOut, timelineDuration * 0.5)) * zoom + 7, y: 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Audio clip \(clip.name)")
    }

    private enum FadeEdge {
        case `in`
        case out
    }

    private func fadeHandle(trackID: UUID, clip: AudioClip, edge: FadeEdge) -> some View {
        Circle()
            .fill(Color.studioAccent)
            .frame(width: 14, height: 14)
            .overlay {
                Circle().stroke(Color.black.opacity(0.45), lineWidth: 1)
            }
            .contentShape(Rectangle().size(width: 26, height: 26))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if fadeDragOrigins[clip.id] == nil {
                            fadeDragOrigins[clip.id] = (clip.fadeIn, clip.fadeOut)
                        }
                        let origin = fadeDragOrigins[clip.id] ?? (clip.fadeIn, clip.fadeOut)
                        let delta = Double(value.translation.width / max(zoom, 1))
                        if edge == .in {
                            model.setClipFades(
                                trackID: trackID,
                                clipID: clip.id,
                                fadeIn: origin.in + delta,
                                fadeOut: origin.out
                            )
                        } else {
                            model.setClipFades(
                                trackID: trackID,
                                clipID: clip.id,
                                fadeIn: origin.in,
                                fadeOut: origin.out - delta
                            )
                        }
                    }
                    .onEnded { _ in
                        fadeDragOrigins[clip.id] = nil
                    }
            )
            .accessibilityLabel(edge == .in ? "Fade in" : "Fade out")
    }

    private func moveGesture(trackID: UUID, clip: AudioClip) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                selectedClipID = clip.id
                if moveOrigins[clip.id] == nil {
                    moveOrigins[clip.id] = clip.startTime
                }
                let origin = moveOrigins[clip.id] ?? clip.startTime
                model.moveClip(
                    trackID: trackID,
                    clipID: clip.id,
                    to: origin + Double(value.translation.width / zoom),
                    snapInterval: snapInterval
                )
            }
            .onEnded { value in
                let origin = moveOrigins.removeValue(forKey: clip.id) ?? clip.startTime
                model.moveClip(
                    trackID: trackID,
                    clipID: clip.id,
                    to: origin + Double(value.translation.width / zoom),
                    snapInterval: snapInterval
                )
                model.commitClipChanges()
            }
    }

    private func trimHandle(trackID: UUID, clip: AudioClip, edge: TimelineTrimEdge) -> some View {
        Rectangle()
            .fill(Color.clear)
            .overlay {
                Capsule()
                    .fill(Color.white)
                    .frame(width: 4, height: 30)
                    .overlay(Capsule().stroke(Color.studioAccent, lineWidth: 1))
            }
            .frame(width: 16)
            .contentShape(Rectangle())
            .highPriorityGesture(trimGesture(trackID: trackID, clip: clip, edge: edge))
            .accessibilityLabel(edge == .left ? "Trim clip start" : "Trim clip end")
    }

    private func trimGesture(trackID: UUID, clip: AudioClip, edge: TimelineTrimEdge) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                selectedClipID = clip.id
                switch edge {
                case .left:
                    if leftTrimOrigins[clip.id] == nil { leftTrimOrigins[clip.id] = clip }
                    let original = leftTrimOrigins[clip.id] ?? clip
                    model.trimClipStart(
                        trackID: trackID,
                        clipID: clip.id,
                        original: original,
                        to: original.startTime + Double(value.translation.width / zoom),
                        snapInterval: snapInterval
                    )
                case .right:
                    if rightTrimOrigins[clip.id] == nil { rightTrimOrigins[clip.id] = clip }
                    let original = rightTrimOrigins[clip.id] ?? clip
                    model.trimClipEnd(
                        trackID: trackID,
                        clipID: clip.id,
                        original: original,
                        to: original.startTime + original.timelineDuration(tempoBPM: model.tempoBPM) + Double(value.translation.width / zoom),
                        snapInterval: snapInterval
                    )
                }
            }
            .onEnded { value in
                switch edge {
                case .left:
                    let original = leftTrimOrigins.removeValue(forKey: clip.id) ?? clip
                    model.trimClipStart(
                        trackID: trackID,
                        clipID: clip.id,
                        original: original,
                        to: original.startTime + Double(value.translation.width / zoom),
                        snapInterval: snapInterval
                    )
                case .right:
                    let original = rightTrimOrigins.removeValue(forKey: clip.id) ?? clip
                    model.trimClipEnd(
                        trackID: trackID,
                        clipID: clip.id,
                        original: original,
                        to: original.startTime + original.timelineDuration(tempoBPM: model.tempoBPM) + Double(value.translation.width / zoom),
                        snapInterval: snapInterval
                    )
                }
                model.commitClipChanges()
            }
    }

    private var timelineGrid: some View {
        Canvas { context, size in
            let beatSpacing = CGFloat(beatDuration) * zoom
            guard beatSpacing > 0 else { return }
            var x: CGFloat = 0
            var beatIndex = 0

            while x <= size.width {
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                let isBar = beatIndex % 4 == 0
                context.stroke(
                    line,
                    with: .color(isBar ? Color.white.opacity(0.16) : Color.white.opacity(0.06)),
                    lineWidth: isBar ? 1.1 : 1
                )
                x += beatSpacing
                beatIndex += 1
            }
        }
        .allowsHitTesting(false)
    }

    private var playhead: some View {
        Canvas { context, size in
            let x = CGFloat(playheadTime) * zoom
            guard x >= 0, x <= size.width else { return }

            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(line, with: .color(.studioAccent), lineWidth: 1.5)

            var marker = Path()
            marker.move(to: CGPoint(x: x - 5, y: 0))
            marker.addLine(to: CGPoint(x: x + 5, y: 0))
            marker.addLine(to: CGPoint(x: x, y: 8))
            marker.closeSubpath()
            context.fill(marker, with: .color(.studioAccent))
        }
        .allowsHitTesting(false)
    }

    // MARK: - Zoom

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if let base = pinchBase {
                    zoom = min(200, max(6, base * value.magnification))
                } else {
                    pinchBase = zoom
                }
            }
            .onEnded { _ in
                pinchBase = nil
            }
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            zoomButton(symbol: "minus.magnifyingglass") {
                withAnimation(.easeOut(duration: 0.18)) {
                    zoom = max(6, zoom / 1.4)
                }
            }

            zoomButton(symbol: "plus.magnifyingglass") {
                withAnimation(.easeOut(duration: 0.18)) {
                    zoom = min(200, zoom * 1.4)
                }
            }
        }
        .padding(4)
        .background(Color.studioPanel.opacity(0.94), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
        .padding(6)
    }

    private func zoomButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 29, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol.hasPrefix("minus") ? "Zoom out" : "Zoom in")
    }
}

private enum TimelineTrimEdge: Equatable {
    case left
    case right
}

/// Slim vertical fader for a track control strip.
struct CompactFaderView: View {
    @Binding var value: Float
    var onCommit: () -> Void = {}
    var color: Color = .studioAccent

    private let thumbHeight: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.height - thumbHeight)
            let thumbTop = CGFloat(1 - value) * usable
            let fillHeight = max(0, geo.size.height - thumbTop - thumbHeight / 2)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color(white: 0.3))
                    .frame(width: 4)

                VStack {
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(color)
                        .frame(width: 4, height: fillHeight)
                }

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(white: 0.92))
                    .frame(width: 20, height: thumbHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(color, lineWidth: 1.5)
                    )
                    .offset(y: thumbTop)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        update(gesture, height: geo.size.height)
                    }
                    .onEnded { gesture in
                        update(gesture, height: geo.size.height)
                        onCommit()
                    }
            )
        }
    }

    private func update(_ gesture: DragGesture.Value, height: CGFloat) {
        let usable = max(1, height - thumbHeight)
        let y = min(max(0, gesture.location.y - thumbHeight / 2), usable)
        value = Float(1 - y / usable)
    }
}

/// Thin vertical level meter for a track control strip.
struct MiniLevelMeterView: View {
    let level: Float
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color(white: 0.3))

                Capsule()
                    .fill(color)
                    .frame(height: geo.size.height * CGFloat(min(1, max(0, level))))
            }
            .clipShape(Capsule())
        }
    }
}

/// Draws a track's peak envelope as vertical bars across the lane.
struct WaveformLane: View {
    let peaks: [Float]
    var color: Color = .studioAccent

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty, size.width > 0 else { return }
            let midY = size.height / 2
            var path = Path()
            var x: CGFloat = 0
            let step = max(2, size.width / 600)

            while x < size.width {
                let bucket = min(peaks.count - 1, Int(Double(x / size.width) * Double(peaks.count)))
                let peak = CGFloat(min(1, max(0, peaks[bucket])))
                let half = peak * (size.height / 2 - 2)
                path.move(to: CGPoint(x: x, y: midY - half))
                path.addLine(to: CGPoint(x: x, y: midY + half))
                x += step
            }

            context.stroke(path, with: .color(color), lineWidth: 1.2)
        }
    }
}



private struct VolumeAutomationCurve: View {
    let points: [VolumeAutomationPoint]
    let zoom: CGFloat
    let color: Color

    private let verticalInset: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let ordered = points.sorted { $0.time < $1.time }
            guard let first = ordered.first, size.width > 0 else { return }

            var path = Path()
            let firstY = y(for: first.gain, height: size.height)
            path.move(to: CGPoint(x: 0, y: firstY))
            let firstX = CGFloat(first.time) * zoom
            if firstX > 0 {
                path.addLine(to: CGPoint(x: min(size.width, firstX), y: firstY))
            }

            if ordered.count > 1 {
                for index in 1..<ordered.count {
                    let left = ordered[index - 1]
                    let right = ordered[index]
                    let segmentCount = 16
                    for step in 1...segmentCount {
                        let progress = CGFloat(step) / CGFloat(segmentCount)
                        let eased = progress * progress * (3 - 2 * progress)
                        let gain = left.gain + (right.gain - left.gain) * Float(eased)
                        let time = left.time + (right.time - left.time) * Double(progress)
                        path.addLine(to: CGPoint(
                            x: min(size.width, CGFloat(time) * zoom),
                            y: y(for: gain, height: size.height)
                        ))
                    }
                }
            }

            if let last = ordered.last {
                let lastX = CGFloat(last.time) * zoom
                if lastX < size.width {
                    path.addLine(to: CGPoint(x: size.width, y: y(for: last.gain, height: size.height)))
                }
            }

            context.stroke(path, with: .color(color.opacity(0.95)), lineWidth: 2)
            for point in ordered {
                let pointX = min(max(0, CGFloat(point.time) * zoom), size.width)
                let pointY = y(for: point.gain, height: size.height)
                let marker = Path(ellipseIn: CGRect(x: pointX - 3, y: pointY - 3, width: 6, height: 6))
                context.fill(marker, with: .color(color))
            }
        }
    }

    fileprivate func y(for gain: Float, height: CGFloat) -> CGFloat {
        let usableHeight = max(1, height - verticalInset * 2)
        let boundedGain = min(1, max(0, CGFloat(gain)))
        return verticalInset + (1 - boundedGain) * usableHeight
    }
}

private struct VolumeAutomationEditor: View {
    let points: [VolumeAutomationPoint]
    let zoom: CGFloat
    let selectedPointID: UUID?
    let color: Color
    var onSelect: (UUID) -> Void
    var onAdd: (TimeInterval, Float) -> Void
    var onMove: (UUID, TimeInterval, Float) -> Void
    var onCommit: () -> Void

    @State private var dragOrigins: [UUID: VolumeAutomationPoint] = [:]
    private let verticalInset: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let x = min(max(0, value.location.x), geometry.size.width)
                                onAdd(
                                    Double(x / max(zoom, 1)),
                                    gain(at: value.location.y, height: geometry.size.height)
                                )
                            }
                    )

                VolumeAutomationCurve(points: points, zoom: zoom, color: color)
                    .allowsHitTesting(false)

                ForEach(points) { point in
                    Circle()
                        .fill(Color.studioPanel)
                        .frame(width: 15, height: 15)
                        .overlay(Circle().stroke(color, lineWidth: 2))
                        .position(
                            x: min(max(0, CGFloat(point.time) * zoom), geometry.size.width),
                            y: y(for: point.gain, height: geometry.size.height)
                        )
                        .onTapGesture { onSelect(point.id) }
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    onSelect(point.id)
                                    let origin = dragOrigins[point.id] ?? point
                                    if dragOrigins[point.id] == nil {
                                        dragOrigins[point.id] = point
                                    }
                                    update(point: point, origin: origin, translation: value.translation, size: geometry.size)
                                }
                                .onEnded { value in
                                    let origin = dragOrigins.removeValue(forKey: point.id) ?? point
                                    update(point: point, origin: origin, translation: value.translation, size: geometry.size)
                                    onCommit()
                                }
                        )
                        .accessibilityLabel("Volume automation point, \(Int(point.gain * 100)) percent")
                        .accessibilityHint("Tap to select or drag to adjust.")
                        .accessibilityAddTraits(selectedPointID == point.id ? .isSelected : [])
                }
            }
        }
    }

    private func update(
        point: VolumeAutomationPoint,
        origin: VolumeAutomationPoint,
        translation: CGSize,
        size: CGSize
    ) {
        let maximumTime = Double(size.width / max(zoom, 1))
        let time = min(maximumTime, max(0, origin.time + Double(translation.width / max(zoom, 1))))
        let usableHeight = max(1, size.height - verticalInset * 2)
        let gain = origin.gain - Float(translation.height / usableHeight)
        onMove(point.id, time, min(1, max(0, gain)))
    }

    private func gain(at y: CGFloat, height: CGFloat) -> Float {
        let usableHeight = max(1, height - verticalInset * 2)
        let normalized = min(1, max(0, (y - verticalInset) / usableHeight))
        return Float(1 - normalized)
    }

    private func y(for gain: Float, height: CGFloat) -> CGFloat {
        let usableHeight = max(1, height - verticalInset * 2)
        return verticalInset + (1 - CGFloat(min(1, max(0, gain)))) * usableHeight
    }
}


// MARK: - Automation lanes

enum AutomationParameter: String {
    case volume
    case pan

    var title: String {
        self == .volume ? "VOLUME" : "PAN"
    }

    var shortTitle: String {
        self == .volume ? "VOL" : "PAN"
    }

    var accessibilityTitle: String {
        self == .volume ? "Volume automation" : "Pan automation"
    }
}

private struct AutomationHandle: Identifiable {
    let id: UUID
    var time: TimeInterval
    var value: Double
}

/// Draws an automation curve from a set of handles.
private struct AutomationCurveView: View {
    let handles: [AutomationHandle]
    let zoom: CGFloat
    let color: Color
    let unitForValue: (Double) -> Double

    private let verticalInset: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let points = handles.sorted { $0.time < $1.time }
            guard let first = points.first, size.width > 0 else { return }

            let usableHeight = max(1, size.height - verticalInset * 2)
            let yFor: (Double) -> CGFloat = { value in
                let unit = min(1, max(0, unitForValue(value)))
                return verticalInset + (1 - CGFloat(unit)) * usableHeight
            }

            var path = Path()
            let firstY = yFor(first.value)
            path.move(to: CGPoint(x: 0, y: firstY))
            let firstX = CGFloat(first.time) * zoom
            if firstX > 0 {
                path.addLine(to: CGPoint(x: min(size.width, firstX), y: firstY))
            }

            if points.count > 1 {
                for index in 1..<points.count {
                    let left = points[index - 1]
                    let right = points[index]
                    let segmentCount = 16
                    for step in 1...segmentCount {
                        let progress = Double(step) / Double(segmentCount)
                        let eased = progress * progress * (3 - 2 * progress)
                        let value = left.value + (right.value - left.value) * eased
                        let time = left.time + (right.time - left.time) * progress
                        path.addLine(to: CGPoint(
                            x: min(size.width, CGFloat(time) * zoom),
                            y: yFor(value)
                        ))
                    }
                }
            }

            if let last = points.last {
                let lastX = CGFloat(last.time) * zoom
                if lastX < size.width {
                    path.addLine(to: CGPoint(x: size.width, y: yFor(last.value)))
                }
            }

            context.stroke(path, with: .color(color.opacity(0.95)), lineWidth: 2)

            for point in points {
                let pointX = min(max(0, CGFloat(point.time) * zoom), size.width)
                let pointY = yFor(point.value)
                context.fill(
                    Path(ellipseIn: CGRect(x: pointX - 3, y: pointY - 3, width: 6, height: 6)),
                    with: .color(color)
                )
            }
        }
    }
}

/// Draws a clip's fade envelope across its width.
private struct ClipFadeCurve: Shape {
    let fadeIn: TimeInterval
    let fadeOut: TimeInterval
    let duration: TimeInterval

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard duration > 0 else { return path }
        let inWidth = CGFloat(min(fadeIn, duration) / duration) * rect.width
        let outWidth = CGFloat(min(fadeOut, duration) / duration) * rect.width

        path.move(to: CGPoint(x: rect.minX, y: fadeIn > 0 ? rect.maxY : rect.minY))
        if inWidth > 0 {
            path.addLine(to: CGPoint(x: rect.minX + inWidth, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX - outWidth, y: rect.minY))
        if outWidth > 0 {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        return path
    }
}

private struct AutomationLaneEditor: View {
    let handles: [AutomationHandle]
    let zoom: CGFloat
    let selectedPointID: UUID?
    let color: Color
    let unitForValue: (Double) -> Double
    let valueForUnit: (Double) -> Double
    var onSelect: (UUID) -> Void
    var onAdd: (TimeInterval, Double) -> Void
    var onMove: (UUID, TimeInterval, Double) -> Void
    var onCommit: () -> Void

    @State private var dragOrigins: [UUID: AutomationHandle] = [:]
    private let verticalInset: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let x = min(max(0, value.location.x), geometry.size.width)
                                onAdd(
                                    Double(x / max(zoom, 1)),
                                    valueAt(y: value.location.y, height: geometry.size.height)
                                )
                            }
                    )

                AutomationCurveView(
                    handles: handles,
                    zoom: zoom,
                    color: color,
                    unitForValue: unitForValue
                )
                .allowsHitTesting(false)

                ForEach(handles) { handle in
                    Circle()
                        .fill(Color.studioPanel)
                        .frame(width: 15, height: 15)
                        .overlay(Circle().stroke(color, lineWidth: 2))
                        .position(
                            x: min(max(0, CGFloat(handle.time) * zoom), geometry.size.width),
                            y: y(for: handle.value, height: geometry.size.height)
                        )
                        .onTapGesture { onSelect(handle.id) }
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    onSelect(handle.id)
                                    if dragOrigins[handle.id] == nil {
                                        dragOrigins[handle.id] = handle
                                    }
                                    let origin = dragOrigins[handle.id] ?? handle
                                    update(handle: handle, origin: origin, translation: value.translation, size: geometry.size)
                                }
                                .onEnded { value in
                                    let origin = dragOrigins.removeValue(forKey: handle.id) ?? handle
                                    update(handle: handle, origin: origin, translation: value.translation, size: geometry.size)
                                    onCommit()
                                }
                        )
                        .accessibilityLabel("Automation point, \(Int(unitForValue(handle.value) * 100)) percent")
                        .accessibilityHint("Tap to select or drag to adjust.")
                        .accessibilityAddTraits(selectedPointID == handle.id ? .isSelected : [])
                }
            }
        }
    }

    private func update(
        handle: AutomationHandle,
        origin: AutomationHandle,
        translation: CGSize,
        size: CGSize
    ) {
        let maximumTime = Double(size.width / max(zoom, 1))
        let time = min(maximumTime, max(0, origin.time + Double(translation.width / max(zoom, 1))))
        let usableHeight = max(1, size.height - verticalInset * 2)
        let unit = unitForValue(origin.value) - Double(translation.height / usableHeight)
        onMove(handle.id, time, valueForUnit(min(1, max(0, unit))))
    }

    private func valueAt(y: CGFloat, height: CGFloat) -> Double {
        let usableHeight = max(1, height - verticalInset * 2)
        let normalized = min(1, max(0, (y - verticalInset) / usableHeight))
        return valueForUnit(1 - Double(normalized))
    }

    private func y(for value: Double, height: CGFloat) -> CGFloat {
        let usableHeight = max(1, height - verticalInset * 2)
        let unit = min(1, max(0, unitForValue(value)))
        return verticalInset + (1 - CGFloat(unit)) * usableHeight
    }
}
