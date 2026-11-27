import Foundation

// MARK: - Models

struct PlaybackState: Decodable {
    let is_playing: Bool
    let progress_ms: Int?
    let item: Item?

    struct Item: Decodable {
        let id: String?
        let name: String
        let duration_ms: Int
        let artists: [Named]?     
        let album: Album?         
        let show: Named?          
        let images: [Image]?      

        var artistLine: String {
            artists?.map(\.name).joined(separator: ", ") ?? show?.name ?? ""
        }
        var artworkURL: URL? {
            let s = album?.images.first?.url ?? images?.first?.url
            return s.flatMap(URL.init(string:))
        }
    }
    struct Named: Decodable { let name: String }
    struct Album: Decodable { let name: String; let images: [Image] }
    struct Image: Decodable { let url: String }
}

struct SpotifyAPIError: LocalizedError {
    let status: Int
    var errorDescription: String? {
        switch status {
        case 401: return "Spotify Session time out, log in again."
        case 403: return "Spotify denied access."
        case 404: return "No active device in Spotify"
        case 429: return "Too many requests to Spotify, wait and then try again"
        default:  return "Error: Spotify API (\(status))"
        }
    }
}

// MARK: - Client

@MainActor
final class SpotifyClient {
    private let auth: SpotifyAuth
    init(auth: SpotifyAuth) { self.auth = auth }

    func playbackState() async throws -> PlaybackState? {
        let (data, status) = try await send("GET", "me/player?additional_types=episode")
        guard status == 200, !data.isEmpty else { return nil }
        return try JSONDecoder().decode(PlaybackState.self, from: data)
    }

    func play() async throws     { _ = try await send("PUT", "me/player/play") }
    func pause() async throws    { _ = try await send("PUT", "me/player/pause") }
    func next() async throws     { _ = try await send("POST", "me/player/next") }
    func previous() async throws { _ = try await send("POST", "me/player/previous") }

    private func send(_ method: String, _ path: String) async throws -> (Data, Int) {
        let token = try await auth.validToken()
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/\(path)")!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if method != "GET" { req.setValue("0", forHTTPHeaderField: "Content-Length") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status >= 400 { throw SpotifyAPIError(status: status) }
        return (data, status)
    }
}
