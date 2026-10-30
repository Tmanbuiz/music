import SwiftUI
import UniformTypeIdentifiers

struct AddMediaView: View {
    @EnvironmentObject private var library: MediaLibrary
    @State private var showImporter = false
    @State private var showFolderImporter = false
    @State private var showDownloadSheet = false
    @State private var showNotice = false
    @State private var isSyncingFolder = false
    @State private var notice = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keep your media close.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Build a private offline library and find lyrics for your tracks.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                Button {
                    showFolderImporter = true
                } label: {
                    ActionCard(
                        icon: "folder.badge.gearshape",
                        title: "Sync a music folder",
                        subtitle: isSyncingFolder
                            ? "Scanning and syncing audio tracks…"
                            : "Choose a folder in Files to scan and copy its audio tracks",
                        tint: .cyan
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSyncingFolder)

                Button {
                    showImporter = true
                } label: {
                    ActionCard(
                        icon: "folder.badge.plus",
                        title: "Import selected files",
                        subtitle: "Add individual audio or video files already saved on your iPhone",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showDownloadSheet = true
                } label: {
                    ActionCard(
                        icon: "arrow.down.circle.fill",
                        title: "Download a media file",
                        subtitle: "Paste a direct HTTPS link to a file the source allows you to save",
                        tint: .purple
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Bulk lyric sync", systemImage: "text.magnifyingglass")
                        .font(.headline)
                    Text("After adding your songs, use Sync Missing Lyrics in the Library tab. The app checks tracks one at a time and saves matches for offline viewing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 8) {
                    Label("iPhone folder access", systemImage: "hand.raised")
                        .font(.headline)
                    Text("iOS asks you to choose the folder. TmanVibez copies supported tracks into its own library. Choose the folder again later to scan for new or changed files.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Direct downloads only", systemImage: "checkmark.shield")
                        .font(.headline)
                    Text("YouTube links cannot be downloaded from TmanVibez. Use YouTube's official offline feature when available. For other sources, use a direct media-file link only when you have permission to keep it; the app does not extract streams, bypass DRM, paywalls, or download restrictions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Add Media")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            do {
                let count = try library.importFiles(result.get())
                notice = count == 0
                    ? "No supported audio or video files were selected."
                    : "Added \(count) file\(count == 1 ? "" : "s") to your offline library."
            } catch {
                notice = error.localizedDescription
            }
            showNotice = true
        }
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let folderURLs):
                guard let folderURL = folderURLs.first else {
                    notice = "No folder was selected."
                    showNotice = true
                    return
                }
                isSyncingFolder = true
                Task {
                    do {
                        let report = try await library.syncAudioFolder(folderURL)
                        notice = "Folder scan complete: \(report.added) added, \(report.updated) updated, \(report.unchanged) unchanged."
                    } catch {
                        notice = error.localizedDescription
                    }
                    isSyncingFolder = false
                    showNotice = true
                }
            case .failure(let error):
                notice = error.localizedDescription
                showNotice = true
            }
        }
        .alert("TmanVibez", isPresented: $showNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice)
        }
        .sheet(isPresented: $showDownloadSheet) {
            DirectDownloadSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct ActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 54, height: 54)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }
}

private struct DirectDownloadSheet: View {
    @EnvironmentObject private var library: MediaLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var isDownloading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Paste a direct link to a supported audio or video file.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("https://example.com/video.mp4", text: $address)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))

                if isDownloading {
                    ProgressView("Downloading file…")
                        .tint(.cyan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    beginDownload()
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.to.line")
                        Text("Download to Library")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(isDownloading || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer(minLength: 0)
            }
            .padding(22)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Direct Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .disabled(isDownloading)
                }
            }
        }
    }

    private func beginDownload() {
        isDownloading = true
        errorMessage = nil

        Task {
            do {
                let result = try await MediaDownloader.fetchDirectFile(from: address)
                try library.saveDownloadedFile(
                    at: result.temporaryURL,
                    suggestedFileName: result.fileName,
                    mimeType: result.mimeType
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isDownloading = false
        }
    }
}
