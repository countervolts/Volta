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

### Playback
- Full-screen Now Playing with dynamic artwork backgrounds
- Gapless playback, crossfade, AutoMix, sleep timer, ReplayGain normalization
- Queue editing, drag reordering, swipe Play Next, and library-wide autoplay
- Lock-screen, Control Center, AirPods remote, Siri intent, and animated artwork support
- Time-synced lyrics, tap-to-seek lyrics, and on-device lyric translation when available

### Library
- Home with Picks for You, Discovery Station, Heavy Rotation, daily genre/artist mixes, recent albums, and more-like-this rows
- Albums, artists, songs, genres, folders, playlists, smart playlists, and downloaded-only views
- Artist pages with photos, bios, stats, top songs, albums, similar artists, and appeared-on albums
- Album and playlist pages with play/shuffle/download actions, descriptions, stats, and rich song menus
- Search history plus songs, albums, artists, playlists, and genres

### Offline
- Per-track download progress
- Multithreaded downloads, custom speed limit, quality setting, and storage cap
- Local artwork library for faster cover and artist image loading
- Offline downloaded library sections

### Settings
- Wi-Fi and cellular streaming quality
- Transcoding format, download quality, cache modes, and image-loading modes
- Custom accent color, live artwork toggle, lossless badges, and list artwork toggle
- Server info, storage sizes, log export, log filtering, and speed test

## Why Volta

Most Subsonic clients feel like file browsers with playback bolted on. Volta is built around the way music apps feel on iOS: quick artwork, strong gestures, rich now-playing controls, daily mixes, smart queues, and offline-first behavior.

Volta is also server-friendly. It uses standard Subsonic/OpenSubsonic endpoints, keeps credentials in Keychain, supports HTTP only with a warning, and avoids requiring a proprietary cloud account.

## Requirements

- iOS 17.0+
- A Subsonic / OpenSubsonic-compatible server, such as [Navidrome](https://navidrome.org)
- For iOS 26 devices, Volta uses Liquid Glass and native tab accessories. Older iOS versions silently use fallback UI.

## Building

Volta is a Swift Package and can build on-device with [xtool](https://github.com/xtool-org/xtool):

```bash
xtool devices
xtool dev run --udid <DEVICE_UDID>
```

With Xcode, open `Package.swift` and run the `Volta` target on a device or simulator.

Codespaces can inspect and edit the package, run manifest checks, and use SourceKit-LSP. iOS app builds still need an Apple SDK environment.

## Project Layout

```text
Sources/Volta/
  App/           app entry and root view
  Components/    reusable SwiftUI controls
  Intents/       Siri / App Intents
  Models/        Subsonic, media, and smart playlist models
  Networking/    Subsonic client and API calls
  Persistence/   play stats and local stores
  Services/      playback, downloads, artwork, logs, keychain, sharing
  Utilities/     theme, glass fallback, effects, helpers
  ViewModels/    screen state and loading
  Views/         app screens
```

## Acknowledgements

Built on the [Subsonic](http://www.subsonic.org/pages/api.jsp) and [OpenSubsonic](https://opensubsonic.netlify.app) APIs. Lyrics fallback uses [LRCLib](https://lrclib.net). Universal music links use Songlink/Odesli.
