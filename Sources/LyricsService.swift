import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: TimeInterval
    let text: String
}

enum LyricsService {
    private struct Item: Decodable {
        let syncedLyrics: String?
    }

    static func fetch(title: String, artist: String, album: String?, duration: TimeInterval) async -> [LyricLine] {
        if let lines = await exact(title: title, artist: artist, album: album, duration: duration), !lines.isEmpty {
            return lines
        }
        return await search(title: title, artist: artist)
    }

    // MARK: Requests

    private static func exact(title: String, artist: String, album: String?, duration: TimeInterval) async -> [LyricLine]? {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        var q: [URLQueryItem] = [
            .init(name: "track_name", value: title),
            .init(name: "artist_name", value: artist),
            .init(name: "duration", value: String(Int(duration.rounded())))
        ]
        if let album { q.append(.init(name: "album_name", value: album)) }
        c.queryItems = q
        guard let item: Item = await load(c.url) else { return nil }
        return item.syncedLyrics.map(parse)
    }

    private static func search(title: String, artist: String) async -> [LyricLine] {
        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = [
            .init(name: "track_name", value: title),
            .init(name: "artist_name", value: artist)
        ]
        guard let items: [Item] = await load(c.url) else { return [] }
        for item in items {
            if let s = item.syncedLyrics, !s.isEmpty {
                let lines = parse(s)
                if !lines.isEmpty { return lines }
            }
        }
        return []
    }

    private static func load<T: Decodable>(_ url: URL?) async -> T? {
        guard let url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("SpotWall/1.0 (macOS desktop widget)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: LRC parsing

    static func parse(_ lrc: String) -> [LyricLine] {
        var out: [(time: TimeInterval, text: String)] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var line = Substring(raw)
            var times: [TimeInterval] = []
            while line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                let tag = line[line.index(after: line.startIndex)..<close]
                if let t = timestamp(tag) { times.append(t) }   
                line = line[line.index(after: close)...]
            }
            let text = line.trimmingCharacters(in: .whitespaces)
            for t in times { out.append((t, text)) }
        }
        out.sort { $0.time < $1.time }
        return out.enumerated().map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text) }
    }

    private static func timestamp(_ s: Substring) -> TimeInterval? {
        let p = s.split(separator: ":")
        guard p.count == 2, let m = Double(p[0]), let sec = Double(p[1]) else { return nil }
        return m * 60 + sec
    }
}
