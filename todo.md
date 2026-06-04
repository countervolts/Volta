stuff that needs to be done

## done

### Player & Playback
- [x] make it so that the tab bar miniplayer doenst have a forward button
- [x] make the tab bar miniplayer also include the artist name
- [x] when pressing the album cover from the queue view make it so it will expand the cover (just like how the lyric one works) queue/lyrics now fill the artwork area; tapping artwork tab returns to now playing
- [x] show the progress bar of the song when viewing the lyrics and queue mini progress bar above controls; full scrubber visible when switching back to now playing
- [x] make the AutoPlay function work, when running out of songs in the queue add random songs from the users library and play them (queue cycles Off → AutoPlay → Algorithm → Off)
- [x] add the ability to rearrange the queue (drag handle on right side, move up or down)
- [x] add the ability to swipe right on a song to make it play next in the queue
- [x] add gapless playback (off/weak/on) weak=pre-buffer, on=AVQueuePlayer seamless
- [x] improved algorithmic infinite play (artist-scoped → similar-artist → random fallback chain)
- [x] move the progress bar (when in lyric and queue view) to right above the control buttons
- [x] make it so that when pressing the album cover in the player view when looking at the queue does the same thing as pressing it when in the lyric view both now live in the same layout, tapping the queue/lyrics tab icon switches back
- [x] ensure support for all audio file types
- [x] tapping a synced lyric line seeks to that point in the song (tap any line in synced lyrics view)
- [x] sleep timer (moon button in player bottom bar: 5/15/30/45/60 min or end of track)
- [x] volume normalization / ReplayGain (Settings → Playback → Volume Normalization: off/track/album, peak-protected)
- [x] share button on now playing 3-dot + song 3-dot menus via Songlink/Odesli-style public pages
- [x] artist profile Play plays the full discography in album order; Shuffle shuffles all artist songs
- [x] album about text and playlist descriptions show below the action row with More/Less expansion
- [x] lyric translation button uses Apple's Translation framework on supported iOS versions
- [x] volume slider supports tap or drag from anywhere on the bar

### Library & Navigation
- [x] fix song view in the library tab because currently it shows nothing
- [x] when pressing a artist name in the playback view make it open that artists profile
- [x] when pressing a artist in the artists section of the library make it open the profile
- [x] add downloaded section in the library tab
- [x] scrolling down in library hides the search bar for more space (single ScrollView so nav search field collapses)
- [x] play button on the artist profile (Play + Shuffle); autoplay scoped to that artist so it keeps playing them
- [x] filtering within library sections — sort (Name/Year/Most Played/Recently Added) + genre filter + Never Played toggle (filter menu on albums/songs)
- [x] custom daily mixes ("Genre Mix" / "Artist Mix") generated from the library, shown in Picks for You, rotate each day (seeded RNG), 20–50 songs each
- [x] add folder/directory browsing in the library tab — new "Folders" filter backed by getMusicFolders / getIndexes / getMusicDirectory, drill into directories, Play/Shuffle a directory, multi-folder picker, search-filtered
- [x] add multi-select mode — long-press a song in the Library Songs list to enter selection, tap to multi-select, floating bar to batch Play Next / Queue / Add to Playlist / Download, Select All + count
- [x] share actions now resolve to Songlink/Odesli-style links instead of Navidrome server shares
- [x] Picks for You includes daily Discovery Station and Heavy Rotation mixes
- [x] smart playlists can be pinned to the top
- [x] holding an album includes a View Stats option
- [x] smart playlist creation has searchable multi-select pickers for artists and albums plus clearer rule summaries
- [x] Library Songs has Album sorting plus Play and Shuffle controls
- [x] genre grids can be left with the normal swipe-back gesture

### Search & History
- [x] show previous search results when using the search feature
- [x] search includes matching genres

