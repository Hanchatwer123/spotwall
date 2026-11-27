import SwiftUI

struct LyricsView: View {
    @EnvironmentObject var store: NowPlayingStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { tl in
            let pos = store.position(at: tl.date) + 0.25     
            let cur = store.lyrics.lastIndex(where: { $0.time <= pos }) ?? -1
            content(current: cur)
        }
        .mask(
            LinearGradient(colors: [.clear, .black, .black, .clear],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    @ViewBuilder
    private func content(current cur: Int) -> some View {
        let lines = store.lyrics
        if lines.isEmpty {
            Text(statusText)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            let lo = max(0, cur - 2)
            let hi = min(lines.count - 1, max(cur, 0) + 4)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(lines[lo...hi]) { line in
                    let d = abs(line.id - cur)
                    let isCur = line.id == cur
                    Text(line.text.isEmpty ? "♪" : line.text)
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .opacity(isCur ? 1 : max(0.25, 0.6 - Double(d) * 0.12))
                        .blur(radius: isCur ? 0 : min(5, CGFloat(d) * 1.4))
                        .shadow(color: isCur ? store.accent.opacity(0.9) : .clear, radius: 16)
                        .scaleEffect(isCur ? 1 : 0.78, anchor: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.85), value: cur)
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private var statusText: String {
        switch store.lyricsState {
        case .idle:     return ""
        case .loading:  return "Looking for lyrics..."
        case .notFound: return "Lyrics are not found."
        case .ready:    return ""
        }
    }
}
