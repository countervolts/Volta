# Volta

A native iOS music client for self-hosted [Subsonic](http://www.subsonic.org/)-compatible servers (Navidrome, Airsonic, Funkwhale, etc.).

## Features

- **Now Playing** — large artwork, scrubber, lossless badge, Siri integration
- **Lyrics** — synced (LRC) and plain lyrics via OpenSubsonic, LRCLib fallback
- **Library** — albums, artists, playlists, song browser
- **Stats** — play history with charts (daily / weekly / monthly / yearly / all-time)
- **Downloads** — offline playback with per-track download management
- **Siri / App Intents** — "Play Kendrick Lamar on Volta"
- **Settings** — streaming quality, crossfade, autoplay, developer logs

## Requirements

- iOS 26.0+
- A Subsonic-compatible server (tested with [Navidrome](https://navidrome.org))

## Building

This project uses [Swift Package Manager](https://www.swift.org/package-manager/) and [xtool](https://github.com/xtool-org/xtool) for on-device builds without Xcode.

```bash
# Install xtool (macOS / Linux)
brew install xtool-org/tap/xtool          # macOS
# or follow https://github.com/xtool-org/xtool for Linux

# Build & run on a connected device
xtool dev run --udid <DEVICE_UDID>

# List connected devices
xtool devices
```

Alternatively, open `Package.swift` in Xcode 16+ and run on a simulator or device.

## Project Structure

```
Sources/music/
├── App/            RootView, navigation root
├── Components/     Reusable UI (BottomBar, MiniPlayer, ArtworkView…)
├── Intents/        Siri / App Intents (PlayArtistIntent, PlaySongIntent…)
├── Models/         Subsonic data models (Song, Album, Artist…)
├── Networking/     SubsonicClient, API methods, error types
├── Persistence/    StatsStore (play events), PersistenceModels
├── Resources/      Assets, app icons
├── Services/       AudioPlayer, DownloadService, LyricsService, Logger…
├── Utilities/      Theme, Symbols, ColorExtractor, helpers
├── ViewModels/     AppState, HomeViewModel, StatsViewModel…
└── Views/          All SwiftUI screens
```

## License

MIT
