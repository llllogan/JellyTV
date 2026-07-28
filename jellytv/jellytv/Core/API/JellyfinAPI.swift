import Foundation

enum JellyfinError: LocalizedError {
    case invalidServer
    case insecureServer
    case unauthorized
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidServer:
            "Enter a valid Jellyfin URL."
        case .insecureServer:
            "Remote Jellyfin servers must use HTTPS."
        case .unauthorized:
            "Session expired. Sign in again."
        case let .requestFailed(message):
            message
        case .invalidResponse:
            "Jellyfin returned an unexpected response."
        }
    }
}

enum JellyfinReachability: Equatable {
    case reachable
    case unreachable
    case unauthorized
}

struct JellyfinAPI {
    let account: Account

    init(account: Account) {
        self.account = account
    }

    static func authenticate(
        url rawURL: String,
        username: String,
        password: String,
        permitsLocalHTTP _: Bool
    ) async throws -> Account {
        guard
            let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme?.lowercased(),
            ["https", "http"].contains(scheme)
        else {
            throw JellyfinError.invalidServer
        }

        var request = URLRequest(url: url.appending(path: "Users/AuthenticateByName"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")

        var credentials = ["Username": username]
        if !password.isEmpty {
            credentials["Pw"] = password
        }
        request.httpBody = try JSONEncoder().encode(credentials)

        let response: AuthenticationResponse = try await decode(request)
        return Account(
            token: response.accessToken,
            userID: response.user.id,
            serverID: response.serverID ?? "",
            baseURL: url,
            userName: response.user.name,
            isAdministrator: response.user.policy?.isAdministrator
        )
    }

    func items(type: String, search: String? = nil) async throws -> [JellyfinItem] {
        var query = [
            URLQueryItem(name: "IncludeItemTypes", value: type),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
            URLQueryItem(name: "Fields", value: "Overview,PrimaryImageAspectRatio,UserData,Genres,RunTimeTicks,Size,ChildCount,SeriesId,SeriesPrimaryImageTag,CanDelete,ParentId,SeasonId,SeasonName,SeriesName"),
            URLQueryItem(name: "StartIndex", value: "0"),
            URLQueryItem(name: "Limit", value: "100"),
        ]

        if let search {
            query.append(URLQueryItem(name: "SearchTerm", value: search))
        }

        return try await get(
            "Users/\(account.userID)/Items",
            query: query,
            as: ItemsResponse.self
        ).items
    }

    func currentUser() async throws -> JellyfinUser {
        try await get("Users/\(account.userID)", query: [], as: JellyfinUser.self)
    }

    func refreshLibraries() async throws {
        let (_, response) = try await URLSession.shared.data(for: request(path: "Library/Refresh", method: "POST"))
        guard let http = response as? HTTPURLResponse else { throw JellyfinError.invalidResponse }
        guard 200 ..< 300 ~= http.statusCode else {
            throw http.statusCode == 401 ? JellyfinError.unauthorized : JellyfinError.requestFailed("Library refresh failed (\(http.statusCode)).")
        }
    }

    func libraryRefreshTask() async throws -> ScheduledTaskInfo? {
        let tasks: [ScheduledTaskInfo] = try await get("ScheduledTasks", query: [], as: [ScheduledTaskInfo].self)
        return tasks.first { task in
            let key = task.key?.lowercased() ?? ""
            let name = task.name.lowercased()
            return key.contains("refreshmedialibrary")
                || name.contains("scan media library")
                || name.contains("refresh media library")
        }
    }

    func resumeItems() async throws -> [JellyfinItem] {
        try await get(
            "Users/\(account.userID)/Items/Resume",
            query: [
                URLQueryItem(name: "Fields", value: "Overview,UserData,RunTimeTicks,Size,SeriesId,SeriesPrimaryImageTag,CanDelete,ParentId,SeasonId,SeasonName,SeriesName"),
                URLQueryItem(name: "Limit", value: "20"),
            ],
            as: ItemsResponse.self
        ).items
    }

    func nextUpEpisodes() async throws -> [JellyfinItem] {
        try await get(
            "Shows/NextUp",
            query: [
                URLQueryItem(name: "UserId", value: account.userID),
                URLQueryItem(name: "Fields", value: "Overview,UserData,RunTimeTicks,Size,SeriesId,SeriesPrimaryImageTag,CanDelete,ParentId,SeasonId,SeasonName,SeriesName"),
                URLQueryItem(name: "Limit", value: "20"),
            ],
            as: ItemsResponse.self
        ).items
    }

    func item(id: String) async throws -> JellyfinItem {
        try await get(
            "Users/\(account.userID)/Items/\(id)",
            query: [URLQueryItem(name: "Fields", value: "Overview,UserData,MediaSources,RunTimeTicks,Size,ChildCount,SeriesId,SeriesPrimaryImageTag,CanDelete,ParentId,SeasonId,SeasonName,SeriesName")],
            as: JellyfinItem.self
        )
    }

    func children(parentID: String, type: String) async throws -> [JellyfinItem] {
        try await get(
            "Users/\(account.userID)/Items",
            query: [
                URLQueryItem(name: "ParentId", value: parentID),
                URLQueryItem(name: "IncludeItemTypes", value: type),
                URLQueryItem(name: "Fields", value: "Overview,UserData,RunTimeTicks,Size,SeriesId,SeriesPrimaryImageTag,CanDelete,ParentId,SeasonId,SeasonName,SeriesName"),
                URLQueryItem(name: "SortBy", value: "IndexNumber,SortName"),
            ],
            as: ItemsResponse.self
        ).items
    }

    func playbackInfo(itemID: String, positionTicks: Int64 = 0, audioStreamIndex: Int? = nil) async throws -> PlaybackInfo {
        var request = request(path: "Items/\(itemID)/PlaybackInfo", method: "POST")
        var queryItems = [
            URLQueryItem(name: "UserId", value: account.userID),
            URLQueryItem(name: "StartTimeTicks", value: String(positionTicks)),
            URLQueryItem(name: "IsPlayback", value: "true"),
            URLQueryItem(name: "EnableTranscoding", value: "true"),
        ]
        if let audioStreamIndex {
            queryItems += [
                URLQueryItem(name: "AudioStreamIndex", value: String(audioStreamIndex)),
                URLQueryItem(name: "EnableDirectPlay", value: "false"),
                URLQueryItem(name: "EnableDirectStream", value: "false"),
                URLQueryItem(name: "AllowVideoStreamCopy", value: "false"),
                URLQueryItem(name: "AllowAudioStreamCopy", value: "false"),
            ]
        }
        request.url?.append(queryItems: queryItems)
        let deviceProfile: [String: Any] = [
            "MaxStreamingBitrate": 20_000_000,
            "MaxStaticBitrate": 20_000_000,
            "DirectPlayProfiles": [
                ["Type": "Video", "Container": "mp4,m4v,mov,hls"],
                ["Type": "Audio", "Container": "mp3,aac,m4a,mp4"],
            ],
            "TranscodingProfiles": [
                [
                    "Type": "Video",
                    "Container": "ts",
                    "Protocol": "hls",
                    "VideoCodec": "h264",
                    "AudioCodec": "aac",
                ],
            ],
        ]
        var profile: [String: Any] = [
            "DeviceProfile": deviceProfile,
            "UserId": account.userID,
            "StartTimeTicks": positionTicks,
        ]
        if let audioStreamIndex {
            profile["AudioStreamIndex"] = audioStreamIndex
            // A direct stream can retain all source audio tracks, causing AVPlayer to
            // choose the file's default track. Force Jellyfin to create an HLS stream
            // mapped to the user's selected audio track instead.
            profile["EnableDirectPlay"] = false
            profile["EnableDirectStream"] = false
            profile["AllowVideoStreamCopy"] = false
            profile["AllowAudioStreamCopy"] = false
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: profile)

        return try await Self.decode(request)
    }

    func playbackURL(itemID: String, source: MediaSource, audioStreamIndex: Int? = nil) -> URL {
        if let path = source.transcodingURL {
            var url = URL(string: path, relativeTo: account.baseURL)!
            url = replacingQueryItem(named: "api_key", with: account.token, in: url)
            if let audioStreamIndex {
                url = replacingQueryItem(named: "AudioStreamIndex", with: String(audioStreamIndex), in: url)
            }
            return url
        }

        // The static stream endpoint can hand AVPlayer an unsupported audio codec
        // (such as DTS or EAC3). HLS lets Jellyfin transcode audio to AAC.
        var queryItems = [
                URLQueryItem(name: "MediaSourceId", value: source.id),
                URLQueryItem(name: "Static", value: "false"),
                URLQueryItem(name: "VideoCodec", value: "h264"),
                URLQueryItem(name: "AudioCodec", value: "aac"),
                URLQueryItem(name: "MaxAudioChannels", value: "2"),
                URLQueryItem(name: "SegmentContainer", value: "ts"),
                URLQueryItem(name: "MinSegments", value: "2"),
                URLQueryItem(name: "api_key", value: account.token),
        ]
        if let audioStreamIndex {
            queryItems.append(URLQueryItem(name: "AudioStreamIndex", value: String(audioStreamIndex)))
            queryItems.append(URLQueryItem(name: "EnableDirectPlay", value: "false"))
            queryItems.append(URLQueryItem(name: "EnableDirectStream", value: "false"))
            queryItems.append(URLQueryItem(name: "AllowVideoStreamCopy", value: "false"))
            queryItems.append(URLQueryItem(name: "AllowAudioStreamCopy", value: "false"))
        }
        return account.baseURL.appending(path: "Videos/\(itemID)/master.m3u8").appending(queryItems: queryItems)
    }

    private func replacingQueryItem(named name: String, with value: String, in url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        queryItems.append(URLQueryItem(name: name, value: value))
        components.queryItems = queryItems
        return components.url ?? url
    }

    func report(
        _ endpoint: String,
        itemID: String,
        positionTicks: Int64,
        playSessionID: String?
    ) async {
        var request = request(path: endpoint, method: "POST")
        let body: [String: Any] = [
            "ItemId": itemID,
            "PositionTicks": positionTicks,
            "PlaySessionId": playSessionID as Any,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    /// A small authenticated request used to choose online or offline UI. Authentication
    /// failures are intentionally not treated as an offline server.
    func reachability() async -> JellyfinReachability {
        var request = request(path: "Users/\(account.userID)")
        request.timeoutInterval = 8
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unreachable }
            if http.statusCode == 401 { return .unauthorized }
            return 200 ..< 300 ~= http.statusCode ? .reachable : .unreachable
        } catch {
            return .unreachable
        }
    }

    func isReachable() async -> Bool { await reachability() == .reachable }

    private func get<T: Decodable>(
        _ path: String,
        query: [URLQueryItem],
        as: T.Type
    ) async throws -> T {
        var request = request(path: path)
        request.url?.append(queryItems: query)
        return try await Self.decode(request)
    }

    private func request(path: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: account.baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue(Self.authorizationHeader(token: account.token), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JellyfinError.invalidResponse
        }
        guard 200 ..< 300 ~= http.statusCode else {
            if http.statusCode == 401 {
                throw JellyfinError.unauthorized
            }
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw JellyfinError.requestFailed("Jellyfin request failed (\(http.statusCode)): \(detail)")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw JellyfinError.invalidResponse
        }
    }

    private static var authorizationHeader: String {
        authorizationHeader(token: nil)
    }

    private static func authorizationHeader(token: String?) -> String {
        var value = "MediaBrowser Client=\"Jelly TV\", Device=\"iPhone\", DeviceId=\"jellytv-ios-v1\", Version=\"1.0\""
        if let token {
            value += ", Token=\"\(token)\""
        }
        return value
    }

}
