import Foundation

enum SeerrError: LocalizedError {
    case invalidServer
    case insecureServer
    case unauthorized
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidServer: "Enter a valid Seerr URL."
        case .insecureServer: "Remote Seerr servers must use HTTPS."
        case .unauthorized: "Seerr sign-in expired. Connect Seerr again."
        case let .requestFailed(message): message
        case .invalidResponse: "Seerr returned an unexpected response."
        }
    }
}

struct SeerrAPI: Sendable {
    let account: SeerrAccount

    static func jellyfinSignIn(url rawURL: String, username: String, password: String, permitsLocalHTTP _: Bool) async throws -> SeerrAccount {
        let baseURL = try validatedURL(rawURL)
        var request = URLRequest(url: baseURL.appending(path: "api/v1/auth/jellyfin"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["username": username, "password": password])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SeerrError.invalidResponse }
        guard 200 ..< 300 ~= http.statusCode else { throw failure(http) }
        let headerFields = http.allHeaderFields.reduce(into: [String: String]()) { fields, entry in
            guard let key = entry.key as? String, let value = entry.value as? String else { return }
            fields[key] = value
        }
        let responseCookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: baseURL)
        let storedCookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
        guard let cookie = (responseCookies + storedCookies).first(where: { $0.name == "connect.sid" }) else {
            throw SeerrError.requestFailed("Seerr signed in but did not provide a connect.sid session cookie.")
        }
        return SeerrAccount(baseURL: baseURL, sessionCookie: "\(cookie.name)=\(cookie.value)", apiKey: nil)
    }

    static func apiKeyAccount(url rawURL: String, apiKey: String, permitsLocalHTTP _: Bool) throws -> SeerrAccount {
        let baseURL = try validatedURL(rawURL)
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SeerrError.unauthorized
        }
        return SeerrAccount(baseURL: baseURL, sessionCookie: nil, apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func currentUser() async throws -> SeerrUser { try await get("api/v1/auth/me") }
    func pendingRequests() async throws -> [SeerrRequest] {
        let page: SeerrPage<SeerrRequest> = try await get(
            "api/v1/request",
            query: [
                URLQueryItem(name: "take", value: "20"),
                URLQueryItem(name: "sort", value: "modified"),
                URLQueryItem(name: "sortDirection", value: "desc"),
            ]
        )
        return page.results
    }
    func approvalRequests() async throws -> [SeerrRequest] {
        let page: SeerrPage<SeerrRequest> = try await get(
            "api/v1/request",
            query: [
                URLQueryItem(name: "take", value: "100"),
                URLQueryItem(name: "filter", value: "pending"),
                URLQueryItem(name: "sort", value: "modified"),
                URLQueryItem(name: "sortDirection", value: "desc"),
            ]
        )
        return page.results
    }
    func approveRequest(id: Int) async throws -> SeerrRequest {
        try await updateRequest(id: id, status: "approve")
    }
    func declineRequest(id: Int) async throws -> SeerrRequest {
        try await updateRequest(id: id, status: "decline")
    }
    func trendingMovies() async throws -> [SeerrMedia] {
        try await discovery("api/v1/discover/trending", kind: "movie", query: [URLQueryItem(name: "mediaType", value: "movie")])
    }
    func trendingTV() async throws -> [SeerrMedia] {
        try await discovery("api/v1/discover/trending", kind: "tv", query: [URLQueryItem(name: "mediaType", value: "tv")])
    }
    func popularMovies() async throws -> [SeerrMedia] {
        try await discovery("api/v1/discover/movies", kind: "movie", query: [URLQueryItem(name: "sortBy", value: "popularity.desc")])
    }
    func popularTV() async throws -> [SeerrMedia] {
        try await discovery("api/v1/discover/tv", kind: "tv", query: [URLQueryItem(name: "sortBy", value: "popularity.desc")])
    }
    func upcomingMovies() async throws -> [SeerrMedia] { try await discovery("api/v1/discover/movies/upcoming", kind: "movie") }
    func upcomingTV() async throws -> [SeerrMedia] { try await discovery("api/v1/discover/tv/upcoming", kind: "tv") }
    func movieGenres() async throws -> [SeerrGenre] { try await get("api/v1/discover/genreslider/movie") }
    func tvGenres() async throws -> [SeerrGenre] { try await get("api/v1/discover/genreslider/tv") }
    func movies(genre: SeerrGenre) async throws -> [SeerrMedia] {
        try await discovery("api/v1/discover/movies/genre/\(genre.id)", kind: "movie")
    }
    func tv(genre: SeerrGenre) async throws -> [SeerrMedia] {
        try await discovery("api/v1/discover/tv/genre/\(genre.id)", kind: "tv")
    }

    func search(query: String) async throws -> [SeerrMedia] {
        var components = URLComponents(url: account.baseURL.appending(path: "api/v1/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        let request = self.request(url: components.url!)
        let page: SeerrPage<SeerrMedia> = try await decode(request)
        return page.results
    }

    func movie(id: Int) async throws -> SeerrMovieDetails { try await get("api/v1/movie/\(id)") }
    func tv(id: Int) async throws -> SeerrTVDetails { try await get("api/v1/tv/\(id)") }

    func requestMovie(id: Int) async throws -> SeerrRequest {
        try await createRequest(["mediaType": "movie", "mediaId": id])
    }

    func requestTV(id: Int, seasons: [Int]) async throws -> SeerrRequest {
        try await createRequest(["mediaType": "tv", "mediaId": id, "seasons": seasons])
    }

    private func discovery(_ path: String, kind: String, query: [URLQueryItem] = []) async throws -> [SeerrMedia] {
        let page: SeerrPage<SeerrMedia> = try await get(path, query: query)
        return page.results.map { media in
            var media = media
            media.mediaType = media.mediaType ?? kind
            return media
        }
    }

    private func createRequest(_ body: [String: Any]) async throws -> SeerrRequest {
        var request = request(path: "api/v1/request", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await decode(request)
    }

    private func updateRequest(id: Int, status: String) async throws -> SeerrRequest {
        var request = request(path: "api/v1/request/\(id)/\(status)", method: "POST")
        request.httpBody = Data("{}".utf8)
        return try await decode(request)
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var request = request(path: path)
        request.url?.append(queryItems: query)
        return try await decode(request)
    }

    private func request(path: String, method: String = "GET") -> URLRequest {
        request(url: account.baseURL.appending(path: path), method: method)
    }

    private func request(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = account.apiKey { request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key") }
        if let cookie = account.sessionCookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        return request
    }

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SeerrError.invalidResponse }
        guard 200 ..< 300 ~= http.statusCode else { throw Self.failure(http, data: data) }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw SeerrError.invalidResponse }
    }

    private static func failure(_ response: HTTPURLResponse, data: Data = Data()) -> SeerrError {
        if response.statusCode == 401 || response.statusCode == 403 { return .unauthorized }
        let message = String(data: data, encoding: .utf8) ?? ""
        return .requestFailed("Seerr request failed (\(response.statusCode)): \(message)")
    }

    private static func validatedURL(_ rawURL: String) throws -> URL {
        guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), url.host != nil
        else { throw SeerrError.invalidServer }
        return url
    }
}
