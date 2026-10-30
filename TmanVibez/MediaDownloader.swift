import Foundation

struct DownloadedMedia: Sendable {
    let temporaryURL: URL
    let fileName: String
    let mimeType: String?
}

enum MediaDownloader {
    static func fetchDirectFile(from rawValue: String) async throws -> DownloadedMedia {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            throw DownloadError.httpsRequired
        }

        let host = url.host?.lowercased() ?? ""
        let videoServiceHosts = ["youtube.com", "youtu.be"]
        if videoServiceHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            throw DownloadError.youtubeDownloadsUnsupported
        }

        let blockedExtensions: Set<String> = ["html", "htm", "m3u8", "mpd"]
        guard !blockedExtensions.contains(url.pathExtension.lowercased()) else {
            throw DownloadError.directFileOnly
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 90
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)

        guard response.url?.scheme?.lowercased() == "https" else {
            throw DownloadError.httpsRequired
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw DownloadError.serverRejected
        }

        let fileName = response.suggestedFilename
            ?? response.url?.lastPathComponent
            ?? "download"

        guard SupportedMedia.fileExtensions.contains(
            URL(fileURLWithPath: fileName).pathExtension.lowercased()
        ) else {
            throw DownloadError.directFileOnly
        }

        if let mimeType = response.mimeType?.lowercased(),
           mimeType.hasPrefix("text/") || mimeType == "application/json" {
            throw DownloadError.notMediaFile
        }

        return DownloadedMedia(
            temporaryURL: temporaryURL,
            fileName: fileName,
            mimeType: response.mimeType
        )
    }
}

enum DownloadError: LocalizedError, Sendable {
    case httpsRequired
    case youtubeDownloadsUnsupported
    case directFileOnly
    case notMediaFile
    case serverRejected

    var errorDescription: String? {
        switch self {
        case .httpsRequired:
            return "Use a secure HTTPS link."
        case .youtubeDownloadsUnsupported:
            return "YouTube links cannot be downloaded here. Use YouTube's official offline feature when available, or add a media file you have permission to save."
        case .directFileOnly:
            return "This looks like a webpage or stream playlist. Paste a direct link to a supported audio or video file."
        case .notMediaFile:
            return "The server returned a webpage or text file, not media."
        case .serverRejected:
            return "The source server could not provide that file."
        }
    }
}
