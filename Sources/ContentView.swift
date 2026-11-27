import SwiftUI
import AuthenticationServices

struct ContentView: View {
    @EnvironmentObject var auth: SpotifyAuth
    @EnvironmentObject var store: NowPlayingStore
    @AppStorage("pinToDesktop") private var pinToDesktop = true
    @State private var hovering = false

    var body: some View {
        ZStack {
            RadialGradient(colors: [.black.opacity(0.45), .black.opacity(0)],
                           center: .center, startRadius: 120, endRadius: 560)

            HStack(spacing: 20) {
                VStack(spacing: 14) {
                    VisualizerView().frame(width: 420, height: 420)
                    trackInfo
                    controls
                }
                LyricsView().frame(width: 440, height: 520)
            }
            .padding(32)

            if !auth.isAuthorized { loginCard }
        }
        .frame(width: 1000, height: 640)
        .preferredColorScheme(.dark)
        .onHover { hovering = $0 }
        .contextMenu {
            Toggle("Pin to Desktop", isOn: $pinToDesktop)
            if auth.isAuthorized {
                Button("Sign Out") { auth.signOut() }
            }
            Divider()
            Button("Exit SpotWall") { NSApp.terminate(nil) }
        }
        .task {
            store.startPolling()
            await SpectrumAnalyzer.shared.start()
        }
    }

    // MARK: Pieces

    private var trackInfo: some View {
        VStack(spacing: 4) {
            Text(store.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(1)
                .shadow(color: store.accent.opacity(0.6), radius: 12)
            Text(store.artist)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)

            TimelineView(.periodic(from: .now, by: 0.25)) { tl in
                let total = Double(store.durationMs) / 1000
                let p = total > 0 ? store.position(at: tl.date) / total : 0
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(store.accent).frame(width: g.size.width * p)
                    }
                }
                .frame(height: 3)
            }
            .padding(.top, 6)
        }
        .frame(width: 400)
    }

    private var controls: some View {
        HStack(spacing: 28) {
            controlButton("backward.fill") { await store.previous() }
            controlButton(store.isPlaying ? "pause.fill" : "play.fill", size: 26) { await store.togglePlay() }
            controlButton("forward.fill") { await store.next() }
        }
        .opacity(hovering ? 1 : 0.25)
        .animation(.easeInOut(duration: 0.25), value: hovering)
    }

    private func controlButton(_ symbol: String, size: CGFloat = 20,
                               action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: symbol).font(.system(size: size, weight: .bold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var loginCard: some View {
        VStack(spacing: 14) {
            Text("SpotWall").font(.system(size: 26, weight: .heavy, design: .rounded))
            if Config.clientID == "YOUR_SPOTIFY_CLIENT_ID" {
                Text("Write in your Client ID in Config.swift")
                    .font(.callout).foregroundStyle(.orange)
            }
            Button("Войти через Spotify") { signIn() }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.12, green: 0.84, blue: 0.38))
                .controlSize(.large)
            if let e = store.errorText {
                Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func signIn() {
        Task {
            do {
                try await auth.signIn()
                store.errorText = nil
                store.startPolling()
                await store.refresh()
            } catch {
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
                store.errorText = error.localizedDescription
            }
        }
    }
}
