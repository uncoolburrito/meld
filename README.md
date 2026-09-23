<h1 align="center">Meld</h1>

<p align="center">A personal unified macOS music client combining YouTube Music and Spotify, built with Swift and SwiftUI.</p>

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

### Unified Music Experience
- 🎵 **Native macOS Experience** — Apple Music-style UI with Liquid Glass player bars, clean sidebar navigation, and a multi-source toggle
- 🎧 **YouTube Music** — In-app playback via hidden WKWebView with full DRM audio support, queue management, smart shuffle, and 6-band parametric EQ
- 🟢 **Spotify Integration** — Remote control and metadata surface for native Spotify.app audio: instant notification-driven state sync, zero-latency transport, search, and quick-play
- 📜 **Synced Lyrics** — Rich lyrics display with auto-scroll and line-by-line highlighting, sourced through YouTube Music with LRCLIB fallback
- 🎛️ **Audio & Controls** — Per-source volume gain offset; media keys route to the active player with clean Now Playing handoff and zero double-skipping

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
