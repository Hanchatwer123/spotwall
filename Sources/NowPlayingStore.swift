import SwiftUI
import AppKit
import CoreImage
public import Combine

enum LyricsState { case idle, loading, ready, notFound }

@MainActor
final class NowPlayingStore: ObservableObject {
    @Published var title = "Nothing plays"
    @Published var artist = ""
    @Published var isPlaying = false
    @Published var artwork: NSImage?
    @Published var accent: Color = Color(hue: 0.52, saturation: 0.8, brightness: 1)
    @Published var lyrics: [LyricLine] = []
    @Published var lyricsState: LyricsState = .idle
    @Published var errorText: String?

    private(set) var durationMs = 0

    private let auth: SpotifyAuth
    private let client: SpotifyClient
    private var baseProgressMs = 0
    private var baseDate = Date()
    private var trackKey: String?
    private var pollTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?

    init(auth: SpotifyAuth) {
        self.auth = auth
        self.client = SpotifyClient(auth: auth)
    }

    func position(at date: Date) -> TimeInterval {
        var p = Double(baseProgressMs) / 1000
        if isPlaying { p += date.timeIntervalSince(baseDate) }
        return min(max(p, 0), Double(durationMs) / 1000)
    }

    // MARK: Polling

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.isPlaying ? 2 : 4))
            }
        }
    }

    func refresh() async {
        guard auth.isAuthorized else { return }
        do {
            apply(try await client.playbackState())
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func apply(_ state: PlaybackState?) {
        guard let state, let item = state.item else {
            isPlaying = false
            return
        }
        let artistLine = item.artistLine
        let key = item.id ?? "\(item.name)|\(artistLine)"

        baseProgressMs = state.progress_ms ?? 0
        baseDate = Date()
        durationMs = item.duration_ms
        isPlaying = state.is_playing

        guard key != trackKey else { return }
        trackKey = key
        title = item.name
        artist = artistLine
        artwork = nil
        lyrics = []
        lyricsState = .loading

        artworkTask?.cancel()
        lyricsTask?.cancel()

        let artURL = item.artworkURL
        artworkTask = Task {
            let image = await Self.downloadImage(artURL)
            guard !Task.isCancelled, key == trackKey else { return }
            artwork = image
            if let image, let c = Self.averageColor(of: image) { accent = c }
        }

        let (name, album, duration) = (item.name, item.album?.name, Double(item.duration_ms) / 1000)
        lyricsTask = Task {
            let lines = await LyricsService.fetch(title: name, artist: artistLine, album: album, duration: duration)
            guard !Task.isCancelled, key == trackKey else { return }
            lyrics = lines
            lyricsState = lines.isEmpty ? .notFound : .ready
        }
    }

    // MARK: Commands

    func togglePlay() async {
        baseProgressMs = Int(position(at: Date()) * 1000)
        baseDate = Date()
        let wasPlaying = isPlaying
        isPlaying.toggle()
        do {
            if wasPlaying { try await client.pause() } else { try await client.play() }
        } catch {
            isPlaying = wasPlaying
            errorText = error.localizedDescription
        }
        try? await Task.sleep(for: .milliseconds(400))
        await refresh()
    }

    func next() async {
        do { try await client.next() } catch { errorText = error.localizedDescription }
        try? await Task.sleep(for: .milliseconds(500))
        await refresh()
    }

    func previous() async {
        do { try await client.previous() } catch { errorText = error.localizedDescription }
        try? await Task.sleep(for: .milliseconds(500))
        await refresh()
    }

    // MARK: Helpers

    private static func downloadImage(_ url: URL?) async -> NSImage? {
        guard let url, let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: data)
    }

    private static func averageColor(of image: NSImage) -> Color? {
        guard let tiff = image.tiffRepresentation, let ci = CIImage(data: tiff) else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: ci.extent)
        ])
        guard let out = filter?.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext().render(out, toBitmap: &px, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let ns = NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255,
                         blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(min(1, max(s, 0.45) + 0.15)), brightness: Double(max(b, 0.9)))
    }
}
