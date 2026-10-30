import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: MediaLibrary
    @State private var searchText = ""
    @State private var selectedItem: MediaItem?
    @State private var showImporter = false
    @State private var showNotice = false
    @State private var notice = ""

    private var filteredItems: [MediaItem] {
        guard !searchText.isEmpty else { return library.items }
        return library.items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var audioCount: Int {
        library.items.filter { $0.kind == .audio }.count
    }

    var body: some View {
        Group {
            if filteredItems.isEmpty {
                emptyState
            } else {
                List {
                    if audioCount > 0 {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Image(systemName: "text.magnifyingglass")
                                        .font(.headline)
                                        .foregroundStyle(.cyan)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Lyrics for your library")
                                            .font(.headline)
                                        Text(library.lyricsSyncStatus ?? "Search all local audio tracks for lyrics")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }

                                if library.isSyncingLyrics {
                                    ProgressView()
                                        .tint(.cyan)
                                } else {
                                    Button {
                                        Task { await library.syncMissingLyrics() }
                                    } label: {
                                        Label("Sync Missing Lyrics", systemImage: "arrow.triangle.2.circlepath")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.cyan)
                                }
                            }
                            .padding(14)
                            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }

                    Section {
                        ForEach(filteredItems) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                MediaRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions {
                                Button(role: .destructive) {
                                    library.remove(item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("ON THIS IPHONE")
                            Spacer()
                            Text("\(filteredItems.count) FILE\(filteredItems.count == 1 ? "" : "S")")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("TmanVibez")
        .searchable(text: $searchText, prompt: "Songs and videos")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel("Import media")
            }
        }
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
        .alert("Library", isPresented: $showNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice)
        }
        .sheet(item: $selectedItem) { item in
            PlayerView(item: item)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your offline library is empty", systemImage: "waveform")
        } description: {
            Text(searchText.isEmpty
                 ? "Import files or choose a music folder to build your local library."
                 : "No matching files were found.")
        } actions: {
            Button("Import from Files") {
                showImporter = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct MediaRow: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .fill(item.kind == .audio
                          ? Color.cyan.opacity(0.16)
                          : Color.purple.opacity(0.18))
                    .frame(width: 54, height: 54)
                Image(systemName: item.kind == .audio ? "waveform" : "play.rectangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(item.kind == .audio ? .cyan : .purple)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if item.lyrics != nil {
                Image(systemName: "quote.bubble.fill")
                    .font(.caption)
                    .foregroundStyle(.cyan)
                    .accessibilityLabel("Lyrics saved")
            }

            Image(systemName: "play.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 19))
        .contentShape(RoundedRectangle(cornerRadius: 19))
    }
}
