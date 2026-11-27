import Foundation
import AppKit
import AuthenticationServices
import CryptoKit
import Security
public import Combine

// MARK: - Keychain

enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "SpotWall"

    static func set(_ value: String?, for key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = q
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Auth (Authorization Code + PKCE)

enum AuthError: LocalizedError {
    case notSignedIn, badCallback, tokenRejected
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Log in to Spotify"
        case .badCallback: return "No authorization code from Spotify"
        case .tokenRejected: return "Spotify denied token, try again"
        }
    }
}

@MainActor
final class SpotifyAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isAuthorized: Bool

    private var accessToken: String?
    private var expiresAt = Date.distantPast
    private var refreshToken: String?
    private var session: ASWebAuthenticationSession?

    override init() {
        let saved = Keychain.get("refresh_token")
        refreshToken = saved
        isAuthorized = saved != nil
        super.init()
    }

    // MARK: Public

    func signIn() async throws {
        let verifier = Self.randomVerifier()
        let challenge = Self.challenge(for: verifier)

        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: Config.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Config.redirectURI),
            .init(name: "scope", value: Config.scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge)
        ]

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: Config.callbackScheme) { url, error in
                if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: error ?? AuthError.badCallback) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            self.session = s
            s.start()
        }

        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw AuthError.badCallback }

        try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Config.redirectURI,
            "client_id": Config.clientID,
            "code_verifier": verifier
        ])
    }

    func signOut() {
        accessToken = nil
        refreshToken = nil
        expiresAt = .distantPast
        Keychain.set(nil, for: "refresh_token")
        isAuthorized = false
    }

    func validToken() async throws -> String {
        if let t = accessToken, expiresAt > Date().addingTimeInterval(60) { return t }
        guard let rt = refreshToken else { throw AuthError.notSignedIn }
        try await tokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": rt,
            "client_id": Config.clientID
        ])
        guard let t = accessToken else { throw AuthError.notSignedIn }
        return t
    }

    // MARK: Token endpoint

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
    }

    private func tokenRequest(_ params: [String: String]) async throws {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            if (resp as? HTTPURLResponse)?.statusCode == 400,
               params["grant_type"] == "refresh_token" { signOut() }
            throw AuthError.tokenRejected
        }
        let tr = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = tr.access_token
        expiresAt = Date().addingTimeInterval(TimeInterval(tr.expires_in))
        if let r = tr.refresh_token {
            refreshToken = r
            Keychain.set(r, for: "refresh_token")
        }
        isAuthorized = true
    }

    // MARK: PKCE helpers

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL
    }

    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
    }

    private static func formEncode(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    // MARK: ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        }
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
