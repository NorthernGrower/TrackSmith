//
//  WaveformTimeline.swift
//  AI Music Studio
//

import SwiftUI

/// Mobile multitrack arrangement with fixed track controls and a shared timeline.
struct WaveformTimeline: View {
    @ObservedObject var model: MixerViewModel
    var onOpenTrackEQ: (UUID) -> Void = { _ in }

    @State private var zoom: CGFloat = 24
    @State private var pinchBase: CGFloat?
    @State private var isScrubbing = false
    @State private var selectedClipID: UUID?
    @State private var moveOrigins: [UUID: TimeInterval] = [:]
    @State private var leftTrimOrigins: [UUID: AudioClip] = [:]
    @State private var rightTrimOrigins: [UUID: AudioClip] = [:]

    private let gutterWidth: CGFloat = 122
    private let rowHeight: CGFloat = 92
    private let rulerHeight: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
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
        let canSplit = playheadTime > selection.clip.startTime + 0.05
            && playheadTime < selection.clip.startTime + selection.clip.duration - 0.05

        return HStack(spacing: 7) {
            Image(systemName: "waveform.path")
                .foregroundStyle(Color.studioAccent)
            Text(selection.clip.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

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
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.studioPanel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
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
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
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

            playhead
                .frame(width: contentWidth, height: timelineHeight, alignment: .topLeading)
        }
        .frame(width: contentWidth, height: timelineHeight)
        .simultaneousGesture(zoomGesture)
    }

    // MARK: - Track controls

    private func controlStrip(for track: Track, index: Int) -> some View {
        let color = Color.studioTrackColor(for: index)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(track.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
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
                Spacer(minLength: 0)
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

                Spacer(minLength: 3)

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
            .frame(height: 49)
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
        Canvas { context, size in
            let beatSpacing = CGFloat(beatDuration) * zoom
            let beatCount = Int(ceil(model.duration / beatDuration))

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
                        at: CGPoint(x: x + 4, y: 9),
                        anchor: .leading
                    )
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(scrubGesture)
        .background(Color.studioBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }
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

            ForEach(track.clips) { clip in
                editableClip(trackID: track.id, clip: clip, color: color)
                    .offset(x: CGFloat(clip.startTime) * zoom)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    private func editableClip(trackID: UUID, clip: AudioClip, color: Color) -> some View {
        let isSelected = selectedClipID == clip.id
        let clipWidth = max(52, CGFloat(clip.duration) * zoom)

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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Audio clip \(clip.name)")
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
                        to: original.startTime + original.duration + Double(value.translation.width / zoom),
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
                        to: original.startTime + original.duration + Double(value.translation.width / zoom),
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
