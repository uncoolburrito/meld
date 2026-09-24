<h1 align="center">Meld</h1>

<p align="center">One Mac app for both YouTube Music and Spotify, with proper artwork and synced lyrics for both.</p>

<p align="center">Meld is a personal native macOS music client combining YouTube Music's discovery and library with Spotify's desktop playback into a single Apple Music-inspired interface with unified controls, synced lyrics, and clean macOS media integration.</p>

> ⚠️ **Spotify Support Status**: Spotify integration is currently in progress. The multi-source protocol abstraction and normalized track models are active; local AppleScript transport control, notification monitoring, and unified UI are under active development.

<table>
  <tr>
    <th>YouTube Music</th>
    <th>YouTube</th>
  </tr>
  <tr>
    <td><img src="docs/screenshot-ytm.png" alt="Meld YouTube Music screenshot"></td>
    <td><img src="docs/screenshot-yt.png" alt="Meld YouTube screenshot"></td>
  </tr>
</table>

## Features

### Unified Multi-Source Experience
- 🎵 **Native macOS Experience** — Apple Music-inspired interface featuring Liquid Glass styling, smooth sidebar navigation, and a multi-source architecture.
- 🎧 **YouTube Music** — In-app playback via hidden WKWebView with full DRM audio support, queue management, smart shuffle, and a 6-band parametric equalizer.
- 🟢 **Spotify Integration (In Progress)** — Remote transport control and live metadata sync for native Spotify desktop audio: instant notification-driven state sync, zero-latency transport verbs, and automatic Now Playing arbitration.
- 📜 **Synced Lyrics for Both** — Full-featured synced lyrics display with auto-scroll and line-by-line highlighting, sourced through YouTube Music with LRCLIB fallback.
- 🎛️ **Unified Media Routing** — macOS media keys, Now Playing claims, and notifications route to whichever source is active with zero double-skipping or conflicts.

## Requirements

- macOS 26.0 or later (tested on macOS 27 Golden Gate)
- Xcode 16.0 or later
- Swift 6.0+

## Building from Source

```bash
# Build app bundle
./Scripts/compile_and_run.sh
```

## Attribution & Upstream

Meld is an extended fork of [Kaset](https://github.com/sozercan/kaset) by Sertac Ozercan, licensed under the MIT License.

## Disclaimer

Meld is an unofficial personal application and is not affiliated with YouTube, Google Inc., or Spotify AB in any way. "YouTube", "YouTube Music", and "Spotify" are registered trademarks of their respective owners.
