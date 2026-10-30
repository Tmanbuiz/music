import Foundation
import AVFoundation

enum MediaKind: String, Codable, Sendable {
    case audio
    case video
}

enum SupportedMedia {
    static let fileExtensions: Set<String> = [
        "mp4", "m4v", "mov",
        "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"
    ]

    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"
    ]

    static func kind(for fileExtension: String) -> MediaKind? {
        switch fileExtension.lowercased() {
        case "mp4", "m4v", "mov":
            return .video
        case "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac":
            return .audio
        default:
            return nil
        }
    }
}

struct MediaItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var fileName: String
    var title: String
    var artist: String
    var kind: MediaKind
    var addedAt: Date
    var lyrics: String?
    var sourceKey: String?
    var sourceFileSize: Int64?
    var sourceModifiedAt: Date?

    var fileExtension: String {
        URL(fileURLWithPath: fileName).pathExtension.lowercased()
    }

    var localURL: URL {
        MediaLibrary.mediaDirectory.appendingPathComponent(fileName)
    }

    var subtitle: String {
        let type = kind == .audio ? "AUDIO" : "VIDEO"
        return artist.isEmpty ? type : "\(artist) · \(type)"
    }
}

struct AudioMetadata {
    let title: String?
    let artist: String?

    static func read(from url: URL) -> AudioMetadata {
        let asset = AVURLAsset(url: url)
        let metadata = asset.commonMetadata

        let title = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: .commonIdentifierTitle
        ).compactMap(\.stringValue).first

        let artist = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: .commonIdentifierArtist
        ).compactMap(\.stringValue).first

        return AudioMetadata(title: title, artist: artist)
    }
}

struct LyricLine: Identifiable {
    let id: Int
    let time: Double?
    let text: String

    static func parse(_ lyrics: String) -> [LyricLine] {
        let timestampPattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: timestampPattern) else {
            return lyrics.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .enumerated()
                .map { LyricLine(id: $0.offset, time: nil, text: $0.element) }
        }

        var parsed: [(time: Double?, text: String)] = []
        for sourceLine in lyrics.components(separatedBy: .newlines) {
            let line = sourceLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            let matches = regex.matches(in: line, range: range)

            if matches.isEmpty {
                if !line.hasPrefix("[") {
                    parsed.append((nil, line))
                }
                continue
            }

            let text = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            for match in matches {
                let minutes = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
                let fractionText = match.range(at: 3).location == NSNotFound
                    ? ""
                    : nsLine.substring(with: match.range(at: 3))
                let fraction = fractionText.isEmpty ? 0 : (Double("0." + fractionText) ?? 0)
                parsed.append((minutes * 60 + seconds + fraction, text))
            }
        }

        parsed.sort { ($0.time ?? Double.greatestFiniteMagnitude) < ($1.time ?? Double.greatestFiniteMagnitude) }
        return parsed.enumerated().map {
            LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text)
        }
    }
}

struct FolderSyncReport: Sendable {
    let added: Int
    let updated: Int
    let unchanged: Int
}
