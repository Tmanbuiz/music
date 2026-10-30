import Foundation
import Combine

@MainActor
final class MediaLibrary: ObservableObject {
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var isSyncingLyrics = false
    @Published private(set) var lyricsSyncStatus: String?

    private let fileManager = FileManager.default
    private let indexURL: URL

    nonisolated static var mediaDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TmanVibezFiles", isDirectory: true)
    }

    init() {
        indexURL = Self.mediaDirectory.appendingPathComponent("library.json")
        try? fileManager.createDirectory(at: Self.mediaDirectory, withIntermediateDirectories: true)
        load()
    }

    func importFiles(_ urls: [URL]) throws -> Int {
        try fileManager.createDirectory(at: Self.mediaDirectory, withIntermediateDirectories: true)
        var imported: [MediaItem] = []

        for sourceURL in urls {
            let startedAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if startedAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let fileExtension = sourceURL.pathExtension.lowercased()
            guard let kind = SupportedMedia.kind(for: fileExtension) else { continue }

            let destinationName = uniqueFileName(for: sourceURL.lastPathComponent)
            let destinationURL = Self.mediaDirectory.appendingPathComponent(destinationName)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            imported.append(makeItem(fileName: destinationName, kind: kind, sourceURL: sourceURL))
        }

        items.insert(contentsOf: imported, at: 0)
        persist()
        return imported.count
    }

    func syncAudioFolder(_ folderURL: URL) async throws -> FolderSyncReport {
        let startedAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        let existingItems = items
        let destinationDirectory = Self.mediaDirectory
        let result = try await Task.detached(priority: .utility) {
            try FolderSyncWorker.scan(
                folderURL: folderURL,
                destinationDirectory: destinationDirectory,
                existingItems: existingItems
            )
        }.value

        for updatedItem in result.updated {
            if let index = items.firstIndex(where: { $0.id == updatedItem.id }) {
                items[index] = updatedItem
            }
        }
        items.insert(contentsOf: result.added, at: 0)
        persist()
        return FolderSyncReport(
            added: result.added.count,
            updated: result.updated.count,
            unchanged: result.unchanged
        )
    }

    func saveDownloadedFile(
        at temporaryURL: URL,
        suggestedFileName: String,
        mimeType: String?
    ) throws {
        let fileExtension = URL(fileURLWithPath: suggestedFileName).pathExtension.lowercased()
        guard let kind = SupportedMedia.kind(for: fileExtension) else {
            throw MediaLibraryError.unsupportedFile
        }

        if let mimeType = mimeType?.lowercased(),
           mimeType.hasPrefix("text/") || mimeType == "application/json" {
            throw MediaLibraryError.notMediaFile
        }

        try fileManager.createDirectory(at: Self.mediaDirectory, withIntermediateDirectories: true)
        let destinationName = uniqueFileName(for: suggestedFileName)
        let destinationURL = Self.mediaDirectory.appendingPathComponent(destinationName)
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        items.insert(makeItem(fileName: destinationName, kind: kind, sourceURL: destinationURL), at: 0)
        persist()
    }

    func attachLyrics(_ lyrics: String, to itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].lyrics = lyrics
        persist()
    }

    func remove(_ item: MediaItem) {
        try? fileManager.removeItem(at: item.localURL)
        items.removeAll { $0.id == item.id }
        persist()
    }

    func syncMissingLyrics() async {
        guard !isSyncingLyrics else { return }
        let candidates = items.filter { $0.kind == .audio && $0.lyrics == nil }
        guard !candidates.isEmpty else {
            lyricsSyncStatus = "Every audio track already has saved lyrics."
            return
        }

        isSyncingLyrics = true
        lyricsSyncStatus = "Starting lyric sync…"
        var found = 0
        var checked = 0

        for (offset, item) in candidates.enumerated() {
            if Task.isCancelled { break }
            checked = offset + 1
            lyricsSyncStatus = "Searching lyrics for \(checked) of \(candidates.count)…"

            let metadata = AudioMetadata.read(from: item.localURL)
            let track = metadata.title ?? item.title
            let artist = metadata.artist ?? item.artist

            do {
                let results = try await LyricsService.search(track: track, artist: artist)
                let normalizedTrack = Self.normalized(track)
                let normalizedArtist = Self.normalized(artist)
                let match = results.first(where: {
                    guard $0.lyricsToSave != nil else { return false }
                    let sameTrack = Self.normalized($0.trackName ?? "") == normalizedTrack
                    let sameArtist = normalizedArtist.isEmpty
                        || Self.normalized($0.artistName ?? "") == normalizedArtist
                    return sameTrack && sameArtist
                })

                if let lyrics = match?.lyricsToSave {
                    attachLyrics(lyrics, to: item.id)
                    if items.first(where: { $0.id == item.id })?.artist.isEmpty == true,
                       let matchedArtist = match?.artistName {
                        setArtist(matchedArtist, for: item.id)
                    }
                    found += 1
                }
            } catch {
                // Continue through the library; individual misses are reflected in the final count.
            }

            if offset < candidates.count - 1 {
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }

        isSyncingLyrics = false
        lyricsSyncStatus = Task.isCancelled
            ? "Lyric sync stopped. Found lyrics for \(found) track\(found == 1 ? "" : "s")."
            : "Checked \(checked) track\(checked == 1 ? "" : "s"); found lyrics for \(found)."
    }

    private func setArtist(_ artist: String, for itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].artist = artist
        persist()
    }

    private func makeItem(fileName: String, kind: MediaKind, sourceURL: URL) -> MediaItem {
        let metadata = kind == .audio ? AudioMetadata.read(from: sourceURL) : AudioMetadata(title: nil, artist: nil)
        return MediaItem(
            id: UUID(),
            fileName: fileName,
            title: metadata.title ?? Self.title(from: fileName),
            artist: metadata.artist ?? "",
            kind: kind,
            addedAt: Date(),
            lyrics: nil,
            sourceKey: nil,
            sourceFileSize: nil,
            sourceModifiedAt: nil
        )
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let savedItems = try? JSONDecoder().decode([MediaItem].self, from: data) else {
            items = []
            return
        }
        items = savedItems.filter { fileManager.fileExists(atPath: $0.localURL.path) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func uniqueFileName(for original: String) -> String {
        let ext = URL(fileURLWithPath: original).pathExtension
        let base = URL(fileURLWithPath: original).deletingPathExtension().lastPathComponent
        var candidate = original
        var suffix = 2

        while fileManager.fileExists(atPath: Self.mediaDirectory.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            suffix += 1
        }
        return candidate
    }

    private static func title(from fileName: String) -> String {
        URL(fileURLWithPath: fileName)
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private enum FolderSyncWorker {
    static func scan(
        folderURL: URL,
        destinationDirectory: URL,
        existingItems: [MediaItem]
    ) throws -> (added: [MediaItem], updated: [MediaItem], unchanged: Int) {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let standardizedFolder = folderURL.standardizedFileURL
        let folderKey = standardizedFolder.path
        guard let enumerator = fileManager.enumerator(
            at: standardizedFolder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw MediaLibraryError.folderUnavailable
        }

        var added: [MediaItem] = []
        var updated: [MediaItem] = []
        var unchanged = 0
        let existingBySource = Dictionary(
            existingItems.compactMap { item in item.sourceKey.map { ($0, item) } },
            uniquingKeysWith: { first, _ in first }
        )
        var usedNames = Set(existingItems.map(\.fileName))

        for case let sourceURL as URL in enumerator {
            let fileExtension = sourceURL.pathExtension.lowercased()
            guard SupportedMedia.audioExtensions.contains(fileExtension) else { continue }

            let values = try? sourceURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            )
            guard values?.isRegularFile == true else { continue }

            let relativePath = String(sourceURL.standardizedFileURL.path.dropFirst(folderKey.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let sourceKey = folderKey + "|" + relativePath
            let fileSize = Int64(values?.fileSize ?? 0)
            let modifiedAt = values?.contentModificationDate ?? .distantPast

            if let existing = existingBySource[sourceKey] {
                if existing.sourceFileSize == fileSize && existing.sourceModifiedAt == modifiedAt {
                    unchanged += 1
                    continue
                }

                let destinationURL = destinationDirectory.appendingPathComponent(existing.fileName)
                let temporaryURL = destinationDirectory.appendingPathComponent(
                    ".sync-\(UUID().uuidString)-\(existing.fileName)"
                )
                let backupURL = destinationDirectory.appendingPathComponent(".backup-\(UUID().uuidString)")
                do {
                    try fileManager.copyItem(at: sourceURL, to: temporaryURL)
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.moveItem(at: destinationURL, to: backupURL)
                    }
                    try fileManager.moveItem(at: temporaryURL, to: destinationURL)
                    try? fileManager.removeItem(at: backupURL)
                } catch {
                    try? fileManager.removeItem(at: temporaryURL)
                    if fileManager.fileExists(atPath: backupURL.path)
                        && !fileManager.fileExists(atPath: destinationURL.path) {
                        try? fileManager.moveItem(at: backupURL, to: destinationURL)
                    }
                    throw error
                }

                let metadata = AudioMetadata.read(from: sourceURL)
                var refreshed = existing
                refreshed.title = metadata.title ?? title(from: sourceURL.lastPathComponent)
                refreshed.artist = metadata.artist ?? ""
                refreshed.sourceFileSize = fileSize
                refreshed.sourceModifiedAt = modifiedAt
                refreshed.lyrics = nil
                updated.append(refreshed)
            } else {
                let destinationName = uniqueFileName(
                    sourceURL.lastPathComponent,
                    usedNames: &usedNames,
                    destinationDirectory: destinationDirectory
                )
                try fileManager.copyItem(
                    at: sourceURL,
                    to: destinationDirectory.appendingPathComponent(destinationName)
                )
                let metadata = AudioMetadata.read(from: sourceURL)
                let item = MediaItem(
                    id: UUID(),
                    fileName: destinationName,
                    title: metadata.title ?? title(from: sourceURL.lastPathComponent),
                    artist: metadata.artist ?? "",
                    kind: .audio,
                    addedAt: Date(),
                    lyrics: nil,
                    sourceKey: sourceKey,
                    sourceFileSize: fileSize,
                    sourceModifiedAt: modifiedAt
                )
                added.append(item)
            }
        }

        return (added, updated, unchanged)
    }

    private static func uniqueFileName(
        _ original: String,
        usedNames: inout Set<String>,
        destinationDirectory: URL
    ) -> String {
        let ext = URL(fileURLWithPath: original).pathExtension
        let base = URL(fileURLWithPath: original).deletingPathExtension().lastPathComponent
        var candidate = original
        var suffix = 2
        while usedNames.contains(candidate)
            || FileManager.default.fileExists(atPath: destinationDirectory.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            suffix += 1
        }
        usedNames.insert(candidate)
        return candidate
    }

    private static func title(from fileName: String) -> String {
        URL(fileURLWithPath: fileName)
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}

enum MediaLibraryError: LocalizedError, Sendable {
    case unsupportedFile
    case notMediaFile
    case folderUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "This file type is not supported. Choose an MP3, M4A, AAC, WAV, AIFF, CAF, FLAC, MP4, MOV, or M4V file."
        case .notMediaFile:
            return "The link did not return an audio or video file."
        case .folderUnavailable:
            return "The selected folder could not be opened."
        }
    }
}
