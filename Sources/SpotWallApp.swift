import SwiftUI
import AppKit

@main
struct SpotWallApp: App {
    @StateObject private var auth: SpotifyAuth
    @StateObject private var store: NowPlayingStore
    @AppStorage("pinToDesktop") private var pinToDesktop = true

    init() {
        let a = SpotifyAuth()
        _auth = StateObject(wrappedValue: a)
        _store = StateObject(wrappedValue: NowPlayingStore(auth: a))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(store)
                .background(WindowConfigurator(pinToDesktop: pinToDesktop))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

struct WindowConfigurator: NSViewRepresentable {
    var pinToDesktop: Bool

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { apply(to: v.window) }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: v.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let w = window else { return }
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.styleMask.insert(.fullSizeContentView)
        w.isMovableByWindowBackground = true
        for b: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            w.standardWindowButton(b)?.isHidden = true
        }
        if pinToDesktop {
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        } else {
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
    }
}
