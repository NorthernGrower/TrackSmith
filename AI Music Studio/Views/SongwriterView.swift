//
//  SongwriterView.swift
//  AI Music Studio
//

import SwiftUI
import UIKit

struct SongwriterView: View {
    @ObservedObject var model: MixerViewModel

    @StateObject private var writer = SongwriterViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var tab = WriterTab.lyrics
    @State private var genre = MusicGenre.pop
    @State private var topic = ""
    @State private var vocal = VocalStyle.marleneLead
    @State private var guitar = GuitarStyle.cleanElectric
    @State private var drumKit = DrumKit.studio808
    @State private var tempo = 118

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    introCard

                    Picker("Writer mode", selection: $tab) {
                        ForEach(WriterTab.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if tab == .lyrics {
                        lyricsPane
                    } else {
                        songPane
                    }
                }
                .padding(16)
                .padding(.bottom, 12)
            }
            .background(Color.studioBackground)
            .navigationTitle("AI Songwriter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear(perform: applyGenreDefaults)
        .onChange(of: genre) { _, _ in
            applyDefaultsForGenre()
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
    }

    // MARK: - Intro

    private var introCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.studioAccent)
                .frame(width: 40, height: 40)
                .background(Color.studioAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 5) {
                Text("Write it, then record it")
                    .font(.system(size: 15, weight: .semibold))
                Text("Write a lyric sheet, pick a genre, kit and guitar, and the studio builds a full session with Marlene on the lead vocal.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Lyrics

    private var lyricsPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Song Idea", systemImage: "text.quote")
            ideaField

            sectionTitle("Genre", systemImage: "music.note.list")
            genreChips

            Button {
                writer.writeLyrics(genre: genre, topic: topic)
            } label: {
                HStack(spacing: 8) {
                    if writer.isWritingLyrics {
                        ProgressView()
                            .tint(Color.black)
                    } else {
                        Image(systemName: writer.lyrics == nil ? "wand.and.stars" : "arrow.triangle.2.circlepath")
                    }
                    Text(writerActionTitle)
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(Color.black)
                .background(Color.studioAccent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(writer.isWritingLyrics)

            if let lyrics = writer.lyrics {
                lyricsCard(lyrics)
            } else {
                ContentUnavailableView(
                    "No Lyrics Yet",
                    systemImage: "text.alignleft",
                    description: Text("Describe an idea and tap Write Lyrics to draft a full song sheet.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
    }

    private var writerActionTitle: String {
        if writer.isWritingLyrics { return "Writing…" }
        return writer.lyrics == nil ? "Write Lyrics" : "Write Another Take"
    }

    private func lyricsCard(_ lyrics: LyricsDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lyrics.title)
                        .font(.system(size: 17, weight: .semibold))
                    Text("\(lyrics.genreTitle)  ·  \(lyrics.topic)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Button {
                    UIPasteboard.general.string = lyrics.plainText
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 34, height: 34)
                        .background(Color.studioPanelHighlight.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy lyrics")
            }

            ForEach(lyrics.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(Color.studioAccent)

                    ForEach(section.lines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    writer.writeLyrics(genre: genre, topic: topic)
                } label: {
                    Label("New Take", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary)
                .background(Color.studioPanelHighlight.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                .disabled(writer.isWritingLyrics)

                Button {
                    applyDefaultsForGenre()
                    tab = .song
                } label: {
                    Label("Use in Song", systemImage: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.black)
                .background(Color.studioAccent, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    // MARK: - Song

    private var songPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Song Idea", systemImage: "text.quote")
            ideaField

            sectionTitle("Genre", systemImage: "music.note.list")
            genreChips

            tempoCard

            sectionTitle("Drum Kit", systemImage: "metronome.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DrumKit.allCases) { kit in
                        optionChip(
                            title: kit.title,
                            subtitle: kit.subtitle,
                            systemImage: kit.systemImage,
                            isSelected: drumKit == kit
                        ) {
                            drumKit = kit
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            sectionTitle("Guitar", systemImage: "guitars")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GuitarStyle.allCases) { style in
                        optionChip(
                            title: style.title,
                            subtitle: style.subtitle,
                            systemImage: style.systemImage,
                            isSelected: guitar == style
                        ) {
                            guitar = style
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            sectionTitle("Vocals", systemImage: "music.mic")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VocalStyle.allCases) { style in
                        optionChip(
                            title: style.title,
                            subtitle: style.subtitle,
                            systemImage: style.systemImage,
                            isSelected: vocal == style
                        ) {
                            vocal = style
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            arrangementCard

            Button {
                let request = SongRequest(
                    genre: genre,
                    topic: topic,
                    vocal: vocal,
                    guitar: guitar,
                    drumKit: drumKit,
                    tempo: tempo
                )
                writer.createSong(request: request, model: model) {
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if writer.isComposingSong {
                        ProgressView()
                            .tint(Color.black)
                    } else {
                        Image(systemName: "waveform.badge.plus")
                    }
                    Text(writer.isComposingSong ? "Building Session" : "Create Session")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(Color.black)
                .background(Color.studioAccent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(writer.isComposingSong)

            Text("Tracks are fully editable: open the piano roll to change notes, or the mixer to rebalance the song.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
    }

    private var tempoCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TEMPO")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
                Text("\(tempo) BPM")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
            }

            Spacer(minLength: 4)

            Stepper("Tempo") {
                tempo = min(190, tempo + 1)
            } onDecrement: {
                tempo = max(70, tempo - 1)
            }
            .labelsHidden()
            .tint(Color.studioAccent)
        }
        .padding(14)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
    }

    private var arrangementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT GETS BUILT")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(.secondary)

            arrangementRow(
                title: "Drums",
                detail: "\(drumKit.title) · 16 bars",
                systemImage: "metronome.fill"
            )
            arrangementRow(title: "Bass", detail: "Follows the \(genre.title) progression", systemImage: "waveform")
            if genre.keysVoice != nil {
                arrangementRow(title: "Keys", detail: "Sustained chords under the hook", systemImage: "pianokeys")
            }
            if let voice = guitar.voice {
                arrangementRow(
                    title: guitar.trackName,
                    detail: voice == .acousticGuitar ? "Strummed acoustic" : "Electric strums",
                    systemImage: voice.systemImage
                )
            }
            if vocal.includesVocal {
                arrangementRow(
                    title: vocal == .marleneDouble ? "Marlene Lead + Harmony" : "Marlene Lead",
                    detail: "Female vocal · \(vocal.subtitle.lowercased())",
                    systemImage: "music.mic"
                )
            }

            if let lyrics = writer.lyrics {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                VStack(alignment: .leading, spacing: 3) {
                    Text("LYRICS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.9)
                        .foregroundStyle(.secondary)
                    Text("\(lyrics.title) — \(lyrics.hook)")
                        .font(.system(size: 12, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func arrangementRow(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.studioAccent)
                .frame(width: 26, height: 26)
                .background(Color.studioAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Shared pieces

    private var ideaField: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.studioAccent)

            TextField("A late-night drive home", text: $topic)
                .font(.system(size: 14))
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color.studioPanel, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var genreChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MusicGenre.allCases) { item in
                    let isSelected = item == genre
                    Button {
                        genre = item
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Image(systemName: item.systemImage)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(item.title)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Text(item.tagline)
                                .font(.system(size: 9))
                                .foregroundStyle(isSelected ? Color.black.opacity(0.65) : Color.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(minWidth: 118, alignment: .leading)
                        .foregroundStyle(isSelected ? Color.black : Color.primary)
                        .background(
                            isSelected ? Color.studioAccent : Color.studioPanel,
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.studioAccent)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(.secondary)
        }
    }

    private func optionChip(
        title: String,
        subtitle: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.65) : Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minWidth: 132, maxWidth: 170, minHeight: 54, alignment: .leading)
            .foregroundStyle(isSelected ? Color.black : Color.primary)
            .background(
                isSelected ? Color.studioAccent : Color.studioPanel,
                in: RoundedRectangle(cornerRadius: 11)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Defaults

    private func applyGenreDefaults() {
        tempo = genre.defaultTempo
        drumKit = genre.defaultKit
        guitar = genre.defaultGuitar
    }

    private func applyDefaultsForGenre() {
        tempo = genre.defaultTempo
        drumKit = genre.defaultKit
        guitar = genre.defaultGuitar
    }
}

private enum WriterTab: String, CaseIterable, Identifiable {
    case lyrics
    case song

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lyrics: return "Lyrics"
        case .song: return "Song"
        }
    }
}
