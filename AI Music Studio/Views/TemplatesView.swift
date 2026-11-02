//
//  TemplatesView.swift
//  AI Music Studio
//

import SwiftUI

/// Picks a prepared layout and starts a session from it.
struct TemplatesView: View {
    @ObservedObject var model: MixerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTemplateID: String?

    private var templates: [SessionTemplate] { SessionTemplateCatalog.all }

    private var selectedTemplate: SessionTemplate? {
        templates.first { $0.id == selectedTemplateID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Start from a layout that already has its tracks, colours and mixer settings dialled in.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(templates) { template in
                        card(for: template)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }
            .scrollContentBackground(.hidden)
            .background(Color.studioBackground)
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { createBar }
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
        .onAppear(perform: selectStartingTemplate)
    }

    private func card(for template: SessionTemplate) -> some View {
        let isSelected = template.id == selectedTemplateID

        return Button {
            selectedTemplateID = template.id
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 11) {
                    Image(systemName: template.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.black : Color.studioAccent)
                        .frame(width: 38, height: 38)
                        .background(
                            isSelected ? Color.studioAccent : Color.studioAccent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(template.name)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)

                            if template.isSuggested {
                                tag("SUGGESTED")
                            }
                        }

                        Text("\(template.trackCount) TRACKS  ·  \(template.tempoBPM) BPM")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(0.4)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: selectedTemplateID == template.id ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(selectedTemplateID == template.id ? Color.studioAccent : Color.white.opacity(0.22))
                }

                Text(template.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                VStack(spacing: 5) {
                    ForEach(Array(template.tracks.enumerated()), id: \.element.id) { index, slot in
                        lane(slot, index: index)
                    }
                }
            }
            .padding(14)
            .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        selectedTemplateID == template.id ? Color.studioAccent.opacity(0.75) : Color.white.opacity(0.06),
                        lineWidth: selectedTemplateID == template.id ? 1.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(template.name), \(template.trackCount) tracks")
        .accessibilityAddTraits(selectedTemplateID == template.id ? [.isSelected] : [])
    }

    private func lane(_ slot: SessionTemplate.TrackSlot, index: Int) -> some View {
        let color = Color.studioTrackColor(for: index)
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3, height: 14)

            Text(slot.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("\(levelLabel(slot.volume))  \(panLabel(slot.pan))")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
    }

    private var createBar: some View {
        VStack(spacing: 9) {
            if let selectedTemplate {
                Text("\(selectedTemplate.trackCount) TRACKS READY  ·  \(selectedTemplate.tempoBPM) BPM")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
            }

            Button {
                guard let selectedTemplate else { return }
                model.createSession(from: selectedTemplate)
                dismiss()
            } label: {
                Text("Create Session")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color.studioAccent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(selectedTemplate == nil)
            .opacity(selectedTemplate == nil ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color.studioPanel)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(Color.studioAccent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.studioAccent.opacity(0.14), in: Capsule())
    }

    private func levelLabel(_ volume: Float) -> String {
        guard volume > 0.0001 else { return "-∞ dB" }
        let decibels = 20 * log10(Double(volume))
        return String(format: "%.1f dB", decibels)
    }

    private func panLabel(_ pan: Float) -> String {
        guard abs(pan) >= 0.005 else { return "C" }
        let amount = Int((abs(pan) * 100).rounded())
        return pan < 0 ? "L\(amount)" : "R\(amount)"
    }

    /// Preselects the template the open session came from, or the suggested one.
    private func selectStartingTemplate() {
        guard selectedTemplateID == nil else { return }
        if let activeID = model.activeTemplateID,
           templates.contains(where: { $0.id == activeID }) {
            selectedTemplateID = activeID
        } else {
            selectedTemplateID = templates.first?.id
        }
    }
}
