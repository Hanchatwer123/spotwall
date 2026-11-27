A small project that involves around creating a widget that gets music and lyrics from spotify and turns it into an eyecatching vignette. 

# SpotWall — Interactive Music Wallpaper/Widget for macOS (SwiftUI)

A borderless, transparent window featuring a circular visualizer (album art disc + spectrum rays), floating synchronized lyrics with blur and glow effects, and Spotify playback controls (play/pause/next/prev).

> The video from your message didn't come through, so the design is based on your text description.
> The code was written without compiling (there is no macOS/Xcode in my environment), so minor tweaks may be needed on the first build.

## Structure

```
SpotWall/
├── Sources/
│   ├── SpotWallApp.swift      // @main, transparent borderless window, "on desktop" mode
│   ├── Config.swift           // ← paste your Client ID here
│   ├── SpotifyAuth.swift      // OAuth Authorization Code + PKCE, tokens stored in Keychain
│   ├── SpotifyClient.swift    // /me/player, play/pause/next/previous (async/await)
│   ├── NowPlayingStore.swift  // track state, API polling, position interpolation, album art color
│   ├── LyricsService.swift    // synchronized lyrics (LRC) from LRCLIB
│   ├── SpectrumAnalyzer.swift // real-time FFT of system audio (ScreenCaptureKit + vDSP)
│   ├── VisualizerView.swift   // TimelineView + Canvas: rays, ring, aura, disc
│   ├── LyricsView.swift       // floating lyrics
│   └── ContentView.swift      // layout, buttons, login screen
└── SpotWall.entitlements

```

## Step-by-Step Build Guide

### 1. App Setup in Spotify Developer Dashboard

1. Go to [https://developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) → **Create app**.
2. **Redirect URI**: `spotwall://callback` (must match `Config.swift` exactly).
3. Under "APIs used", check **Web API**.
4. Copy the **Client ID** (Client Secret is not needed because PKCE is used).
5. While the app is in Development Mode, add your Spotify account email under **User Management**.
Spotify occasionally changes Development Mode rules (limits, Premium requirement for the owner)—check the dashboard for current terms.
6. Controlling playback (play/pause/skip) via the Web API requires **Spotify Premium**.
Reading the currently playing track works on a free account as well.

### 2. Xcode Project Setup

1. **File → New → Project → macOS → App**. Product Name: `SpotWall`, Interface: **SwiftUI**, Language: **Swift**.
2. **Minimum Deployments: macOS 14.0** (Target → General).
3. Delete the auto-generated `SpotWallApp.swift` and `ContentView.swift` files.
4. Drag all files from `Sources/` into the project navigator (check *Copy items if needed* and set Target Membership = SpotWall).
5. Open `Config.swift` and paste your Client ID:
```swift
static let clientID = "your_client_id"

```



### 3. Sandbox & Networking (Signing & Capabilities)

* Go to the **Signing & Capabilities** tab → **App Sandbox** → check **Outgoing Connections (Client)**.
(Alternatively, point *Build Settings → Code Signing Entitlements* to the `SpotWall.entitlements` file from the archive.)
* Select your Team for signing (a personal Apple ID works, and *Sign to Run Locally* also works).

### 4. Info.plist

No additional keys are required for networking: all requests use HTTPS (App Transport Security won't block anything), and permissions are handled by the entitlement in Step 3. Registering the `spotwall://` URL scheme isn't necessary either—`ASWebAuthenticationSession` intercepts it automatically.

Optional keys (Target → Info → Custom macOS Application Target Properties):

| Key | Value | Purpose |
| --- | --- | --- |
| `Application is agent (UIElement)` = `LSUIElement` | `YES` | Hide the icon from the Dock and Cmd-Tab switcher (leaving only the widget) |

If you enable `LSUIElement`, you can quit the app by right-clicking the widget → "Quit SpotWall".

### 5. Launch & Permissions

1. Press **⌘R**. In the window, click **"Log in with Spotify"** and authorize access.
2. Start playing music in the Spotify app on this Mac (or on any device logged into your account).
3. For a **real-time** audio spectrum, macOS will prompt for "Screen & System Audio Recording" permission
(*System Settings → Privacy & Security → Screen & System Audio Recording*). Grant access and **restart** SpotWall.
Only audio is captured (screen frames are ignored). Without this permission, the visualizer runs in synthetic spectrum mode.

## Controls

* **Right-click the widget**: "Pin to Desktop" (places the window above the wallpaper and below regular windows; toggles with "Always on Top"), log out, or quit.
* **Drag**: Click and drag anywhere on the window to move it.
* **Playback buttons**: Play/pause/next/prev controls fade in on hover.

## How It Works

* **Authentication**: PKCE (`code_verifier`/SHA-256 challenge) via `ASWebAuthenticationSession`; the refresh token is stored in Keychain, and the access token refreshes automatically.
* **Track Info**: Polls `GET /v1/me/player` every 2 seconds (4 seconds when paused); playback position is interpolated locally between polls so lyric lines scroll smoothly.
* **Lyrics**: Since the Spotify Web API doesn't provide lyrics, the app uses the open LRCLIB API (`/api/get`, falling back to `/api/search`). If no lyrics exist, the widget displays "not found".
* **Spectrum**: Spotify doesn't expose raw audio streams, and `audio-analysis` is deprecated for new apps. Instead, system audio is captured via ScreenCaptureKit → Hann window → `vDSP_fft_zrip` (2048) → 64 logarithmic bands (40 Hz–14 kHz) → rendered with `Canvas` inside `TimelineView(.animation)`.
* **Color**: The average color of the album cover (`CIAreaAverage`) sets the glow color for the spectrum rays and lyrics.

## What You Can Customize

* **Layout & Dimensions**: `ContentView` (1000×640 window; disc on the left, lyrics on the right).
* **Number of Rays/Bands**: `SpectrumAnalyzer.bandCount`.
* **Lyric Sync Offset**: `+ 0.25` in `LyricsView`.
* **Local Control**: Instead of the Web API, you can control a local Spotify client via AppleScript (`tell application "Spotify"`), though doing so inside the sandbox requires the `com.apple.security.temporary-exception.apple-events` entitlement.

