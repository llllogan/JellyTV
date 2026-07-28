import Foundation

struct Account: Codable {
    let token: String
    let userID: String
    let serverID: String
    let baseURL: URL
    let userName: String?
    let isAdministrator: Bool?

    init(token: String, userID: String, serverID: String, baseURL: URL, userName: String? = nil, isAdministrator: Bool? = nil) {
        self.token = token
        self.userID = userID
        self.serverID = serverID
        self.baseURL = baseURL
        self.userName = userName
        self.isAdministrator = isAdministrator
    }
}

struct JellyfinItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let productionYear: Int?
    let overview: String?
    let parentIndexNumber: Int?
    let indexNumber: Int?
    let genres: [String]?
    let runTimeTicks: Int64?
    let size: Int64?
    let childCount: Int?
    let seriesID: String?
    let seriesPrimaryImageTag: String?
    let canDelete: Bool?
    let parentID: String?
    let seasonID: String?
    let seasonName: String?
    let seriesName: String?
    let userData: UserData?
    let imageTags: [String: String]?
    let mediaSources: [MediaSource]?

    @MainActor var imageURL: URL? {
        guard let account = JellyfinSession.sharedAccount
        else {
            return nil
        }

        let artworkItemID: String
        let tag: String?
        if type == "Episode", let seriesID, let seriesPrimaryImageTag {
            artworkItemID = seriesID
            tag = seriesPrimaryImageTag
        } else {
            artworkItemID = id
            tag = imageTags?["Primary"]
        }

        guard let tag else { return nil }
        return account.baseURL.appending(path: "Items/\(artworkItemID)/Images/Primary").appending(
            queryItems: [
                URLQueryItem(name: "tag", value: tag),
                URLQueryItem(name: "api_key", value: account.token),
            ]
        )
    }

    var progressPercent: Double? {
        guard let percentage = userData?.playedPercentage else { return nil }
        return percentage / 100
    }

    var detailLine: String {
        if type == "Episode",
           let season = parentIndexNumber,
           let episode = indexNumber
        {
            return "S\(season) · E\(episode)"
        }
        return productionYear.map(String.init) ?? type
    }

    var runtimeText: String? {
        guard let runTimeTicks else { return nil }
        return Self.durationText(for: runTimeTicks)
    }

    var remainingTimeText: String? {
        guard let runTimeTicks else { return nil }
        let playbackPosition = userData?.playbackPositionTicks ?? 0
        return "\(Self.durationText(for: max(0, runTimeTicks - playbackPosition))) remaining"
    }

    var canResume: Bool {
        guard let progress = progressPercent else { return false }
        return progress > 0.02 && progress < 0.95
    }

    var seasonCountText: String? {
        guard type == "Series", let childCount else { return nil }
        return childCount == 1 ? "1 season" : "\(childCount) seasons"
    }

    private static func durationText(for ticks: Int64) -> String {
        let totalMinutes = Int(ticks / 600_000_000)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case productionYear = "ProductionYear"
        case overview = "Overview"
        case parentIndexNumber = "ParentIndexNumber"
        case indexNumber = "IndexNumber"
        case genres = "Genres"
        case runTimeTicks = "RunTimeTicks"
        case size = "Size"
        case childCount = "ChildCount"
        case seriesID = "SeriesId"
        case seriesPrimaryImageTag = "SeriesPrimaryImageTag"
        case canDelete = "CanDelete"
        case parentID = "ParentId"
        case seasonID = "SeasonId"
        case seasonName = "SeasonName"
        case seriesName = "SeriesName"
        case userData = "UserData"
        case imageTags = "ImageTags"
        case mediaSources = "MediaSources"
    }
}

struct UserData: Codable, Hashable {
    let playedPercentage: Double?
    let playbackPositionTicks: Int64?

    enum CodingKeys: String, CodingKey {
        case playedPercentage = "PlayedPercentage"
        case playbackPositionTicks = "PlaybackPositionTicks"
    }
}

struct ItemsResponse: Codable {
    let items: [JellyfinItem]

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}

struct ScheduledTaskInfo: Codable, Identifiable {
    let id: String
    let name: String
    let key: String?
    let state: String?
    let currentProgressPercentage: Double?

    var isRunning: Bool {
        state?.caseInsensitiveCompare("Running") == .orderedSame
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case key = "Key"
        case state = "State"
        case currentProgressPercentage = "CurrentProgressPercentage"
    }
}

struct AuthenticationResponse: Codable {
    let user: AuthUser
    let accessToken: String
    let serverID: String?

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
        case serverID = "ServerId"
    }
}

struct AuthUser: Codable {
    let id: String
    let name: String?
    let policy: JellyfinUserPolicy?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case policy = "Policy"
    }
}

struct JellyfinUser: Codable {
    let name: String?
    let policy: JellyfinUserPolicy?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case policy = "Policy"
    }
}

struct JellyfinUserPolicy: Codable {
    let isAdministrator: Bool?

    enum CodingKeys: String, CodingKey {
        case isAdministrator = "IsAdministrator"
    }
}

struct PlaybackInfo: Codable {
    let mediaSources: [MediaSource]
    let playSessionID: String?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionID = "PlaySessionId"
    }
}

struct MediaSource: Codable, Hashable {
    let id: String
    let transcodingURL: String?
    let supportsDirectPlay: Bool?
    let size: Int64?
    let mediaStreams: [MediaStream]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case transcodingURL = "TranscodingUrl"
        case supportsDirectPlay = "SupportsDirectPlay"
        case size = "Size"
        case mediaStreams = "MediaStreams"
    }
}

struct MediaStream: Codable, Hashable, Identifiable {
    let index: Int
    let type: String?
    let language: String?
    let displayTitle: String?
    let title: String?

    var id: Int { index }

    var audioTrackName: String {
        displayTitle ?? title ?? language ?? "Audio \(index + 1)"
    }

    enum CodingKeys: String, CodingKey {
        case index = "Index"
        case type = "Type"
        case language = "Language"
        case displayTitle = "DisplayTitle"
        case title = "Title"
    }
}
