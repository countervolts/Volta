<div align="center">

<img src="img/icon.webp" width="96" height="96" alt="Volta icon">

# Volta

**A native iOS player for your own music server Subsonic, Jellyfin, Emby, or Plex.**

![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-black)
![Built with](https://img.shields.io/badge/built%20with-SwiftUI-orange)
![Servers](https://img.shields.io/badge/servers-Subsonic%20%C2%B7%20Jellyfin%20%C2%B7%20Emby%20%C2%B7%20Plex-blue)
[![TestFlight](https://img.shields.io/badge/TestFlight-Join%20Beta-0A84FF)](https://testflight.apple.com/join/PgX1qrJq)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

</div>

---

<div align="center">

<table>
  <tr>
    <td align="center"><img src="img/framed/hometabview.webp" width="250"><br><sub><b>Home</b> · Picks for You & Recently Played</sub></td>
    <td align="center"><img src="img/framed/playerview.webp" width="250"><br><sub><b>Now Playing</b> · artwork-tinted player</sub></td>
    <td align="center"><img src="img/framed/albumview.webp" width="250"><br><sub><b>Album</b> · shuffle / play / download</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="img/framed/artistview.webp" width="250"><br><sub><b>Artist</b> · stretchy header & top songs</sub></td>
    <td align="center"><img src="img/framed/lyricview.webp" width="250"><br><sub><b>Synced Lyrics</b> · tap to seek, translate</sub></td>
    <td align="center"><img src="img/framed/searchview.webp" width="250"><br><sub><b>Search</b> · browse genres & lyrics</sub></td>
  </tr>
</table>

</div>

## Features

- **Playback** Gapless and crossfade, plus an AutoMix mode that (tries to) beat-match tracks. ReplayGain, a sleep timer, and an infinite autoplay queue. Full lock screen, Control Center, and (WIP) Siri support.
 
- **Audio** A 10-band graphic EQ, mono downmix, a 3D spatial widener, and an Audio Signal Path sheet so you can see exactly what's happening to the sound. Lossless / Hi-Res / True Hi-Res badges come from real data.

- **Now Playing** Backgrounds that take their colour from the artwork, animated cover art (GIF, APNG, WebP) on screen *and* the lock screen.

- **Lyrics** Time-synced lyrics (via [LRCLIB](https://lrclib.net)) with tap-to-seek, on-device translation, bulk download for offline use, and search across the lyrics you've saved.

- **Library** A Home feed with daily Picks for You, Discovery Station, Heavy Rotation, and genre/artist mixes. Albums, artists, songs, genres, folders, playlists, smart playlists, and hidden albums.

- **Offline** Multithreaded, resumable downloads with per-track progress, a storage cap that auto-evicts your least-played downloads, and artist profiles that still work with no connection.

- **Multi-server** Save several servers and switch between them on the fly. Each server can have its own cellular URL that kicks in automatically off Wi-Fi. No server? Try a built-in demo.

- **Localized** 17 languages with live, in-app switching.

- **Lightweight** It sits at roughly **30 MB of ram** idle on the Home tab (more on that below).

## Performance

Volta sizes itself to the device it reads the physical ram tier (3 / 4 / 6 / 8 GB+) and scales every cache and decode budget to match, then leans on disk so very little has to stay in memory.

- ram-tiered artwork cache (**48 → 128 MB**) and animated-frame decode caps (**192 → 768 px**)
- Images are never decoded larger than the device's screen
- Animated artwork runs off one shared frame-stepper with a downsampled on-disk frame cache, and caches get evicted on memory pressure
- Scroll and drag are throttled to the display refresh, with `CADisplayLink` keeping frame pacing steady
- An optional **Performance Mode** (battery saver) plus **Image Loading** and **Data Caching** dials if you want to trade quality for battery

Volta aims to remain as lightweight as possible. During testing, it used approximately the following amount of ram:

| Scenario                                                    | ram usage |
| ----------------------------------------------------------- | --------: |
| Idle on the Home tab                                        |    ~30 MB |
| Viewing an album with static artwork                        |    ~40 MB |
| Viewing an album with static artwork while playing music    |    ~50 MB |
| Viewing an artist with 15+ albums                           |    ~60 MB |
| Viewing an artist with 15+ albums while playing music       |    ~70 MB |
| Viewing an album with animated artwork                      |   ~170 MB |
| Viewing an album with animated artwork before optimizations |   ~2.3 GB |


## Supported servers

| Backend | Notes |
| --- | --- |
| **Subsonic / OpenSubsonic** | [Navidrome](https://navidrome.org) (volta works best with), Gonic, Airsonic, Funkwhale, and friends |
| **Jellyfin / Emby** | Self-hosted [Jellyfin](https://jellyfin.org) or Emby |
| **Plex** | Plex Media Server, with hosted "Sign in with Plex" |

## Getting started

Join the [testflight](https://testflight.apple.com/join/PgX1qrJq), or build source.

## Building from source

Build it yourself with [xtool](https://github.com/xtool-org/xtool) on Linux, Windows (WSL), and macOS:

```bash
xtool devices                       # list connected iPhones and their UDIDs
xtool dev run --udid <DEVICE_UDID>  # build, install, and launch on device
```