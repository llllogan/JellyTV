import Foundation

struct SeerrAccount: Codable, Equatable, Sendable {
    let baseURL: URL
    let sessionCookie: String?
    let apiKey: String?
}

struct SeerrUser: Codable, Identifiable {
    let id: Int
    let displayName: String?
    let email: String?
    let permissions: Int?

    var canApproveRequests: Bool {
        let permissions = permissions ?? 0
        return permissions & 2 != 0 || permissions & 16 != 0
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, email, permissions
    }
}

struct SeerrPage<T: Decodable>: Decodable {
    let results: [T]
}

struct SeerrGenre: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
}

struct SeerrMedia: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let tmdbId: Int?
    let tvdbId: Int?
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
    var isTV: Bool { mediaType == "tv" || tvdbId != nil }
    var isAvailable: Bool { (mediaInfo?.status ?? status) == 5 }
    var artworkURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }
    var releaseText: String? { releaseDate ?? firstAirDate }

    enum CodingKeys: String, CodingKey {
        case id, tmdbId, tvdbId, title, name, mediaType, posterPath, backdropPath, overview, releaseDate, firstAirDate, status, mediaInfo, requestStatus
    }

    init(
        id: Int,
        title: String? = nil,
        name: String? = nil,
        mediaType: String? = nil,
        posterPath: String? = nil,
        releaseDate: String? = nil,
        firstAirDate: String? = nil
    ) {
        self.id = id
        tmdbId = nil
        tvdbId = nil
        self.title = title
        self.name = name
        self.mediaType = mediaType
        self.posterPath = posterPath
        backdropPath = nil
        overview = nil
        self.releaseDate = releaseDate
        self.firstAirDate = firstAirDate
        status = nil
        mediaInfo = nil
        requestStatus = nil
    }
}

struct SeerrMediaInfo: Codable, Hashable, Sendable {
    let id: Int?
    let status: Int?
    let jellyfinMediaID: String?
    let requests: [SeerrRequest]?
    let seasons: [SeerrMediaSeason]?

    enum CodingKeys: String, CodingKey {
        case id, status, requests, seasons
        case jellyfinMediaID = "jellyfinMediaId"
    }
}

struct SeerrMediaSeason: Codable, Hashable, Sendable {
    let id: Int?
    let seasonNumber: Int
    let status: Int?
}

struct SeerrRequest: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let status: Int?
    let media: SeerrMedia?
    let createdAt: String?
    let mediaType: String?
    let seasons: [SeerrRequestSeason]?

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

struct SeerrRequestSeason: Codable, Hashable, Sendable {
    let id: Int?
    let seasonNumber: Int
    let status: Int?
}

struct SeerrSeason: Codable, Identifiable, Hashable, Sendable {
    let id: Int?
    let seasonNumber: Int
    let name: String?
    let overview: String?
    let airDate: String?
    let mediaInfo: SeerrMediaInfo?

    var stableID: Int { id ?? seasonNumber }

    enum CodingKeys: String, CodingKey {
        case id, seasonNumber, name, overview, airDate, mediaInfo
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
