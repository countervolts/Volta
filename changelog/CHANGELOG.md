# volta full changelog

a running log of everything done in the app

## Recent changes

### Backends & accounts (multi-server support)
- [x] added a `MusicService` protocol abstraction with a `MusicServiceFactory` so the whole UI talks to one interface; servers now carry a `MusicBackendKind` (Subsonic/Navidrome, Jellyfin, Emby, Plex) plus a `MusicServiceCapabilities` set (folder browsing, public sharing, favorites, …)
- [x] added a Jellyfin/Emby client that maps both servers into Volta's Subsonic-shaped models
- [x] added a Plex client (token auth, MediaContainer envelopes, ratings-as-favorites, cached file-part keys for synchronous stream/download URLs) with hosted "Sign in with Plex" SSO through a Safari sheet (PlexHostedAuth)
- [x] redesigned the login screen into a service-selection step with per-backend login, the Plex hosted sign-in flow, and a language menu
- [x] added public, stream-only demo servers (Navidrome demo, Jellyfin demo) so people can explore without their own server; the app refuses to download or persist demo songs, lyrics, or artwork
- [x] added a Switch Server sheet from the account menu; touch-and-hold or swipe a saved server to remove it (the currently connected server is protected and can't be removed)

### Localization
- [x] added runtime language switching across 17 languages (English default + Spanish, French, German, Portuguese, Italian, Dutch, Russian, Polish, Turkish, Swedish, Norwegian, Danish, Finnish, Simplified Chinese, Japanese, Korean) backed by a `LocKey` string catalog (~210 keys); added Settings -> Language and threaded localized strings through the views and view models

### Settings
- [x] split the single large SettingsView into focused per-section screens under Settings/ (About, Appearance, AutoMix, Backup, Developer, Notifications, Performance, Playback, Server, Storage) behind a SettingsView container

### Library
- [x] added Hidden Albums: hide albums from the library/artist views and manage the hidden list from Settings (HiddenAlbumStore + Hidden Albums settings)

## Earlier changes

### Player & Playback
- [x] make it so that the tab bar miniplayer doenst have a forward button
- [x] make the tab bar miniplayer also include the artist name
- [x] when pressing the album cover from the queue view make it so it will expand the cover (just like how the lyric one works) queue/lyrics now fill the artwork area; tapping artwork tab returns to now playing
- [x] show the progress bar of the song when viewing the lyrics and queue mini progress bar above controls; full scrubber visible when switching back to now playing
- [x] make the AutoPlay function work, when running out of songs in the queue add random songs from the users library and play them (queue cycles Off>AutoPlay>Algorithm>Off)
- [x] add the ability to rearrange the queue (drag handle on right side, move up or down)
- [x] add the ability to swipe right on a song to make it play next in the queue
- [x] add gapless playback (off/weak/on) weak=pre-buffer, on=AVQueuePlayer seamless
- [x] improved algorithmic infinite play (artist-scoped>similar-artist>random fallback chain)
- [x] move the progress bar (when in lyric and queue view) to right above the control buttons
- [x] make it so that when pressing the album cover in the player view when looking at the queue does the same thing as pressing it when in the lyric view both now live in the same layout, tapping the queue/lyrics tab icon switches back
- [x] ensure support for all audio file types
- [x] tapping a synced lyric line seeks to that point in the song (tap any line in synced lyrics view)
- [x] sleep timer (moon button in player bottom bar: 5/15/30/45/60 min or end of track)
- [x] volume normalization / ReplayGain (Settings>Playback>Volume Normalization: off/track/album, peak-protected)
- [x] share button on now playing 3-dot + song 3-dot menus via Songlink/Odesli-style public pages
- [x] artist profile Play plays the full discography in album order; Shuffle shuffles all artist songs
- [x] album about text and playlist descriptions show below the action row with More/Less expansion
- [x] lyric translation button uses Apple's Translation framework on supported iOS versions
- [x] volume slider supports tap or drag from anywhere on the bar
- [x] Lossless badge popover now opens an Audio Signal Path sheet showing source format, server stream settings, app processing, output route and result
- [x] when doing play next on a song it adds it to the queue next instead of playing it now (insert-only queue path, de-dupes moved queued songs)
- [x] added a smoother player background transition so song changes keep the previous color until the next artwork color fades in
- [x] AutoMix can now tempo-match downloaded tracks using BPM metadata or fallback onset analysis, with a default-on BPM Match toggle in Settings -> Playback
- [x] AutoMix BPM matching now actually engages on streamed (un-downloaded) tracks: when there's no BPM tag and no local file it fetches a short ~3 MB prefix of the original stream, runs the on-device onset estimate over it, and caches the result per song id. The tempo bend was reworked to sound clean: only the OUTGOING (ending) track bends — a single constant rate set once at the blend start (`AutoMixTempo.outgoingRate` = nextBPM/currentBPM, octave-folded, ±6% pitch-preserved via `.timeDomain`, engages within ~32%) and held while it fades out, like a podcast speed change. The incoming track always plays at its true tempo (rate 1.0) so the track that becomes dominant is never time-stretched. Earlier attempts that bent the incoming with a per-frame rate ramp stuttered (AVPlayer re-buffers the time-pitch unit on every rate change) — a single rate set fixed that
- [x] Crossfade and AutoMix no longer sound alike, and both are now fluid: both use a constant-power (equal-power cos/sin) curve so perceived loudness stays steady through the blend with no mid-blend dip and no "one song suddenly louder". They stay distinct via crossover *shape* — Crossfade sweeps evenly, AutoMix eases (linger on the outgoing, swap through the middle, settle) and layers on the tempo bend + silence trim. Crossfade never alters tempo; AutoMix does
- [x] AutoMix/Crossfade now pre-buffer (preroll) the next track ~6s before the blend by playing it muted on the idle player, then the crossfade reuses that already-rolling player instead of creating a fresh item — kills the stall/gap on streamed tracks. The outgoing tempo bend also fires ~15% into the fade (while it's already ducking) to mask the time-stretch engage
- [x] Fixed the blend starting silent then jumping in loud / the tempo bend dropping to silence: (1) every AVPlayerItem now gets one fixed pitch-preserving time-stretch algorithm at creation (`makePlayerItem`), so AutoMix bends tempo by only changing `rate` and never switches the algorithm mid-playback — that algorithm switch was re-priming the audio unit and causing the silence right when the mix started; (2) the incoming track is warmed before the blend — the outgoing holds at full level (so there's no silence) while the incoming buffers until it's `.readyToPlay` + `isPlaybackLikelyToKeepUp` + actually playing (up to 3s, bailing early if the outgoing is about to end), which also removes the post-blend "next song won't play for a second" gap on streamed tracks; (3) silence-trim seeks use a small tolerance instead of a slow exact seek; (4) preview starts both players together so the incoming is warm and past its leading silence before the crossfade begins
- [x] main player now has a center bottom-row audio visualizer button that opens a full-screen animated visualizer
- [x] improved the full-screen visualizer with animated radial rings, pulse spokes, glow and orbiting particles so it feels more unique than basic bars
- [x] dynamic output icon in the player the route button now shows AirPods / AirPods Pro / AirPods Max / Beats / headphones / car / speaker based on the active route (built-in speaker keeps the default AirPlay glyph), driven by a new `OutputRouteMonitor`
- [x] output icon no longer shows generic wired headphones for Bluetooth/AirPods: broadened brand detection (AirPods Max/Pro/regular, Beats, HomePod, third-party speakers) and added a CoreMotion `CMHeadphoneMotionManager.isDeviceMotionAvailable` fallback so renamed AirPods still show an AirPods glyph; wired USB-C/Lightning EarPods now show headphones instead of a speaker; wired analog headphones still show the headphones glyph


### Library & Navigation
- [x] fix song view in the library tab because currently it shows nothing
- [x] when pressing a artist name in the playback view make it open that artists profile
- [x] when pressing a artist in the artists section of the library make it open the profile
- [x] add downloaded section in the library tab
- [x] scrolling down in library hides the search bar for more space (single ScrollView so nav search field collapses)
- [x] play button on the artist profile (Play + Shuffle); autoplay scoped to that artist so it keeps playing them
- [x] filtering within library sections sort (Name/Year/Most Played/Recently Added) + genre filter + Never Played toggle (filter menu on albums/songs)
- [x] custom daily mixes ("Genre Mix" / "Artist Mix") generated from the library, shown in Picks for You, rotate each day (seeded RNG), 20–50 songs each
- [x] add folder/directory browsing in the library tab new "Folders" filter backed by getMusicFolders / getIndexes / getMusicDirectory, drill into directories, Play/Shuffle a directory, multi-folder picker, search-filtered
- [x] add multi-select mode long-press a song in the Library Songs list to enter selection, tap to multi-select, floating bar to batch Play Next / Queue / Add to Playlist / Download, Select All + count
- [x] share actions now resolve to Songlink/Odesli-style links instead of Navidrome server shares
- [x] Picks for You includes daily Discovery Station and Heavy Rotation mixes
- [x] smart playlists can be pinned to the top
- [x] holding an album includes a View Stats option
- [x] smart playlist creation has searchable multi-select pickers for artists and albums plus clearer rule summaries
- [x] Library Songs has Album sorting plus Play and Shuffle controls
- [x] genre grids can be left with the normal swipe-back gesture
- [x] Picks for You mixes no longer update on every app open; randomized picks and mixes stay cached for the day unless forced refreshed
- [x] smart playlists can filter to only Hi-Res Lossless tracks
- [x] playlists can be organized into local folders; server and smart playlists can be added/removed from folders
- [x] Library genre rows now say Album/Albums beside the count
- [x] Folder browsing screens re-enable legacy swipe-back
- [x] Folder song 3-dot menus now include Go to Album and Go to Artist

### Search & History
- [x] show previous search results when using the search feature
- [x] search includes matching genres
- [x] Search now has a default browse page with colored genre cards plus Picks for You and Artists rows; pressing the search field shows recent searches before typing while the default landing stays on Browse Genres
- [x] lyric search results now show the song cover art and long-press actions to Go to Album / Go to Artist
- [x] recent search history shows artwork/type thumbnails for artists and albums plus generic search icons for submitted text searches
- [x] recent search history now stores only explicit keyboard Search submissions or exact artist/album taps, and recent artist/album rows reopen their detail screens

### Downloads
- [x] when using the download feature show a download circle progress next to each song of the album or playlist to show how much of each song is downloaded
- [x] download progress circle now accurate (downloads use a download-specific URL honouring download bitrate, so size matches and progress isn't skewed by streaming transcode)
- [x] download storage cap setting + auto-evict least-recently-played downloads when over the limit (toggle on/off)
- [x] limit download speeds setting
- [x] downloads can resume automatically after connection loss using URLSession resume data when available and retrying pending downloads when the network returns
- [x] downloaded/offline artist names now use the primary artist name instead of feature-credit strings
- [x] offline artist profiles now synthesize downloaded albums and songs when the server cannot load the artist

### Settings & Integration
- [x] remove "Show Explicit Content" setting
- [x] export all logs button bundles all logs into zip, shares to Files app
- [x] add setting for transcoding format (mp3/aac/opus/original)
- [x] add setting for changing the streaming quality on wifi and data separately
- [x] add settings for app appearance (lossless badge, dynamic background, accent color)
- [x] add setting (and functionality) to cache data on device downloaded section + gapless pre-buffer
- [x] add section to view server/music info artists, albums, total songs, total duration, streaming speed test with grade
- [x] allow searching in settings
- [x] make it so that 3 dot uis have much more things: play, play next, add to queue, add to playlist
- [x] add the option in settings to save/edit the server login information (url, username, password via Edit Connection view)
- [x] have better siri integration play artist/song/album/playlist, pause, resume, skip (multiple phrase variants each)
- [x] show total songs and total amount of music (in days/hours/minutes) in settings
- [x] allow swipe to exit settings (re-enabled edge swipe-back via SwipeBackEnabler)
- [x] Performance settings: Image Loading (Fast/Balanced/Conservative) + Data Caching (Aggressive/Balanced/Light) + Prefetch Artist Images (warms profile photos)
- [x] raised download speed limits (up to 100 MB/s) with a custom MB/s entry; storage cap presets up to 100 GB with a custom GB entry
- [x] custom 10-band graphic equalizer (Settings>Playback>Equalizer): enable toggle, presets, per-band ±12 dB sliders, applied globally via MTAudioProcessingTap
- [x] add feature for url switching when on data vs wifi optional per-server Cellular URL (Edit Connection), auto-switches the client base URL via NWPathMonitor; also wired the previously-dead Cellular Quality streaming setting
- [x] let users define new usernames and passwords for cellular server switching (Edit Connection>Separate Cellular Login; blank values fall back to the main server credentials)
- [x] local artwork library download is faster and shows an estimated total size
- [x] custom accent colour picker works through the app theme
- [x] storage shows logged play events size
- [x] storage shows logs size
- [x] verbose logs can be filtered by level and sorted newest/oldest
- [x] added Developer Tools under Settings with slow server / expired session / no network simulations, profiling, RAM/runtime snapshots, mix/autoplay/automix dry runs and log output
- [x] added AutoMix and crossfade tuning in Settings (crossfade duration, AutoMix style, max blend and silence trim)
- [x] added a live performance overlay toggle in Developer Tools showing FPS, frame pacing, RAM and queue state
- [x] improved local artwork library size estimates by sampling artwork Content-Length instead of using one flat per-item guess
- [x] Library Stats & Speed Test now shows total music size from summed song file sizes
- [x] add setting to dump all app files (Settings -> Storage -> Dump App Files exports Documents, Application Support, Caches and Preferences as a zip)
- [x] moved notifications into their own Settings -> Developer -> Notifications submenu with warning notifications hidden by default unless enabled
- [x] Library Stats & Speed Test now includes a server health dashboard with ping status, latency, API version, server type, active URL and connection type
- [x] app data dumps now exclude artwork cache, live-artwork cache and Spotlight thumbnail caches
- [x] moved Dump App Files into the Developer section
- [x] added Settings backup/restore for app preferences and smart playlists (passwords stay in Keychain and are not exported)
- [x] moved AutoMix tuning into its own Settings submenu
- [x] added a Preview AutoMix screen under Settings -> AutoMix that picks two of your tracks (preferring downloads, falling back to random library songs), shows both with artwork and detected BPM, and draws a timeline of two overlapping clips with an orange band marking exactly when the blend happens; clip lengths are based on the AutoMix blend time (short intro/outro + the blend), not full songs, and a Play Preview button auditions the actual crossfade + beat-match out loud (pausing the main player) with a moving playhead
- [x] added a Notifications toggle to hide offline error notifications while keeping them logged
- [x] offline error notifications now match warning notifications: hidden by default and shown only after enabling Show Offline Error Notifications
- [x] Server Health now reports Server unreachable instead of raw SubsonicError text
- [x] added a double-confirmed Clear Logged Play Events action for local stats reset
- [x] performance overlay now shows CPU %, estimated CPU power, thermal state, battery, low-power state, transition and autoplay state
- [x] automatic local JSON playlist backups are enabled by default, update after playlist edits, and Settings can refresh backups or restore deleted playlists
- [x] users can permanently delete local playlist backups from Settings
- [x] the whole Developer section is hidden until you tap Version/Build in About 7 times, persisted via `developerUnlocked`; a hint toast counts down from 4 taps and a "Hide Developer Tools" button re-locks it

### Bug Fixes
- [x] fix error in stats where it will say avg play for 700,000 days instead of the amount of days the app was installed
- [x] fix bug where the 3 dots in the Top Songs does nothing
- [x] fix bug where similar artists within artist profile (when pressed) wont open anything
- [x] fix bug where pressing 3 dots in the top songs for artists plays it, also fix how that ui works restructured to onTapGesture so 3-dots button is fully isolated
- [x] when scrolling down with no music playing it will still do animation to hide the miniplayer tab bar only minimizes on scroll when music is playing
- [x] when scrolling up instead of just going past the profile picture it should start to close it scroll offset detection, overscroll > 60pt triggers dismiss
- [x] fix progress bar going PAST the total bar (progress clamped to 0...1, fill width capped to track width)
- [x] fix foreground progress bar detaching when moving player up/down (fg+bg share one geometry/origin)
- [x] fix accent colour picker showing all purple circles (custom Circle swatch row instead of tinted SF Symbols)
- [x] artist profile no longer flashes an album cover as the profile picture before the real photo loads (waits for artwork lookup)
- [x] albums opened from an artist profile can be closed like home-tab albums (added GlassBackButton to AlbumDetailView)
- [x] fix Picks for You album cover off-centred / black bar (artwork now fills full card width)
- [x] fix stats counting "Artist1, Artist2" feature credits as their own artist (top artists grouped by primary/lead artist)
- [x] genre no longer appears twice on the artist profile (only in Stats now)
- [x] pencil button works again playlist sheets consolidated into one enum-driven sheet
- [x] artist photo shows immediately now (resolved earlier + cached, no longer waits for "More")
- [x] fixed crash when long-pressing an album cover (ArtworkView no longer force-reads the app environment inside context-menu previews)
- [x] artist profile photo appears as soon as it loads now (mirrored into view @State so the body re-renders without interaction)
- [x] fixed the black bar on the side of some Picks for You covers (artwork forced to a true 1:1 square)
- [x] fixed the intermittent Picks for You black bar in both pick cards and mix cards
- [x] fixed the Picks for You black bar on long album titles by truncating titles to a single line with a trailing ellipsis (album + mix pick cards), so no card grows taller than its neighbours and the square artwork is never squished into a side bar
- [x] miniplayer swipe no longer also opens the player (highPriorityGesture), fixing the stuck open/close state afterwards
- [x] fixed the library `.searchable` bar bleeding into the artist profile (toolbar hidden on artist detail)
- [x] foreground progress bar no longer detaches from the track (fill anchored inside the track via overlay)
- [x] View Credits no longer shows the composer twice (deduped + composer-role suppressed when displayComposer present)
- [x] hold-album preview now renders in place (same root cause as the crash ArtworkView no longer needs the app env)
- [x] fix ui bug when leaving an album then scrolling detaches the album cover gated the swipe-back pop gesture (no longer fires mid-zoom-transition or simultaneously with the scroll pan) which was orphaning the zoom source snapshot
- [x] fix the search bar on artists in the library tab again to just be exactly like how it works on albums/genres (artist rows use native NavigationLink push)
- [x] when using airpods and going next at the end of a album while using autoplay or algorithm it will just repeat the same song (autoplay/algorithm now preloads before queue end so remote next advances)
- [x] fix bug on iOS versions that support liquid glass not using it and instead falling back onto the fallback (modern tabs start on iOS 26.0; tab accessory is only applied on iOS 26.1+; stale disable pref ignored)
  - [x] because of this issue there are numorus issues on the iphone that supports liquid glass
  - [x] also becasue of this add a setting that will attempt to force liquid glass (Appearance>Force Liquid Glass; restart required)
- [x] when pressing the 3 dots it shouldnt play the song it should just open the menu (song rows now keep the menu outside the play tap target)
- [x] when using the fallback ui the miniplayer will overlap the bottom tab bar (fallback miniplayer inset now lives inside each tab page)
- [x] fixed genre section search-bar jump by stabilizing the Library scroll height and search drawer prompt while switching filters
- [x] fixed album song-row scrolling while preserving Play Next swipe (stricter horizontal axis lock; vertical track-skip gesture moved into a narrow gutter after SwiftUI gesture/search drawer research)
- [x] fixed scrubber width spike after releasing a seek by removing implicit spring animation from the progress bar geometry
- [x] fixed legacy iOS miniplayer visibility with a material-backed fallback shell
- [x] fixed legacy iOS miniplayer overlap by moving the fallback bar to the tab root safe-area inset so pushed views like Settings are inset too
- [x] on legacy devices (pre iOS 26) the miniplayer overlaps the tab bar (legacy tabs now inset each tab page instead of overlaying the tab root)
- [x] still when swiping on a song to make it play next, it plays the song right away (TrackRow now uses a high-priority swipe gesture and suppresses the row tap after horizontal swipes)
- [x] when in a artists profile their name will jump up and down as the user scrolls, same with their profile picture (artist header scroll updates are pixel-aligned and animation-free)
- [x] when a song is skipped using Siri and AutoMix is on, manual/remote skips now suppress scheduled AutoMix briefly and reset transition plans/rates so the next track starts normally
- [x] there is now an exit animation when leaving Picks for You mixes/albums (Picks mix cards use the same zoom navigation source/destination path)
- [x] fixed remaining Picks for You album black bar by slightly overscanning square artwork crops
- [x] fixed pause not stopping audio by preventing transition cancellation from setting AVPlayer rate back to 1 while paused
- [x] Home hides cached Picks for You while offline/server-unreachable and shows a server-unreachable retry state pointing users to downloaded music
- [x] fixed saving a Search > Genre mix as a playlist by wiring the genre mix context menu into the shared playlist save flow
- [x] issue when the audio stops playing (because its forced via youtube or another audio focusing app is used) the play button in the app will remain saying playing instead of changing it to paused icon (AudioPlayer now observes AVAudioSession interruption notifications and updates isPlaying/Now Playing on begin/end)

### Audio Info & Metadata
- [x] tapping the Lossless badge opens a popover with format, bitrate, sample rate and bit depth
- [x] Lossless badge now shows Hi-Res Lossless for 24-bit+ tracks above 48 kHz up to 192 kHz, with True Hi-Res Lossless when output is verified
- [x] song detail sheet (Info) now shows bitrate, sample/bit, format, file size, server path and play count

### Artist & Library Enhancements
- [x] artist profile "Appeared On" section showing albums they're featured on (excludes their own discography)

### Gestures & Interaction Polish
- [x] swipe right on a song now queues it to play next (album/playlist/mix track rows)
- [x] still cannot make a song play next with swiping on songs make this doable while still allowing users to scroll on the songs (song rows now use an axis-locked right swipe that coexists with vertical scrolling)

### Performance
- [x] all animations and that should be vsync based (hot drag/scroll updates throttled to CADisplayLink; visual sleep-delays removed from player nudge)
- [x] fix issue when viewing artists profiles where the frame rate will be extremely low (artist header scroll updates throttled to vsync and profile images downsampled)
- [x] artist profile low-FPS pass tightened further with smaller header image decoding and ignored sub-pixel scroll updates
- [x] fixed artist profile FPS drop for artists with more than 9 albums by isolating scroll redraws to the header and caching sorted albums
- [x] fix issue when making player smaller the frame rate will be very low (player dismiss drag updates throttled to vsync)
- [x] frame-rate drops when opening/leaving settings, changing tabs fast, opening miniplayer to player, and switching library sections (disabled broad tab/source animations and tightened player/library transitions)

### UI
- [x] do slight redesign for the Picks for you section text panel uses album dominant color
- [x] on the login page allow http with a warning and a continue/edit choice
- [x] add a nicer fade/slide animation when lyrics switch state or song
- [x] add silent fallback for devices below iOS 26 (no setting; older systems use legacy tabs/material instead)
- [x] redesign the artist view (top songs) compact rows, Show All/Less toggle, up to 15 songs
- [x] add section near the bottom of each artist to include stats (albums, plays, years active, genres)
- [x] in the player dragging the progress bar makes it slightly larger (track grows 5>9pt while scrubbing)
- [x] dragging the progress bar no longer shows an oval/circle knob (removed thumb, bar grows instead)
- [x] accent colour has more effect (player scrubber fill uses accent + palette expanded to 9 colours)
- [x] show whether an album is Lossless/Lossy next to its year in the album header
- [x] hold down on an album (library grid + home rows) for an Apple-Music-style menu (play, shuffle, play next, add to queue, download, favourite) with an enlarged cover preview
- [x] download section messages now change based on the section (artists/albums/songs/genres) being viewed
- [x] progress bar (and volume bar) stay white regardless of accent colour
- [x] accent colour picker is now a horizontal swipable scroll of swatches
- [x] artist profile albums sorted newest>oldest
- [x] artist profile album covers all uniform size (fixed 130×130)
- [x] album view "Play" button made smaller (compact capsule)
- [x] separator added between the action row and first song (albums + playlists)
- [x] album/playlist track separators more defined (0.14 opacity)
- [x] mixes unified into the "Picks for You" row at the same card size, interleaved randomly (stable per day)
- [x] ArtistName / Genre mixes open like an album (new MixDetailView with play/shuffle + track list)
- [x] swipe left/right on the miniplayer to skip / go back, with a slide animation
- [x] swipe songs to queue next and swipe up/down inside albums, playlists, and smart playlists to move through tracks
- [x] "View Credits" now shows only creation data (performers, writing, production & engineering) via a dedicated credits sheet
- [x] removed the floating back button on album/playlist when opened from the library tab (swipe-back instead)
- [x] artist profile now has a true stretchy header pulling/scrolling zooms the photo and fills the gap so the background colour never shows behind it
- [x] cover-art thumbnails next to song names in mixes & playlists, with a Settings>Appearance toggle to disable
- [x] mix song rows now have Go to Album / Go to Artist in the 3-dot menu
- [x] add live artwork support animated cover art (GIF/APNG) plays in the full player only (miniplayer + lock screen keep the still frame; native lock-screen video isn't exposed by MediaPlayer). Toggle in Appearance>Live Artwork; original cover fetched (unscaled) so the server can't flatten the animation
- [x] add live artwork support for webp, also add lock screen support (uses WebP frame timing + MPMediaItemAnimatedArtwork video cache)
- [x] holding a Picks for You mix can save it as a new playlist
- [x] moved Home content up so the custom Home title/menu row sits higher
- [x] create notification suite and use it make them just like how the playing next ui looks (VoltaNotificationToast styles queue/success/info/warning/error with entrance bounce/glow)
- [x] notification previews and real notifications now appear from the same bottom toast host
- [x] when pressing "More" in artists profiles can you just make it so that a seperate ui pops up and shows the text (About sheet)
- [x] make the artists profile go all the way to the top of the screen (header extends under the status area)
- [x] light and AMOLED themes (Settings>Appearance>Theme: Dark / AMOLED / Light) `Theme` colours are now mode-driven and `preferredColorScheme` follows the choice; live switch via colorScheme (light) and a root rebuild (amoled)
- [x] within a album if the user presses the lossless badge (nexst the the year released) can you make it have a small insight on the album audio quality (tapping the badge opens an album-wide quality popover: format mix, sample rates, bit depths, hi-res track count)
- [x] allow users to view their password when signing in (put a button at the end of the password prompt) (eye/eye.slash toggle button toggles SecureField/TextField on the login password field)
- [x] added a Resume After Interruption setting (Settings>Playback) so users can choose whether playback auto-resumes once another app stops using audio (e.g. after a phone call or another app force-stops your music)
- [x] fixed bug where logging out while a song was playing left it playing in the background (logout now fully stops and clears the player — queue, now-playing info and audio session — so nothing remains playable after sign-out)
- [x] when exiting the app or turning off the phone the audio stops (added route-change observer that syncs isPlaying on headphone unplug; added stall observer that reactivates the session and re-calls player.play() so background streaming recovers after a brief network drop)
- [x] issue when using siri to skip a song the first N seconds of the song will be silent just like if automix was playing, when skipping using the next button this doesnt happen (startPlaying now calls setActive(true) before player.play() so the session is always live at the moment playback begins even when Siri interrupted it; the interruption-ended guard required rate==0 but a remote-command skip already set rate to 1 so the session was left inactive)
- [x] redesigned the album/player view for animated artworks so they look nicer

### Playlists
- [x] add the ability to edit playlists remove songs via 3-dot menu, delete playlist via long-press context menu
- [x] show the artist name under the song title in playlists (TrackRow showArtist)
- [x] add/edit playlist descriptions (pencil button>edit sheet) and pin playlists to the top of the playlists tab (long-press>Pin)
- [x] playlist detail action row now matches albums (shuffle circle · white Play · download)
- [x] smart playlist creation sheet now opens full-height so rule editing is not trapped in the compact UI
- [x] creating a server playlist, smart playlist, or playlist folder now warns when the same name already exists

### Performance & Battery
- [x] performance mode (Settings>Performance>Performance Mode): master switch plus per-feature override toggles (lighter artwork loading, disable live artwork, static player background, reduce animations, skip image prefetch, cap streaming quality, bypass audio effects). Overrides user settings at each read point via `PerformanceMode` without rewriting them; restored when off

### Audio Effects
- [x] mono audio toggle (Settings>Playback>Mono Audio, off by default) L+R downmix in the shared MTAudioProcessingTap
- [x] 3D spatial widener toggle (Settings>Playback) mid/side stereo widening in the same tap, clamped so it can't clip; mutually exclusive with mono
- [x] EQ tap now attaches whenever EQ, mono OR spatial is active (was EQ-only) and skips the EQ biquads when only mono/spatial are on

### Lyrics
- [x] download all lyrics (Settings>Storage>Download All Lyrics) bulk fetch with 12 concurrent requests, live progress bar + stop; already-downloaded songs resolve from disk
- [x] search by lyric Search now returns a "From Lyrics" section matching locally downloaded lyrics; tapping resolves the song via getSong and plays it

### Stats & Playlists Export
- [x] export stats (Stats tab>share button) writes play events as JSON + CSV and opens the share sheet
- [x] export/import playlists (Settings>Backups) exports all server playlists to portable JSON and recreates them on import (name, comment, ordered song ids)