### Downloads
- [x] when using the download feature show a download circle progress next to each song of the album or playlist to show how much of each song is downloaded
- [x] download progress circle now accurate (downloads use a download-specific URL honouring download bitrate, so size matches and progress isn't skewed by streaming transcode)
- [x] download storage cap setting + auto-evict least-recently-played downloads when over the limit (toggle on/off)
- [x] limit download speeds setting

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
- [x] custom 10-band graphic equalizer (Settings → Playback → Equalizer): enable toggle, presets, per-band ±12 dB sliders, applied globally via MTAudioProcessingTap
- [x] add feature for url switching when on data vs wifi — optional per-server Cellular URL (Edit Connection), auto-switches the client base URL via NWPathMonitor; also wired the previously-dead Cellular Quality streaming setting
- [x] local artwork library download is faster and shows an estimated total size
- [x] custom accent colour picker works through the app theme
- [x] storage shows logged play events size
- [x] storage shows logs size
- [x] verbose logs can be filtered by level and sorted newest/oldest

### Bugs & Fixes
- [x] fix error in stats where it will say avg play for 700,000 days instead of the amount of days the app was installed
- [x] fix bug where the 3 dots in the Top Songs does nothing
- [x] fix bug where similar artists within artist profile (when pressed) wont open anything
- [x] fix bug where pressing 3 dots in the top songs for artists plays it, also fix how that ui works restructured to onTapGesture so 3-dots button is fully isolated
- [x] when scrolling down with no music playing it will still do animation to hide the miniplayer tab bar only minimizes on scroll when music is playing
- [x] when scrolling up instead of just going past the profile picture it should start to close it scroll offset detection, overscroll > 60pt triggers dismiss
- [x] fix progress bar going PAST the total bar (progress clamped to 0...1, fill width capped to track width)
- [x] fix foreground progress bar detaching when moving player up/down (fg+bg share one geometry/origin)
- [x] fix accent colour picker showing all purple circles (custom Circle swatch row instead of tinted SF Symbols)
- [x] tapping the Lossless badge opens a popover with format, bitrate, sample rate and bit depth
- [x] song detail sheet (Info) now shows bitrate, sample/bit, format, file size, server path and play count
- [x] artist profile no longer flashes an album cover as the profile picture before the real photo loads (waits for artwork lookup)
- [x] artist profile "Appeared On" section showing albums they're featured on (excludes their own discography)
- [x] albums opened from an artist profile can be closed like home-tab albums (added GlassBackButton to AlbumDetailView)
- [x] fix Picks for You album cover off-centred / black bar (artwork now fills full card width)
- [x] fix stats counting "Artist1, Artist2" feature credits as their own artist (top artists grouped by primary/lead artist)
- [x] removed the Disable Liquid Glass setting (glass always on; fixed rendering bug)
- [x] genre no longer appears twice on the artist profile (only in Stats now)
- [x] swipe right on a song now queues it to play next (album/playlist/mix track rows)
- [x] pencil button works again — playlist sheets consolidated into one enum-driven sheet
- [x] artist photo shows immediately now (resolved earlier + cached, no longer waits for "More")
- [x] fixed crash when long-pressing an album cover (ArtworkView no longer force-reads the app environment inside context-menu previews)
- [x] artist profile photo appears as soon as it loads now (mirrored into view @State so the body re-renders without interaction)
- [x] fixed the black bar on the side of some Picks for You covers (artwork forced to a true 1:1 square)
- [x] fixed the intermittent Picks for You black bar in both pick cards and mix cards
- [x] miniplayer swipe no longer also opens the player (highPriorityGesture), fixing the stuck open/close state afterwards
- [x] fixed the library `.searchable` bar bleeding into the artist profile (toolbar hidden on artist detail)
- [x] foreground progress bar no longer detaches from the track (fill anchored inside the track via overlay)
- [x] View Credits no longer shows the composer twice (deduped + composer-role suppressed when displayComposer present)
- [x] hold-album preview now renders in place (same root cause as the crash — ArtworkView no longer needs the app env)
- [x] fix ui bug when leaving an album then scrolling detaches the album cover — gated the swipe-back pop gesture (no longer fires mid-zoom-transition or simultaneously with the scroll pan) which was orphaning the zoom source snapshot
- [x] all animations and that should be vsync based (hot drag/scroll updates throttled to CADisplayLink; visual sleep-delays removed from player nudge)
- [x] fix issue when viewing artists profiles where the frame rate will be extremely low (artist header scroll updates throttled to vsync and profile images downsampled)
- [x] artist profile low-FPS pass tightened further with smaller header image decoding and ignored sub-pixel scroll updates
- [x] fix issue when making player smaller the frame rate will be very low (player dismiss drag updates throttled to vsync)
- [x] fix the search bar on artists in the library tab again to just be exactly like how it works on albums/genres (artist rows use native NavigationLink push)
- [x] when using airpods and going next at the end of a album while using autoplay or algorithm it will just repeat the same song (autoplay/algorithm now preloads before queue end so remote next advances)

### UI
- [x] do slight redesign for the Picks for you section text panel uses album dominant color
- [x] on the login page allow http with a warning and a continue/edit choice
- [x] add a nicer fade/slide animation when lyrics switch state or song
- [x] add silent fallback for devices below iOS 26 (no setting; older systems use legacy tabs/material instead)
- [x] redesign the artist view (top songs) compact rows, Show All/Less toggle, up to 15 songs
- [x] add section near the bottom of each artist to include stats (albums, plays, years active, genres)
- [x] in the player dragging the progress bar makes it slightly larger (track grows 5→9pt while scrubbing)
- [x] dragging the progress bar no longer shows an oval/circle knob (removed thumb, bar grows instead)
- [x] accent colour has more effect (player scrubber fill uses accent + palette expanded to 9 colours)
- [x] show whether an album is Lossless/Lossy next to its year in the album header
- [x] hold down on an album (library grid + home rows) for an Apple-Music-style menu (play, shuffle, play next, add to queue, download, favourite) with an enlarged cover preview
- [x] download section messages now change based on the section (artists/albums/songs/genres) being viewed
- [x] progress bar (and volume bar) stay white regardless of accent colour
- [x] accent colour picker is now a horizontal swipable scroll of swatches
- [x] artist profile albums sorted newest → oldest
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
- [x] artist profile now has a true stretchy header — pulling/scrolling zooms the photo and fills the gap so the background colour never shows behind it
- [x] cover-art thumbnails next to song names in mixes & playlists, with a Settings → Appearance toggle to disable
- [x] mix song rows now have Go to Album / Go to Artist in the 3-dot menu
- [x] add live artwork support — animated cover art (GIF/APNG) plays in the full player only (miniplayer + lock screen keep the still frame; native lock-screen video isn't exposed by MediaPlayer). Toggle in Appearance → Live Artwork; original cover fetched (unscaled) so the server can't flatten the animation
- [x] add live artwork support for webp, also add lock screen support (uses WebP frame timing + MPMediaItemAnimatedArtwork video cache)

### Playlists
- [x] add the ability to edit playlists remove songs via 3-dot menu, delete playlist via long-press context menu
- [x] show the artist name under the song title in playlists (TrackRow showArtist)
- [x] add/edit playlist descriptions (pencil button → edit sheet) and pin playlists to the top of the playlists tab (long-press → Pin)
- [x] playlist detail action row now matches albums (shuffle circle · white Play · download)
