stuff that needs to be done

## done

### Player & Playback
- [x] make it so that the tab bar miniplayer doenst have a forward button
- [x] make the tab bar miniplayer also include the artist name
- [x] when pressing the album cover from the queue view make it so it will expand the cover (just like how the lyric one works) — queue/lyrics now fill the artwork area; tapping artwork tab returns to now playing
- [x] show the progress bar of the song when viewing the lyrics and queue — mini progress bar above controls; full scrubber visible when switching back to now playing
- [x] make the AutoPlay function work, when running out of songs in the queue add random songs from the users library and play them (queue cycles Off → AutoPlay → Algorithm → Off)
- [x] add the ability to rearrange the queue (drag handle on right side, move up or down)
- [x] add the ability to swipe right on a song to make it play next in the queue
- [x] add gapless playback (off/weak/on) — weak=pre-buffer, on=AVQueuePlayer seamless
- [x] move the progress bar (when in lyric and queue view) to right above the control buttons
- [x] make it so that when pressing the album cover in the player view when looking at the queue does the same thing as pressing it when in the lyric view — both now live in the same layout, tapping the queue/lyrics tab icon switches back
- [x] ensure support for all audio file types

### Library & Navigation
- [x] fix song view in the library tab because currently it shows nothing
- [x] when pressing a artist name in the playback view make it open that artists profile
- [x] when pressing a artist in the artists section of the library make it open the profile
- [x] add downloaded section in the library tab

### Search & History
- [x] show previous search results when using the search feature

### Downloads
- [x] when using the download feature show a download circle progress next to each song of the album or playlist to show how much of each song is downloaded

### Settings & Integration
- [x] remove "Show Explicit Content" setting
- [x] export all logs button — bundles all logs into zip, shares to Files app
- [x] add setting for transcoding format (mp3/aac/opus/original)
- [x] add setting for changing the streaming quality on wifi and data separately
- [x] add settings for app appearance (lossless badge, dynamic background, accent color)
- [x] add setting (and functionality) to cache data on device — downloaded section + gapless pre-buffer
- [x] add section to view server/music info — artists, albums, total songs, total duration, streaming speed test with grade
- [x] allow searching in settings
- [x] make it so that 3 dot uis have much more things: play, play next, add to queue, add to playlist
- [x] add the option in settings to save/edit the server login information (url, username, password via Edit Connection view)
- [x] have better siri integration — play artist/song/album/playlist, pause, resume, skip (multiple phrase variants each)
- [x] show total songs and total amount of music (in days/hours/minutes) in settings

### Bugs & Fixes
- [x] fix error in stats where it will say avg play for 700,000 days instead of the amount of days the app was installed
- [x] fix bug where the 3 dots in the Top Songs does nothing
- [x] fix bug where similar artists within artist profile (when pressed) wont open anything
- [x] fix bug where pressing 3 dots in the top songs for artists plays it, also fix how that ui works — restructured to onTapGesture so 3-dots button is fully isolated
- [x] when scrolling down with no music playing it will still do animation to hide the miniplayer — tab bar only minimizes on scroll when music is playing
- [x] when scrolling up instead of just going past the profile picture it should start to close it — scroll offset detection, overscroll > 60pt triggers dismiss

### UI
- [x] do slight redesign for the Picks for you section — text panel uses album dominant color
- [x] redesign the artist view (top songs) — compact rows, Show All/Less toggle, up to 15 songs
- [x] add section near the bottom of each artist to include stats (albums, plays, years active, genres)

### Playlists
- [x] add the ability to edit playlists — remove songs via 3-dot menu, delete playlist via long-press context menu

## not done

### Player & Playback
- [ ] add algorithmic infinite play method (basic version with similar artists implemented — can be improved further)

