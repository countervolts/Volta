<div align="center">

# Volta

**A native iOS player for Navidrome and other Subsonic-compatible music servers.**

Volta streams your own library from Navidrome, Gonic, Airsonic, Funkwhale, and other Subsonic / OpenSubsonic servers with a fast SwiftUI interface, offline downloads, lyrics, stats, and Apple-style playback controls.

![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-black)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange)
![Server](https://img.shields.io/badge/server-Subsonic%20%2F%20OpenSubsonic-blue)

</div>

---

## Features

- **Playback** — Gapless, crossfade, AutoMix, ReplayGain, sleep timer, and an infinite autoplay queue. Full lock-screen and Siri integration.
- **Audio** — 10-band EQ, mono downmix, 3D spatial widener, and an Audio Signal Path sheet. Lossless / Hi-Res Lossless / True Hi-Res badges backed by real format data.
- **Now Playing** — Fullscreen player with dynamic artwork backgrounds, animated cover art (GIF, APNG, WebP), a built-in visualizer, and a dynamic output-route icon.
- **Lyrics** — Time synced lyrics with tap-to-seek, on-device translation, bulk download, and lyric-content search across your local library.
- **Library** — Home feed with daily Picks for You, Discovery Station, Heavy Rotation, and genre/artist mixes. Full albums, artists, songs, genres, folders, playlists, smart playlists, and offline views.
- **Offline** — Multithreaded downloads with per-track progress, storage cap with auto-evict, and offline artist profiles that synthesize downloaded content.
- **Connectivity** — Per-server cellular URL with automatic switching, and independent Wi-Fi / cellular streaming quality.


## Requirements

- iOS 17.0+
- A Subsonic / OpenSubsonic-compatible server such as [Navidrome](https://navidrome.org)
- iOS 26 devices get Liquid Glass tabs

## Building

Volta is a Swift Package and can build on-device with [xtool](https://github.com/xtool-org/xtool) (for linux and windows)

```bash
xtool devices
xtool dev run --udid <DEVICE_UDID>
```
