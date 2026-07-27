import Foundation

struct SeerrAccount: Codable, Equatable {
    let baseURL: URL
    let sessionCookie: String?
    let apiKey: String?
}

struct SeerrUser: Codable, Identifiable {
    let id: Int
    let displayName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id, displayName, email
    }
}

struct SeerrPage<T: Decodable>: Decodable {
    let results: [T]
}

struct SeerrMedia: Codable, Identifiable, Hashable {
    let id: Int
    let tmdbId: Int?
    let title: String?
    let name: String?
    var mediaType: String?
    let posterPath: String?
    let backdropPath: String?
    let overview: String?
    let releaseDate: String?
    let firstAirDate: String?
    let status: Int?
    let mediaInfo: SeerrMediaInfo?
    let requestStatus: Int?

    var displayTitle: String { title ?? name ?? "Untitled" }
    /// Discovery/search use TMDB IDs directly; request-list media records also expose `tmdbId`.
    var requestableID: Int { tmdbId ?? id }
    var isTV: Bool { mediaType == "tv" }
    var isAvailable: Bool { (mediaInfo?.status ?? status) == 5 }
    var artworkURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }
    var releaseText: String? { releaseDate ?? firstAirDate }

    enum CodingKeys: String, CodingKey {
        case id, tmdbId, title, name, mediaType, posterPath, backdropPath, overview, releaseDate, firstAirDate, status, mediaInfo, requestStatus
    }
}

struct SeerrMediaInfo: Codable, Hashable {
    let id: Int?
    let status: Int?
    let requests: [SeerrRequest]?
}

struct SeerrRequest: Codable, Identifiable, Hashable {
    let id: Int
    let status: Int?
    let media: SeerrMedia?
    let createdAt: String?

    var statusText: String {
        switch status {
        case 1: "Pending"
        case 2: "Approved"
        case 3: "Declined"
        case 4: "Failed"
        case 5: "Available"
        default: "Requested"
        }
    }
}

struct SeerrSeason: Codable, Identifiable, Hashable {
    let id: Int?
    let seasonNumber: Int
    let name: String?
    let overview: String?
    let airDate: String?

    var stableID: Int { id ?? seasonNumber }

    enum CodingKeys: String, CodingKey {
        case id, seasonNumber, name, overview, airDate
    }
}

struct SeerrTVDetails: Codable {
    let id: Int
    let name: String?
    let overview: String?
    let posterPath: String?
    let firstAirDate: String?
    let mediaInfo: SeerrMediaInfo?
    let seasons: [SeerrSeason]?
}

struct SeerrMovieDetails: Codable {
    let id: Int
    let title: String?
    let overview: String?
    let posterPath: String?
    let releaseDate: String?
    let mediaInfo: SeerrMediaInfo?
}
