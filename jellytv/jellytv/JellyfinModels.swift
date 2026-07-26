import Foundation

struct Account: Codable { let token: String; let userID: String; let serverID: String; let baseURL: URL }

struct JellyfinItem: Codable, Identifiable, Hashable {
    let id: String; let name: String; let type: String
    let productionYear: Int?; let overview: String?; let parentIndexNumber: Int?; let indexNumber: Int?
    let userData: UserData?; let imageTags: [String: String]?
    var imageURL: URL? { guard let account = JellyfinSession.sharedAccount, let tag = imageTags?["Primary"] else { return nil }; return account.baseURL.appending(path: "Items/\(id)/Images/Primary").appending(queryItems: [URLQueryItem(name: "tag", value: tag), URLQueryItem(name: "api_key", value: account.token)]) }
    var progressPercent: Double? { guard let p = userData?.playedPercentage else { return nil }; return p / 100 }
    var detailLine: String { if type == "Episode", let season = parentIndexNumber, let episode = indexNumber { return "S\(season) · E\(episode)" }; return productionYear.map(String.init) ?? type }
    enum CodingKeys: String, CodingKey { case id = "Id", name = "Name", type = "Type", productionYear = "ProductionYear", overview = "Overview", parentIndexNumber = "ParentIndexNumber", indexNumber = "IndexNumber", userData = "UserData", imageTags = "ImageTags" }
}
struct UserData: Codable, Hashable { let playedPercentage: Double?; let playbackPositionTicks: Int64?; enum CodingKeys: String, CodingKey { case playedPercentage = "PlayedPercentage", playbackPositionTicks = "PlaybackPositionTicks" } }
struct ItemsResponse: Codable { let items: [JellyfinItem]; enum CodingKeys: String, CodingKey { case items = "Items" } }
struct AuthenticationResponse: Codable { let user: AuthUser; let accessToken: String; let serverID: String?; enum CodingKeys: String, CodingKey { case user = "User", accessToken = "AccessToken", serverID = "ServerId" } }
struct AuthUser: Codable { let id: String; enum CodingKeys: String, CodingKey { case id = "Id" } }
struct PlaybackInfo: Codable { let mediaSources: [MediaSource]; let playSessionID: String?; enum CodingKeys: String, CodingKey { case mediaSources = "MediaSources", playSessionID = "PlaySessionId" } }
struct MediaSource: Codable { let id: String; let transcodingURL: String?; let supportsDirectPlay: Bool?; enum CodingKeys: String, CodingKey { case id = "Id", transcodingURL = "TranscodingUrl", supportsDirectPlay = "SupportsDirectPlay" } }
