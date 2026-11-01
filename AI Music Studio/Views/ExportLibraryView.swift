//
//  ExportLibraryView.swift
//  AI Music Studio
//

import SwiftUI

struct ExportLibraryView: View {
    @ObservedObject var model: MixerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.exports.isEmpty {
                    ContentUnavailableView(
                        "No Mixes Yet",
                        systemImage: "waveform",
                        description: Text("Bounced mixes will be saved here for sharing.")
                    )
                } else {
                    List(model.exports) { mix in
                        HStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Color.studioAccent)
                                .frame(width: 38, height: 38)
                                .background(Color.studioAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(mix.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                Text("\(studioTimeString(mix.duration))  ·  \(mix.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 4)

                            ShareLink(item: mix.url) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 38, height: 38)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Share \(mix.name)")
                        }
                        .padding(.vertical, 5)
                        .listRowBackground(Color.studioPanel)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.studioBackground)
                }
            }
            .background(Color.studioBackground)
            .navigationTitle("Mix Exports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { model.refreshExports() }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }
}
