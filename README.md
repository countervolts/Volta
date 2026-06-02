# Volta

A native iOS music client built for self-hosted Subsonic-compatible servers — Navidrome, Airsonic, Funkwhale, and anything else that speaks the Subsonic API.

---

## What it does

- **Now Playing** — full-screen artwork, scrubber, lossless badge, Siri integration
- **Lyrics** — synced (LRC) and plain, via OpenSubsonic or LRCLib as a fallback
- **Library** — albums, artists, playlists, songs, and a downloaded tracks section for offline
- **Queue** — drag to reorder, swipe to play next, gapless playback
- **AutoPlay** — when the queue runs dry, it pulls in more music automatically
- **Downloads** — per-track download management with multithreaded transfers
- **Stats** — local play history with daily, weekly, monthly, and all-time charts
- **Siri** — "Play ArtistName on Volta", pause, skip, and more
- **Settings** — streaming quality (Wi-Fi + cellular separately), transcoding format, crossfade, appearance

## Requirements

- iOS 26.0+
- A Subsonic-compatible server (tested with [Navidrome](https://navidrome.org))

## Building

This project uses Swift Package Manager and [xtool](https://github.com/xtool-org/xtool) for on-device builds without Xcode.

```bash
# Build & run on a connected device
xtool dev run --udid <DEVICE_UDID>

# List connected devices
xtool devices
```

Or open `Package.swift` in Xcode 16+ and run on a simulator or device.
