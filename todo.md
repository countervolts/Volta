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
- [x] move the progress bar (when in lyric and queue view) to right above the control buttons
- [x] make it so that when pressing the album cover in the player view when looking at the queue does the same thing as pressing it when in the lyric view both now live in the same layout, tapping the queue/lyrics tab icon switches back
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

### Bugs & Fixes
- [x] fix error in stats where it will say avg play for 700,000 days instead of the amount of days the app was installed
- [x] fix bug where the 3 dots in the Top Songs does nothing
- [x] fix bug where similar artists within artist profile (when pressed) wont open anything
- [x] fix bug where pressing 3 dots in the top songs for artists plays it, also fix how that ui works restructured to onTapGesture so 3-dots button is fully isolated
- [x] when scrolling down with no music playing it will still do animation to hide the miniplayer tab bar only minimizes on scroll when music is playing
- [x] when scrolling up instead of just going past the profile picture it should start to close it scroll offset detection, overscroll > 60pt triggers dismiss

### UI
- [x] do slight redesign for the Picks for you section text panel uses album dominant color
- [x] redesign the artist view (top songs) compact rows, Show All/Less toggle, up to 15 songs
- [x] add section near the bottom of each artist to include stats (albums, plays, years active, genres)

### Playlists
- [x] add the ability to edit playlists remove songs via 3-dot menu, delete playlist via long-press context menu

## not done

### Ui & Design
- [ ] make it so that when scrolling upwards in artist view it will effectively zoom into the artists profile picture
- [ ] when viewing a profile for the it will show a album/song cover as the profile picture before the artists proper one
- [ ] in the player make it so when dragging the progress bar it will become slightly larger
- [ ] in player make it so that dragging the progress bar doesnt make a oval/circle to appear at the end 
- [ ] make accent colours have more of a effect changing more colours other than just toggles
- [ ] when in the download section of the library make the messages change based off the section the user is looking at 
- [ ] when in library make it so that scrolling down will hide the search bar therfor making there be more space for showing the data
- [ ] add the ability to hold down on albums and do things to them (play, shuffle, add to a playlist, play next, download, favourite) it should expand and make the album cover larger and still showing the album name and artist name (just like apple music)
- [ ] add live artwork support animated/video artwork shown in the full player and on the lock screen, not the miniplayer

### Player & Playback
- [ ] add algorithmic infinite play method (basic version with similar artists implemented can be improved further)
- [ ] add custom made playlists playlists like "GenreName Mix" and like "ArtistName Mix" this should appear in the "Picks for You" section of the home tab
- [ ] add a sleep timer stop playback after X minutes or at the end of the current song, accessible from the now playing screen
- [ ] add volume normalization / ReplayGain support the replayGain data is already on the Song model just needs to be applied to the player
- [ ] tapping a synced lyric line should seek to that point in the song
- [ ] add a share button to the now playing screen and 3-dot menus for a public share link using the subsonic createShare endpoint only show the button if the server returns a valid link, hide it entirely if not

### Library & Navigation
- [ ] add folder/directory browsing in the library tab useful for servers where metadata is messy
- [ ] add filtering within library sections filter albums or songs by genre, year, never played, etc
- [ ] song detail sheet tapping info on a song should show a sheet with its bitrate, format, file size, server path, and play count (all already in the Song model)
- [ ] add a play button on the artist profile page to immediately play that artists music autoplay should also be scoped to that artist so it keeps playing them
- [ ] add multi-select mode long press a song to enter it, then select multiple songs to batch add to queue, playlist, or download

### Bugs & fixes
- [ ] fix weird bug where the progress bar wont always reflect the proper time (explaination, if a song lasts 2:30 not sure why but sometimes the lenght (according to the time left timer) and because of this the forground progress bar will go PAST the background total progress bar)
- [ ] fix bug still with the forground progress bar where when moving the player up and down the forground progress bar will become detached from the background total progress bar
- [ ] bug? fix issue where in settings under accent colour when picking a colour all the circles are purple instead of being what it says next to them
- [ ] bug where sometimes the album cover will be off centered in the Picks for You section leading to there being a black bar on the right side
- [ ] fix ui bug when leaving a album then scrolling up or down it will cause the album cover to be detached and move with the scrolling 
- [ ] fix a issue with downloading that the download circle next to the song it wont be 100% accurate 

### Downloads
- [ ] add a download storage cap setting set a max size and auto-evict least-recently-played downloads when the limit is hit (let the user toggle on/off auto evict)

### Settings & Integration
- [ ] allow swipe to exit settings currently doesnt work currently and user needs to use the back button
- [ ] add feature for url switching when on data vs wifi
- [ ] add spotlight integration index songs, albums, and artists via CoreSpotlight so they show up in iOS search
- [ ] add a custom equalizer in settings let the user set their own band levels, saved and applied globally to playback