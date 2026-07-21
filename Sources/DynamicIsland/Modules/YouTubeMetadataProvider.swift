import Foundation

struct YouTubeMetadata: Sendable {
    let videoID: String
    let title: String?
    let authorName: String?
    let thumbnailURL: URL?
    let thumbnailData: Data?
}

actor YouTubeMetadataProvider {
    private struct OEmbedResponse: Decodable {
        let title: String?
        let authorName: String?
        let thumbnailURL: String?

        enum CodingKeys: String, CodingKey {
            case title
            case authorName = "author_name"
            case thumbnailURL = "thumbnail_url"
        }
    }

    private var cache: [String: YouTubeMetadata] = [:]

    func metadata(for pageURLString: String) async -> YouTubeMetadata? {
        guard
            let videoID = Self.videoID(from: pageURLString),
            let oEmbedURL = Self.oEmbedURL(for: pageURLString)
        else {
            debugLog("missing video id for url=\(pageURLString)")
            return nil
        }

        debugLog("detected url=\(pageURLString) videoID=\(videoID)")
        if let cached = cache[videoID] {
            debugLog("cache hit videoID=\(videoID)")
            return cached
        }

        debugLog("cache miss videoID=\(videoID)")
        do {
            let (data, _) = try await URLSession.shared.data(from: oEmbedURL)
            let response = try JSONDecoder().decode(OEmbedResponse.self, from: data)
            let thumbnailURL = response.thumbnailURL.flatMap(URL.init(string:))
            let thumbnailData = await loadThumbnailData(from: thumbnailURL, videoID: videoID)
            let metadata = YouTubeMetadata(
                videoID: videoID,
                title: response.title,
                authorName: response.authorName,
                thumbnailURL: thumbnailURL,
                thumbnailData: thumbnailData
            )
            cache[videoID] = metadata
            debugLog(
                "oEmbed success videoID=\(videoID) title=\(response.title ?? "nil") " +
                    "author=\(response.authorName ?? "nil") thumbnailURL=\(thumbnailURL != nil) " +
                    "thumbnailLoaded=\(thumbnailData != nil)"
            )
            return metadata
        } catch {
            debugLog("oEmbed failure videoID=\(videoID) error=\(error.localizedDescription)")
            return nil
        }
    }

    private func loadThumbnailData(from url: URL?, videoID: String) async -> Data? {
        guard let url else {
            debugLog("thumbnail missing videoID=\(videoID)")
            return nil
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        } catch {
            debugLog("thumbnail failure videoID=\(videoID) error=\(error.localizedDescription)")
            return nil
        }
    }

    nonisolated static func videoID(from pageURLString: String) -> String? {
        guard let components = URLComponents(string: pageURLString) else { return nil }
        let host = components.host?.lowercased() ?? ""
        let path = components.path

        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            return path.split(separator: "/").first.map(String.init)
        }

        if host == "youtube.com" ||
            host.hasSuffix(".youtube.com") ||
            host == "music.youtube.com" ||
            host.hasSuffix(".music.youtube.com") {
            if let value = components.queryItems?.first(where: { $0.name == "v" })?.value, !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private nonisolated static func oEmbedURL(for pageURLString: String) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/oembed")
        components?.queryItems = [
            URLQueryItem(name: "url", value: pageURLString),
            URLQueryItem(name: "format", value: "json")
        ]
        return components?.url
    }

    private nonisolated func debugLog(_ message: String) {
        #if DEBUG
        debugPrint("DynamicIsland YouTubeMetadataProvider", message)
        #endif
    }
}
