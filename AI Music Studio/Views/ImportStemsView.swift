import SwiftUI
import UniformTypeIdentifiers

private struct ImportStemRow: Identifiable, Sendable {
    let trackName: String
    let fileName: String
    let duration: TimeInterval
    let format: String

    var id: String { fileName }

    var displayName: String {
        let trimmed = trackName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
            : trimmed
    }

    var formatLabel: String {
        let trimmed = format.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? URL(fileURLWithPath: fileName).pathExtension.uppercased()
            : trimmed.uppercased()
    }
}

private struct ImportStemManifest: Sendable {
    let sessionName: String
    let tempoBPM: Int
    let stems: [ImportStemRow]
}

struct ImportStemsView: View {
    @ObservedObject var model: MixerViewModel
    let archiveURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var manifest: ImportStemManifest?
    @State private var manifestError: String?
    @State private var selectedFileNames = Set<String>()
    @State private var isLoading = true
    @State private var isImporting = false
    @State private var importError: String?

    private var selectedCount: Int {
        selectedFileNames.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 11) {
                    Text(archiveURL.lastPathComponent)
                        .font(.system(size: 21, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                        .padding(.top, 7)

                    Text("Choose the stems to add to this session.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 13)

                    if let manifest {
                        sessionCard(manifest)
                        selectionBar(stemCount: manifest.stems.count)

                        VStack(spacing: 9) {
                            ForEach(manifest.stems) { stem in
                                stemRow(stem)
                            }
                        }
                        .padding(.top, 1)
                    } else if isLoading {
                        ProgressView("Reading stem manifest…")
                            .tint(Color.studioAccent)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ContentUnavailableView(
                            "Manifest Unavailable",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(manifestError ?? "This ZIP does not contain a readable stem manifest.")
                        )
                        .padding(.vertical, 32)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.studioBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if manifest != nil {
                importFooter
            }
        }
        .task {
            await loadManifest()
        }
        .alert("Import Failed", isPresented: importErrorBinding) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "The selected stems could not be imported.")
        }
        .preferredColorScheme(.dark)
        .tint(Color.studioAccent)
        .interactiveDismissDisabled(isImporting)
    }

    private var header: some View {
        ZStack {
            Text("Import Stems")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 54, height: 54)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()
                Color.clear.frame(width: 54, height: 54)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private func sessionCard(_ manifest: ImportStemManifest) -> some View {
        HStack(spacing: 17) {
            Image(systemName: "waveform")
                .font(.system(size: 35, weight: .medium))
                .foregroundStyle(Color.studioAccent)
                .frame(width: 82, height: 82)
                .background(Color.studioAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 6) {
                Text(manifest.sessionName.isEmpty ? "Stem Session" : manifest.sessionName)
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(2)
                Text("\(manifest.tempoBPM) BPM")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 21))
        .overlay(RoundedRectangle(cornerRadius: 21).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func selectionBar(stemCount: Int) -> some View {
        HStack {
            Button {
                selectedFileNames = Set(manifest?.stems.map(\.fileName) ?? [])
            } label: {
                Text("Select All")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.studioAccent)
                    .frame(minWidth: 142, minHeight: 44)
                    .padding(.horizontal, 8)
                    .background(Color.studioAccent.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(Color.studioAccent, lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(stemCount) \(stemCount == 1 ? "stem" : "stems")")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(13)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func stemRow(_ stem: ImportStemRow) -> some View {
        let isSelected = selectedFileNames.contains(stem.fileName)

        return Button {
            if isSelected {
                selectedFileNames.remove(stem.fileName)
            } else {
                selectedFileNames.insert(stem.fileName)
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "waveform")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(Color.studioAccent)
                    .frame(width: 66, height: 66)
                    .background(Color.studioAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 6) {
                    Text(stem.displayName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(durationText(stem.duration))  ·  \(stem.formatLabel.isEmpty ? "AUDIO" : stem.formatLabel)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                ZStack {
                    Circle()
                        .fill(isSelected ? Color.studioAccent : Color.clear)
                    Circle()
                        .stroke(isSelected ? Color.studioAccent : Color.white.opacity(0.42), lineWidth: 1.5)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.88))
                    }
                }
                .frame(width: 31, height: 31)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 91, alignment: .leading)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 21))
            .overlay(RoundedRectangle(cornerRadius: 21).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 21))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stem.displayName), \(durationText(stem.duration)), \(stem.formatLabel), \(isSelected ? "selected" : "not selected")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var importFooter: some View {
        VStack(spacing: 12) {
            Button(action: importSelectedStems) {
                HStack(spacing: 10) {
                    if isImporting {
                        ProgressView()
                            .tint(Color.black)
                    }
                    Text(importButtonTitle)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.78, blue: 0.26), Color(red: 0.96, green: 0.58, blue: 0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                .shadow(color: Color.studioAccent.opacity(0.24), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(selectedCount == 0 || isImporting)
            .opacity(selectedCount == 0 || isImporting ? 0.58 : 1)

            Text("New tracks start at the beginning of the session.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 9)
        .background(Color.studioBackground.opacity(0.98))
    }

    private var importButtonTitle: String {
        guard !isImporting else { return "Importing Stems…" }
        return "Import \(selectedCount) \(selectedCount == 1 ? "Stem" : "Stems")"
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func loadManifest() async {
        isLoading = true
        let scoped = archiveURL.startAccessingSecurityScopedResource()
        defer { if scoped { archiveURL.stopAccessingSecurityScopedResource() } }

        do {
            let loaded = try await Task.detached(priority: .userInitiated) { () throws -> ImportStemManifest in
                let archiveManifest = try StemArchive.readManifest(from: archiveURL)
                guard !archiveManifest.stems.isEmpty else {
                    throw StemArchiveError.manifestContainsNoStems
                }

                var fileNames = Set<String>()
                let stems = try archiveManifest.stems.map { stem -> ImportStemRow in
                    let fileName = stem.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !fileName.isEmpty else { throw StemArchiveError.invalidArchive }
                    guard fileNames.insert(fileName).inserted else {
                        throw StemArchiveError.duplicateStemEntry(fileName)
                    }
                    return ImportStemRow(
                        trackName: stem.trackName,
                        fileName: fileName,
                        duration: stem.duration,
                        format: stem.format
                    )
                }

                return ImportStemManifest(
                    sessionName: archiveManifest.sessionName,
                    tempoBPM: archiveManifest.sessionTempoBPM,
                    stems: stems
                )
            }.value

            manifest = loaded
            selectedFileNames = Set(loaded.stems.map(\.fileName))
            manifestError = nil
        } catch {
            manifest = nil
            manifestError = (error as? LocalizedError)?.errorDescription
                ?? "This ZIP does not contain a readable stem manifest."
        }
        isLoading = false
    }

    private func importSelectedStems() {
        guard let manifest else { return }
        let selected = manifest.stems
            .filter { selectedFileNames.contains($0.fileName) }
            .map {
                StemArchiveManifest.Stem(
                    trackName: $0.trackName,
                    fileName: $0.fileName,
                    duration: $0.duration,
                    format: $0.format
                )
            }
        guard !selected.isEmpty else {
            importError = StemArchiveError.noStemsSelected.localizedDescription
            return
        }

        isImporting = true
        Task { @MainActor in
            do {
                try await model.importStems(from: archiveURL, stems: selected)
                dismiss()
            } catch {
                importError = (error as? LocalizedError)?.errorDescription
                    ?? "The selected stems could not be imported. No stems were imported."
            }
            isImporting = false
        }
    }
}



struct StemArchiveImportCoordinator: View {
    @ObservedObject var model: MixerViewModel
    @Binding var isImporterPresented: Bool

    @State private var archiveURL: URL?
    @State private var isImportScreenPresented = false

    var body: some View {
        Color.clear
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [UTType(filenameExtension: "zip") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let selectedURL = urls.first else { return }
                archiveURL = selectedURL
                isImportScreenPresented = true
            }
            .fullScreenCover(isPresented: $isImportScreenPresented, onDismiss: {
                archiveURL = nil
            }) {
                if let archiveURL {
                    ImportStemsView(model: model, archiveURL: archiveURL)
                } else {
                    Color.clear
                }
            }
    }
}
