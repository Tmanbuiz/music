import SwiftUI
import AVKit
import AVFoundation
import Combine
import MediaPlayer

struct PlayerView: View {
    let itemID: UUID

    @EnvironmentObject private var library: MediaLibrary
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback: PlaybackController
    @State private var showLyricsSearch = false

    init(item: MediaItem) {
        itemID = item.id
        _playback = StateObject(wrappedValue: PlaybackController(item: item))
    }

    private var item: MediaItem? {
        library.items.first(where: { $0.id == playback.currentItemID })
            ?? library.items.first(where: { $0.id == itemID })
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
        .onAppear {
            playback.prepareQueue(library.items, startingAt: itemID)
            playback.play()
        }
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

            HStack {
                Button {
                    playback.toggleShuffle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(playback.isShuffleEnabled ? Color.cyan : Color.secondary)
                }
                .accessibilityLabel(playback.isShuffleEnabled ? "Turn shuffle off" : "Turn shuffle on")

                Spacer()

                Button {
                    playback.previousTrack()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 22))
                }
                .disabled(!playback.canSkipPrevious)
                .accessibilityLabel("Previous track")

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
                    playback.nextTrack()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 22))
                }
                .disabled(!playback.canSkipNext)
                .accessibilityLabel("Next track")

                Spacer()

                Button {
                    playback.cycleRepeatMode()
                } label: {
                    Image(systemName: playback.repeatMode.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(playback.repeatMode == .off ? Color.secondary : Color.cyan)
                }
                .accessibilityLabel(playback.repeatMode.accessibilityLabel)
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

    @Published private(set) var currentItemID: UUID
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isShuffleEnabled = false
    @Published private(set) var repeatMode: RepeatMode = .off

    private var timeObserver: Any?
    private var completionObserver: NSObjectProtocol?
    private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
    private var originalQueue: [MediaItem] = []
    private var playbackQueue: [MediaItem] = []
    private var currentIndex = 0

    var canSkipPrevious: Bool {
        currentTime > 3 || currentIndex > 0 || repeatMode == .all
    }

    var canSkipNext: Bool {
        currentIndex + 1 < playbackQueue.count || repeatMode == .all
    }

    init(item: MediaItem) {
        currentItemID = item.id
        player = AVPlayer(url: item.localURL)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.35, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let value = time.seconds
            Task { @MainActor [weak self] in
                self?.updatePlaybackState(at: value)
            }
        }

        completionObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let finishedItem = notification.object as? AVPlayerItem else { return }
            Task { @MainActor [weak self] in
                self?.handlePlaybackEnded(finishedItem)
            }
        }

        configureRemoteCommands()
        updateNowPlayingInfo()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let completionObserver {
            NotificationCenter.default.removeObserver(completionObserver)
        }
        for (command, target) in remoteCommandTargets {
            command.removeTarget(target)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func prepareQueue(_ items: [MediaItem], startingAt itemID: UUID) {
        guard playbackQueue.isEmpty else { return }
        guard let selectedItem = items.first(where: { $0.id == itemID }) else { return }
        originalQueue = items.filter { $0.kind.rawValue == selectedItem.kind.rawValue }
        playbackQueue = originalQueue
        guard let startingIndex = playbackQueue.firstIndex(where: { $0.id == itemID }) else { return }
        currentIndex = startingIndex
        loadCurrentItem(autoplay: false)
    }

    func play() {
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        let bounded = min(max(seconds, 0), max(duration, 0))
        player.seek(to: CMTime(seconds: bounded, preferredTimescale: 600))
        currentTime = bounded
        updateNowPlayingInfo()
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func toggleShuffle() {
        guard let currentItem = currentTrack else { return }
        isShuffleEnabled.toggle()

        if isShuffleEnabled {
            playbackQueue = [currentItem] + originalQueue
                .filter { $0.id != currentItem.id }
                .shuffled()
            currentIndex = 0
        } else {
            playbackQueue = originalQueue
            currentIndex = playbackQueue.firstIndex(where: { $0.id == currentItem.id }) ?? 0
        }
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next
        updateNowPlayingInfo()
    }

    func previousTrack() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }

        if currentIndex > 0 {
            currentIndex -= 1
        } else if repeatMode == .all, !playbackQueue.isEmpty {
            currentIndex = playbackQueue.count - 1
        } else {
            return
        }
        loadCurrentItem(autoplay: true)
    }

    func nextTrack() {
        guard !playbackQueue.isEmpty else { return }
        if currentIndex + 1 < playbackQueue.count {
            currentIndex += 1
        } else if repeatMode == .all {
            currentIndex = 0
        } else {
            return
        }
        loadCurrentItem(autoplay: true)
    }

    private var currentTrack: MediaItem? {
        guard playbackQueue.indices.contains(currentIndex) else { return nil }
        return playbackQueue[currentIndex]
    }

    private func loadCurrentItem(autoplay: Bool) {
        guard let item = currentTrack else { return }
        currentItemID = item.id
        currentTime = 0
        duration = 0
        isPlaying = false
        player.replaceCurrentItem(with: AVPlayerItem(url: item.localURL))
        updateNowPlayingInfo()
        if autoplay { play() }
    }

    private func handlePlaybackEnded(_ finishedItem: AVPlayerItem) {
        guard finishedItem === player.currentItem else { return }

        if repeatMode == .one {
            player.seek(to: .zero) { [weak self] completed in
                guard completed else { return }
                Task { @MainActor [weak self] in self?.play() }
            }
        } else if canSkipNext {
            nextTrack()
        } else {
            isPlaying = false
            currentTime = duration
            updateNowPlayingInfo()
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand) { [weak self] _ in
            guard self != nil else { return .commandFailed }
            Task { @MainActor [weak self] in self?.play() }
            return .success
        }
        register(center.pauseCommand) { [weak self] _ in
            guard self != nil else { return .commandFailed }
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }
        register(center.togglePlayPauseCommand) { [weak self] _ in
            guard self != nil else { return .commandFailed }
            Task { @MainActor [weak self] in self?.togglePlayback() }
            return .success
        }
        register(center.nextTrackCommand) { [weak self] _ in
            guard let self, self.canSkipNext else { return .noSuchContent }
            Task { @MainActor [weak self] in self?.nextTrack() }
            return .success
        }
        register(center.previousTrackCommand) { [weak self] _ in
            guard let self, self.canSkipPrevious else { return .noSuchContent }
            Task { @MainActor [weak self] in self?.previousTrack() }
            return .success
        }
        register(center.changePlaybackPositionCommand) { [weak self] event in
            guard let self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor [weak self] in self?.seek(to: positionEvent.positionTime) }
            return .success
        }
    }

    private func register(
        _ command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        let target = command.addTarget(handler: handler)
        remoteCommandTargets.append((command, target))
    }

    private func updateNowPlayingInfo() {
        guard let item = currentTrack ?? originalQueue.first(where: { $0.id == currentItemID }) else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updatePlaybackState(at value: Double) {
        currentTime = value.isFinite ? value : 0

        if let currentItem = player.currentItem {
            let total = currentItem.duration.seconds
            if total.isFinite, total > 0 {
                let durationChanged = duration != total
                duration = total
                if durationChanged { updateNowPlayingInfo() }
            }
        }
        isPlaying = player.timeControlStatus == .playing
    }
}

enum RepeatMode: Equatable {
    case off
    case all
    case one

    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    var systemImage: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .off: "Repeat off"
        case .all: "Repeat all tracks"
        case .one: "Repeat this track"
        }
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
