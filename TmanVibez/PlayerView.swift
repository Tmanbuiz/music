import SwiftUI
import AVKit
import AVFoundation
import Combine

struct PlayerView: View {
    let itemID: UUID

    @EnvironmentObject private var library: MediaLibrary
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback: PlaybackController
    @State private var showLyricsSearch = false

    init(item: MediaItem) {
        itemID = item.id
        _playback = StateObject(wrappedValue: PlaybackController(url: item.localURL))
    }

    private var item: MediaItem? {
        library.items.first(where: { $0.id == itemID })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let item {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if item.kind == .video {
                                VideoPlayer(player: playback.player)
                                    .frame(height: 260)
                                    .clipShape(RoundedRectangle(cornerRadius: 22))
                            } else {
                                audioPlayerCard
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.title2.bold())
                                    .lineLimit(2)
                                Text(item.artist.isEmpty ? item.fileExtension.uppercased() : item.artist)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            lyricsPanel(item)
                        }
                        .padding(20)
                    }
                    .background(Color.black.ignoresSafeArea())
                    .navigationTitle("Now Playing")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                playback.pause()
                                dismiss()
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("File unavailable", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .onAppear { playback.play() }
        .onDisappear { playback.pause() }
        .sheet(isPresented: $showLyricsSearch) {
            if let item {
                LyricsSearchSheet(item: item) { lyrics in
                    library.attachLyrics(lyrics, to: itemID)
                }
            }
        }
    }

    private var audioPlayerCard: some View {
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.22), Color.blue.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "waveform")
                    .font(.system(size: 68, weight: .light))
                    .symbolEffect(.pulse, isActive: playback.isPlaying)
                    .foregroundStyle(.cyan)
            }
            .frame(height: 240)

            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { playback.currentTime },
                        set: { playback.seek(to: $0) }
                    ),
                    in: 0...max(playback.duration, 0.1)
                )
                HStack {
                    Text(Self.time(playback.currentTime))
                    Spacer()
                    Text(Self.time(playback.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 36) {
                Button {
                    playback.skip(by: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 25))
                }

                Button {
                    playback.togglePlayback()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 25, weight: .bold))
                        .frame(width: 68, height: 68)
                        .background(.cyan, in: Circle())
                        .foregroundStyle(.black)
                }

                Button {
                    playback.skip(by: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 25))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 26))
    }

    @ViewBuilder
    private func lyricsPanel(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lyrics")
                        .font(.title3.bold())
                    Text(item.lyrics == nil ? "Find lyrics and save them for offline use" : "Saved on this iPhone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showLyricsSearch = true
                } label: {
                    Label(item.lyrics == nil ? "Find" : "Change", systemImage: "text.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
            }

            if let lyrics = item.lyrics {
                LyricsPanel(lyrics: lyrics, currentTime: playback.currentTime)
                    .frame(maxHeight: 320)
            } else {
                Text("Search by track title and artist while online. The selected lyrics are stored with this file so you can view them offline.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

@MainActor
final class PlaybackController: ObservableObject {
    let player: AVPlayer

    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false

    private var timeObserver: Any?

    init(url: URL) {
        player = AVPlayer(url: url)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.35, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let value = time.seconds
            self.currentTime = value.isFinite ? value : 0

            if let currentItem = self.player.currentItem {
                let total = currentItem.duration.seconds
                if total.isFinite, total > 0 {
                    self.duration = total
                }
            }
            self.isPlaying = self.player.timeControlStatus == .playing
        }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        let bounded = min(max(seconds, 0), max(duration, 0))
        player.seek(to: CMTime(seconds: bounded, preferredTimescale: 600))
        currentTime = bounded
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }
}

private struct LyricsPanel: View {
    let lyrics: String
    let currentTime: Double

    private var lines: [LyricLine] {
        LyricLine.parse(lyrics)
    }

    private var activeLineID: Int? {
        lines.last(where: { line in
            guard let time = line.time else { return false }
            return time <= currentTime
        })?.id
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(lines) { line in
                    Text(line.text)
                        .font(.system(size: line.id == activeLineID ? 19 : 16, weight: line.id == activeLineID ? .semibold : .regular))
                        .foregroundStyle(line.id == activeLineID ? .cyan : .primary.opacity(0.68))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
            }
            .padding(16)
        }
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct LyricsSearchSheet: View {
    let item: MediaItem
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var trackName: String
    @State private var artistName: String
    @State private var results: [LyricsRecord] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    init(item: MediaItem, onSelect: @escaping (String) -> Void) {
        self.item = item
        self.onSelect = onSelect
        _trackName = State(initialValue: item.title)
        _artistName = State(initialValue: item.artist)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Track details") {
                    TextField("Song title", text: $trackName)
                    TextField("Artist", text: $artistName)
                }

                Section {
                    Button {
                        search()
                    } label: {
                        HStack {
                            Spacer()
                            if isSearching {
                                ProgressView()
                            } else {
                                Label("Search lyrics", systemImage: "magnifyingglass")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSearching || trackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if !results.isEmpty {
                    Section("Choose a match") {
                        ForEach(results) { result in
                            Button {
                                guard let lyrics = result.lyricsToSave else { return }
                                onSelect(lyrics)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(result.trackName ?? "Unknown track")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(result.syncLabel)
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.cyan)
                                    }
                                    Text([result.artistName, result.albumName].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let preview = result.lyricsToSave {
                                        Text(preview.components(separatedBy: .newlines).first ?? "")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 5)
                            }
                            .disabled(result.lyricsToSave == nil)
                        }
                    }
                }

                Section {
                    Text("Search uses LRCLIB. Only the title and artist entered above are sent to find a match.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Find Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func search() {
        isSearching = true
        errorMessage = nil
        results = []

        Task {
            do {
                results = try await LyricsService.search(track: trackName, artist: artistName)
                if results.isEmpty {
                    errorMessage = "No lyrics matched. Try adjusting the title or artist."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }
}
