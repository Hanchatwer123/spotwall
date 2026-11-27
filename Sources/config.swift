import Foundation

enum Config {
    /// Client ID from Spotify Developer Dashboard
    static let clientID = "\"

    static let redirectURI = "spotwall://callback"
    static let callbackScheme = "spotwall"

    static let scopes = [
        "user-read-playback-state",
        "user-read-currently-playing",
        "user-modify-playback-state"
    ].joined(separator: " ")
}
