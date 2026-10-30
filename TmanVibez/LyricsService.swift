import Foundation

struct LyricsRecord: Decodable, Identifiable, Sendable {
    let id: Int
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let plainLyrics: String?
    let syncedLyrics: String?

    var lyricsToSave: String? {
        if let syncedLyrics, !syncedLyrics.isEmpty { return syncedLyrics }
        if let plainLyrics, !plainLyrics.isEmpty { return plainLyrics }
        return nil
    }

    var syncLabel: String {
        syncedLyrics?.isEmpty == false ? "SYNCED" : "PLAIN"
    }
}

enum LyricsService {
    static func search(track: String, artist: String) async throws -> [LyricsRecord] {
        guard var components = URLComponents(string: "https://lrclib.net/api/search") else {
            throw LyricsSearchError.invalidAddress
        }

        var queryItems = [URLQueryItem(name: "track_name", value: track)]
        if !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "artist_name", value: artist))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw LyricsSearchError.invalidAddress
        }

        var request = URLRequest(url: url)
        request.setValue("TmanVibez/1.0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 25

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LyricsSearchError.serviceUnavailable
        }

        return try JSONDecoder().decode([LyricsRecord].self, from: data)
    }
}

enum LyricsSearchError: LocalizedError, Sendable {
    case invalidAddress
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "The lyrics search could not be prepared."
        case .serviceUnavailable:
            return "Lyrics are unavailable right now. Try again later."
        }
    }
}
