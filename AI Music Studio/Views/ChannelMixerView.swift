//
//  ChannelMixerView.swift
//  AI Music Studio
//

import Foundation
import SwiftUI

/// Full channel mixer: one vertical strip per track plus the master output,
/// with track groups shown as buses above the channels.
struct ChannelMixerView: View {
    @ObservedObject var model: MixerViewModel
    @Environment(\.dismiss) private var dismiss

    private let stripWidth: CGFloat = 88
    private let masterWidth: CGFloat = 96
    private let meterHeight: CGFloat = 168

    @State private var isSelectingGroup = false
    @State private var selectedTrackIDs: Set<UUID> = []
    @State private var isNamingGroup = false
    @State private var groupNameDraft = ""
    @State private var renamingGroupID: UUID?
    @State private var renameDraft = ""
    @State private var isRenamingGroup = false
    @State private var dissolvingGroupID: UUID?
    @State private var isConfirmingDissolve = false

    var body: some View {
        NavigationStack {
            Group {
                if model.tracks.isEmpty {
                    ContentUnavailableView(
                        "No Tracks Yet",
                        systemImage: "slider.vertical.3",
                        description: Text("Import audio or split a song into stems to fill the mixer.")
                    )
                } else {
                    mixerBoard
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.studioBackground)
            .navigationTitle("Mixer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.tracks.count > 1 {
                        if isSelectingGroup {
                            Button("Cancel") { endGroupSelection() }
                        } else {
                            Button {
                                beginGroupSelection()
                            } label: {
                                Image(systemName: "square.3.layers.3d")
                            }
                            .accessibilityLabel("Group tracks")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelectingGroup {
                    groupSelectionBar
                } else {
                    transportFooter
                }
            }
            .alert("New Group", isPresented: $isNamingGroup) {
                TextField("Group name", text: $groupNameDraft)
                Button("Cancel", role: .cancel) { groupNameDraft = "" }
                Button("Create") { createGroupFromSelection() }
            } message: {
                Text("The selected tracks get one fader, mute and solo.")
            }
            .alert("Rename Group", isPresented: $isRenamingGroup) {
                TextField("Group name", text: $renameDraft)
                Button("Cancel", role: .cancel) { renamingGroupID = nil }
                Button("Save") {
                    if let renamingGroupID {
                        model.renameGroup(renamingGroupID, to: renameDraft)
                    }
                    renamingGroupID = nil
                }
            } message: {
                Text("Choose a name for this group.")
            }
            .confirmationDialog(
                "Dissolve this group?",
                isPresented: $isConfirmingDissolve,
                titleVisibility: .visible
            ) {
                Button("Dissolve Group", role: .destructive) {
                    if let dissolvingGroupID {
                        model.deleteGroup(dissolvingGroupID)
                    }
                    dissolvingGroupID = nil
                }
                Button("Cancel", role: .cancel) { dissolvingGroupID = nil }
            } message: {
                Text("The tracks stay in the session and keep their own levels.")
            }
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    private var mixerBoard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(isSelectingGroup ? "SELECT TRACKS TO GROUP" : model.sessionName.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(isSelectingGroup ? Color.studioAccent : Color.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(isSelectingGroup
                    ? "\(selectedTrackIDs.count) SELECTED"
                    : "\(model.tracks.count) \(model.tracks.count == 1 ? "CHANNEL" : "CHANNELS")")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.studioAccent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if !model.groups.isEmpty {
                groupBusRow
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 9) {
                    ForEach(Array(model.tracks.enumerated()), id: \.element.id) { index, track in
                        channelColumn(track, index: index)
                    }

                    masterStrip
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }

            auxReturns
        }
    }

    // MARK: - Aux sends and returns

    private func sendsBlock(for track: Track) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SENDS")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
            auxSendRow(label: "A", value: track.sendA, trackID: track.id, bus: "A")
            if model.isProMode {
                auxSendRow(label: "B", value: track.sendB, trackID: track.id, bus: "B")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func auxSendRow(label: String, value: Float, trackID: UUID, bus: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.studioAccent)
                .frame(width: 8)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { model.setSend(trackID, bus: bus, value: Float($0)) }
                ),
                in: 0...1
            )
            .tint(Color.studioAccent)
            .controlSize(.mini)
            Text("\(Int(value * 100))")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
        }
    }

    private var auxReturns: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AUX RETURNS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            auxReturnRow(model.auxBusA)
            if model.isProMode {
                auxReturnRow(model.auxBusB)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.studioPanel)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
        }
    }

    private func auxReturnRow(_ bus: AuxBusSettings) -> some View {
        HStack(spacing: 10) {
            Text(bus.name.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .frame(width: 52, alignment: .leading)
            Text(bus.effect.title.uppercased())
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Slider(
                value: Binding(
                    get: { Double(bus.level) },
                    set: { newValue in
                        var settings = bus
                        settings.level = Float(newValue)
                        model.updateAuxBus(settings)
                    }
                ),
                in: 0...1
            )
            .tint(Color.studioAccent)

            Button {
                var settings = bus
                settings.isBypassed.toggle()
                model.updateAuxBus(settings)
            } label: {
                Text(bus.isBypassed ? "BYP" : "ON")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .frame(width: 36, height: 24)
                    .foregroundStyle(bus.isBypassed ? Color.secondary : Color.black)
                    .background(
                        bus.isBypassed ? Color.studioPanelHighlight : Color.studioAccent,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Track groups

    private var groupBusRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.groups) { group in
                    groupBusCard(group)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    private func groupBusCard(_ group: TrackGroup) -> some View {
        let color = Color.studioTrackColor(for: group.colorIndex)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)

                Text(group.name.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(color)
                    .lineLimit(1)

                Text("\(group.trackIDs.count)")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Menu {
                    Button {
                        renamingGroupID = group.id
                        renameDraft = group.name
                        isRenamingGroup = true
                    } label: {
                        Label("Rename Group", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        dissolvingGroupID = group.id
                        isConfirmingDissolve = true
                    } label: {
                        Label("Dissolve Group", systemImage: "rectangle.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Group actions for \(group.name)")
            }

            HStack(spacing: 8) {
                stripToggle("M", isOn: group.isMuted, accessibilityLabel: "Mute \(group.name)") {
                    model.toggleGroupMute(group.id)
                }
                stripToggle("S", isOn: group.isSoloed, accessibilityLabel: "Solo \(group.name)") {
                    model.toggleGroupSolo(group.id)
                }

                Slider(
                    value: Binding(
                        get: { Double(group.volume) },
                        set: { model.setGroupVolume(group.id, Float($0)) }
                    ),
                    in: 0...1,
                    onEditingChanged: { isEditing in
                        if !isEditing { model.commitSession() }
                    }
                )
                .tint(color)
                .frame(width: 88)
                .accessibilityLabel("Group level for \(group.name)")

                Text(dbLabel(group.volume))
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.85))
                    .frame(width: 46, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: 258)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Group \(group.name)")
    }

    private func channelColumn(_ track: Track, index: Int) -> some View {
        VStack(spacing: 6) {
            groupBadge(for: track)
                .frame(height: 15)

            channelStrip(track, index: index)
                .overlay {
                    if isSelectingGroup {
                        selectionOverlay(for: track.id)
                    }
                }
        }
    }

    @ViewBuilder
    private func groupBadge(for track: Track) -> some View {
        if let group = model.group(forTrack: track.id) {
            let color = Color.studioTrackColor(for: group.colorIndex)
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                Text(group.name.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .lineLimit(1)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .frame(maxWidth: stripWidth)
            .accessibilityLabel("Group \(group.name)")
        }
    }

    private func selectionOverlay(for trackID: UUID) -> some View {
        let isSelected = selectedTrackIDs.contains(trackID)
        return ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.28)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isSelected ? Color.studioAccent : Color.white.opacity(0.55))
                .padding(7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { toggleSelection(trackID) }
    }

    private var groupSelectionBar: some View {
        HStack(spacing: 10) {
            Text("\(selectedTrackIDs.count) SELECTED")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(selectedTrackIDs.count > 1 ? Color.primary : Color.secondary)

            Spacer(minLength: 0)

            Button("Cancel") { endGroupSelection() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Button {
                groupNameDraft = ""
                isNamingGroup = true
            } label: {
                Text("Create Group")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Color.studioAccent, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(selectedTrackIDs.count < 2)
            .opacity(selectedTrackIDs.count > 1 ? 1 : 0.4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.studioPanel)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
        }
    }

    private func beginGroupSelection() {
        selectedTrackIDs.removeAll()
        isSelectingGroup = true
    }

    private func endGroupSelection() {
        isSelectingGroup = false
        selectedTrackIDs.removeAll()
        groupNameDraft = ""
    }

    private func toggleSelection(_ trackID: UUID) {
        if selectedTrackIDs.contains(trackID) {
            selectedTrackIDs.remove(trackID)
        } else {
            selectedTrackIDs.insert(trackID)
        }
    }

    private func createGroupFromSelection() {
        let members = model.tracks.map(\.id).filter { selectedTrackIDs.contains($0) }
        guard members.count > 1 else {
            groupNameDraft = ""
            return
        }
        model.createGroup(name: groupNameDraft, colorIndex: model.nextGroupColorIndex, trackIDs: members)
        endGroupSelection()
    }

    // MARK: - Channel strips

    private func channelStrip(_ track: Track, index: Int) -> some View {
        let color = Color.studioTrackColor(for: index)

        return VStack(spacing: 8) {
            VStack(spacing: 3) {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)

                Text(track.name)
                    .font(.system(size: 10, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .frame(height: 37)

            if model.isProMode {
                PanKnobView(
                    value: Binding(
                        get: { track.pan },
                        set: { model.setPan(track.id, $0) }
                    ),
                    color: color,
                    onCommit: { model.commitSession() }
                )
                .frame(width: 36, height: 36)

                Text(panLabel(track.pan))
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(height: 10)
            }

            sendsBlock(for: track)

            HStack(spacing: 6) {
                CompactFaderView(
                    value: Binding(
                        get: { track.volume },
                        set: { model.setVolume(track.id, $0) }
                    ),
                    onCommit: { model.commitSession() },
                    color: color
                )
                .frame(width: 28, height: meterHeight)
                .accessibilityLabel("Volume for \(track.name)")

                MiniLevelMeterView(level: model.levels[track.id] ?? 0, color: color)
                    .frame(width: 5, height: meterHeight)
                    .accessibilityHidden(true)
            }

            Text(dbLabel(track.volume))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.85))
                .frame(height: 10)

            HStack(spacing: 5) {
                stripToggle("M", isOn: track.isMuted, accessibilityLabel: "Mute \(track.name)") {
                    model.toggleMute(track.id)
                }
                stripToggle("S", isOn: track.isSoloed, accessibilityLabel: "Solo \(track.name)") {
                    model.toggleSolo(track.id)
                }
            }
            .frame(height: 22)
        }
        .padding(.vertical, 12)
        .frame(width: stripWidth)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Channel \(track.name)")
    }

    private var masterStrip: some View {
        VStack(spacing: 8) {
            Text("MASTER")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.studioAccent)
                .frame(height: 37)

            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.studioAccent)
                .frame(width: 36, height: 36)
                .background(Color.studioAccent.opacity(0.12), in: Circle())

            Text("OUTPUT")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(height: 10)

            HStack(spacing: 6) {
                CompactFaderView(
                    value: Binding(
                        get: { model.masterVolume },
                        set: { model.setMasterVolume($0) }
                    ),
                    onCommit: { model.commitSession() },
                    color: .studioAccent
                )
                .frame(width: 34, height: meterHeight)
                .accessibilityLabel("Master output level")

                MiniLevelMeterView(level: model.masterLevel, color: .studioAccent)
                    .frame(width: 6, height: meterHeight)
                    .accessibilityHidden(true)
            }

            Text(dbLabel(model.masterVolume))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.9))
                .frame(height: 10)

            Text("ST")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(width: masterWidth)
        .background(Color.studioPanelHighlight.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.studioAccent.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Master channel")
    }

    // MARK: - Transport

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

            Text(studioTimeString(model.duration))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
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

    private func stripToggle(
        _ title: String,
        isOn: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
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

    private func dbLabel(_ volume: Float) -> String {
        let clamped = min(1, max(0, volume))
        guard clamped > 0.0001 else { return "-∞ dB" }
        return String(format: "%.1f dB", 20 * log10(clamped))
    }

    private func panLabel(_ pan: Float) -> String {
        let clamped = min(1, max(-1, pan))
        guard abs(clamped) >= 0.005 else { return "C" }
        return clamped < 0 ? "L\(Int(abs(clamped) * 100))" : "R\(Int(clamped * 100))"
    }
}

/// Rotary pan control: drag horizontally to place a track in the stereo field.
private struct PanKnobView: View {
    @Binding var value: Float
    var color: Color = .studioAccent
    var onCommit: () -> Void = {}

    @State private var dragStart: Float?

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                Circle()
                    .fill(Color(white: 0.17))
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                Rectangle()
                    .fill(color)
                    .frame(width: 2, height: size * 0.26)
                    .offset(y: -size * 0.20)
                    .rotationEffect(.degrees(Double(value) * 135))
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if dragStart == nil {
                            dragStart = value
                        }
                        let origin = dragStart ?? value
                        value = min(1, max(-1, origin + Float(gesture.translation.width / 80)))
                    }
                    .onEnded { _ in
                        dragStart = nil
                        onCommit()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Pan")
            .accessibilityValue(panText(value))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value = min(1, value + 0.1)
                case .decrement: value = max(-1, value - 0.1)
                @unknown default: break
                }
                onCommit()
            }
        }
    }

    private func panText(_ pan: Float) -> String {
        let clamped = min(1, max(-1, pan))
        guard abs(clamped) >= 0.005 else { return "Center" }
        return clamped < 0 ? "Left \(Int(abs(clamped) * 100)) percent" : "Right \(Int(clamped * 100)) percent"
    }
}
