<div align="center">

# Volta

**A native iOS music player for your own server.**

Volta streams from any Subsonic / OpenSubsonic-compatible server — [Navidrome](https://navidrome.org),
Airsonic, Gonic, Funkwhale, and more — with a fast, modern interface built entirely in SwiftUI.

![Platform](https://img.shields.io/badge/platform-iOS%2026%2B-black)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange)
![License](https://img.shields.io/badge/license-open%20source-blue)

</div>

---

## Features

### Playback
- Full-screen **Now Playing** with dynamic artwork-driven backgrounds
- **Gapless playback** (off / pre-buffer / seamless) and optional **crossfade**
- **AutoPlay** — when the queue empties it keeps going: a taste-aware algorithm that
  blends similar artists, your most-played artists, and the current genre
- **Queue** you can reorder by drag, swipe a song to play next, sleep timer
- **ReplayGain / volume normalization** (track or album, peak-protected)
- Lock-screen, Control Center, and CarPlay-style remote controls

### Discovery & Library
- **Home** — Picks for You, daily Genre/Artist **Mixes**, recently played, more-like-this, recently added
- **Library** — albums, artists, playlists, songs, and genres, with sort + genre filters
- **Downloaded** section for fully offline playback
- Rich **artist** & **album** pages with bios, stats, and "appeared on"
- **Lyrics** — time-synced (LRC) or plain, via OpenSubsonic or an LRCLib fallback
- **Search** with history for songs, albums, artists, and playlists

### Downloads & Offline
- Per-track downloads with a live progress ring, multithreaded transfers
- Configurable **download quality**, **speed limit** (presets up to 100 MB/s + custom), and
  **storage cap** with least-recently-played auto-eviction

### Integration
- **Siri** — "Play _ArtistName_ on Volta", pause, resume, skip (many phrasings)
- **Stats** — local play history with daily / weekly / monthly / all-time views
- Separate **streaming quality** for Wi-Fi and cellular, **transcoding format** (MP3/AAC/Opus/original)
- Performance tuning (image-loading + caching modes) and a configurable accent colour

## Requirements

- **iOS 26.0+**
- A Subsonic / OpenSubsonic-compatible server. Tested against [Navidrome](https://navidrome.org);
  anything implementing the Subsonic API should work.

## Building

Volta is a Swift Package and builds **on-device without Xcode** via
[xtool](https://github.com/xtool-org/xtool):

```bash
# list connected devices
xtool devices

# build & run on a device
xtool dev run --udid <DEVICE_UDID>
```

Prefer Xcode? Open `Package.swift` in **Xcode 16+** and run on a device or simulator.

## Configuration

On first launch, enter your server **URL**, **username**, and **password**. Credentials are stored
in the iOS Keychain. You can edit the connection later under **Settings → Server → Edit Connection**.

## Project layout

```
Sources/music/
  Models/        Subsonic API models, MediaItem, MusicMix
  Networking/    SubsonicClient / SubsonicAPI / errors
  Services/      AudioPlayer, DownloadService, ArtworkLoader, Lyrics, Keychain
  ViewModels/    @Observable view models (one per screen)
  Views/         screens   ·   Components/ reusable cells   ·   Utilities/ Theme, LiquidGlass, effects
  Persistence/   SwiftData stores (stats, caches)
```

See [CLAUDE.md](CLAUDE.md) for architecture notes and conventions.

## Contributing

Issues and pull requests are welcome. Please keep changes focused, match the surrounding style
(minimal lowercase comments, animation-heavy SwiftUI), and prioritize maintainability and performance.

## Acknowledgements

Built on the [Subsonic](http://www.subsonic.org/pages/api.jsp) /
[OpenSubsonic](https://opensubsonic.netlify.app) APIs, with on-device builds powered by
[xtool](https://github.com/xtool-org/xtool). Lyrics fallback via [LRCLib](https://lrclib.net).
