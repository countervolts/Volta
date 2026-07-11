#if canImport(CarPlay)
import CarPlay
import UIKit
import Combine

@MainActor
final class CarPlayController: NSObject {
    static let shared = CarPlayController()
    private override init() { super.init() }

    // Cap rows so we don't fan out hundreds of artwork loads on connect; lists
    // are also truncated by the system while the car is in motion anyway.
    private static let maxRows = 80
    private static let listImageSize = 120

    private var interfaceController: CPInterfaceController?
    private var clientObserver: NSObjectProtocol?
    private var playerStateCancellable: AnyCancellable?

    // Root tab templates, kept so we can repopulate them in place when the
    // client connects/disconnects without rebuilding the whole tab bar.
    private var recentlyPlayedTemplate: CPListTemplate?
    private var playlistsTemplate: CPListTemplate?
    private var albumsTemplate: CPListTemplate?
    private var artistsTemplate: CPListTemplate?

    private var client: (any MusicService)? { IntentBridge.shared.client }
    private var audioPlayer: AudioPlayer? { IntentBridge.shared.audioPlayer }

    // MARK: - Scene lifecycle

    func connect(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        buildRootTabBar()
        observeClientChanges()
        CPNowPlayingTemplate.shared.add(self)
        // Launched straight into CarPlay (phone window never opened)? Kick off the
        // same session restore the SwiftUI root view normally performs.
        if AppState.shared.phase == .loading {
            AppState.shared.restoreSession()
        }
        reloadAll()
        startObservingPlayerState()
        AppLogger.shared.log("CarPlay connected", category: .other)
    }

    func disconnect() {
        if let clientObserver {
            NotificationCenter.default.removeObserver(clientObserver)
        }
        clientObserver = nil
        CPNowPlayingTemplate.shared.remove(self)
        playerStateCancellable?.cancel()
        playerStateCancellable = nil
        interfaceController = nil
        recentlyPlayedTemplate = nil
        playlistsTemplate = nil
        albumsTemplate = nil
        artistsTemplate = nil
        AppLogger.shared.log("CarPlay disconnected", category: .other)
    }

    private func observeClientChanges() {
        guard clientObserver == nil else { return }
        clientObserver = NotificationCenter.default.addObserver(
            forName: IntentBridge.clientDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadAll()
                // The live player only exists once signed in; (re)arm now.
                self?.startObservingPlayerState()
            }
        }
    }

    // MARK: - Root

    private func buildRootTabBar() {
        let recent = CPListTemplate(title: L(.home_recently_played), sections: [])
        recent.tabTitle = L(.home_recently_played)
        recent.tabImage = UIImage(systemName: "clock")

        let playlists = CPListTemplate(title: L(.tab_playlists), sections: [])
        playlists.tabTitle = L(.tab_playlists)
        playlists.tabImage = UIImage(systemName: "music.note.list")

        let albums = CPListTemplate(title: L(.home_recently_added), sections: [])
        albums.tabTitle = L(.home_recently_added)
        albums.tabImage = UIImage(systemName: "square.stack")

        let artists = CPListTemplate(title: L(.home_artists), sections: [])
        artists.tabTitle = L(.home_artists)
        artists.tabImage = UIImage(systemName: "music.mic")

        recentlyPlayedTemplate = recent
        playlistsTemplate = playlists
        albumsTemplate = albums
        artistsTemplate = artists

        let tabBar = CPTabBarTemplate(templates: [recent, playlists, albums, artists])
        interfaceController?.setRootTemplate(tabBar, animated: false, completion: nil)
    }

    // Refresh every root tab. Shows a sign-in / loading placeholder until the
    // client is live, then fills each list from the server.
    private func reloadAll() {
        guard interfaceController != nil else { return }

        guard let client else {
            let placeholder = AppState.shared.phase == .login
                ? messageSection("Open Volta on your iPhone to sign in")
                : messageSection("Loading…")
            recentlyPlayedTemplate?.updateSections([placeholder])
            playlistsTemplate?.updateSections([placeholder])
            albumsTemplate?.updateSections([placeholder])
            artistsTemplate?.updateSections([placeholder])
            return
        }

        recentlyPlayedTemplate?.updateSections([loadingSection()])
        playlistsTemplate?.updateSections([loadingSection()])
        albumsTemplate?.updateSections([loadingSection()])
        artistsTemplate?.updateSections([loadingSection()])

        loadAlbums(into: recentlyPlayedTemplate) {
            (try? await client.recentlyPlayedAlbums(size: Self.maxRows)) ?? []
        }
        loadAlbums(into: albumsTemplate) {
            (try? await client.newestAlbums(size: Self.maxRows)) ?? []
        }
        load(into: playlistsTemplate) { [weak self] in
            let playlists = Array(((try? await client.playlists()) ?? []).prefix(Self.maxRows))
            return self?.playlistItems(playlists) ?? []
        }
        load(into: artistsTemplate) { [weak self] in
            let artists = Array(((try? await client.artists()) ?? []).prefix(Self.maxRows))
            return self?.artistItems(artists) ?? []
        }
    }

    // MARK: - Async list population

    // Generic: run a loader, then swap the template's single section for the result (or an empty-state row).
    private func load(into template: CPListTemplate?, _ loader: @escaping () async -> [CPListItem]) {
        guard let template else { return }
        Task { @MainActor in
            let items = await loader()
            guard self.interfaceController != nil else { return }
            template.updateSections(items.isEmpty ? [self.emptySection()] : [CPListSection(items: items)])
        }
    }

    private func loadAlbums(into template: CPListTemplate?, _ loader: @escaping () async -> [Album]) {
        load(into: template) { [weak self] in
            let albums = HiddenAlbumStore.shared.visibleAlbums(await loader())
            return self?.albumItems(Array(albums.prefix(Self.maxRows))) ?? []
        }
    }

    // Push a fresh list that shows a spinner row, then fills it once loaded.
    private func pushList(title: String, _ loader: @escaping () async -> [CPListItem]) {
        let template = CPListTemplate(title: title, sections: [loadingSection()])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
        Task { @MainActor in
            let items = await loader()
            guard self.interfaceController != nil else { return }
            template.updateSections(items.isEmpty ? [self.emptySection()] : [CPListSection(items: items)])
        }
    }

    // MARK: - Item builders

    private func albumItems(_ albums: [Album]) -> [CPListItem] {
        albums.map { album in
            let item = CPListItem(text: album.name, detailText: album.displayArtist)
            item.accessoryType = .disclosureIndicator
            setImage(on: item, coverArt: album.coverArt, placeholder: "square.stack")
            item.handler = { [weak self] _, completion in
                self?.openAlbum(album)
                completion()
            }
            return item
        }
    }

    private func artistItems(_ artists: [Artist]) -> [CPListItem] {
        artists.map { artist in
            let item = CPListItem(text: artist.name, detailText: nil)
            item.accessoryType = .disclosureIndicator
            setImage(on: item, coverArt: artist.coverArt, placeholder: "music.mic")
            item.handler = { [weak self] _, completion in
                self?.openArtist(artist)
                completion()
            }
            return item
        }
    }

    private func playlistItems(_ playlists: [Playlist]) -> [CPListItem] {
        playlists.map { playlist in
            let count = playlist.songCount ?? playlist.entry?.count ?? 0
            let item = CPListItem(text: playlist.name, detailText: L(.home_song_count, count))
            item.accessoryType = .disclosureIndicator
            setImage(on: item, coverArt: playlist.coverArt, placeholder: "music.note.list")
            item.handler = { [weak self] _, completion in
                self?.openPlaylist(playlist)
                completion()
            }
            return item
        }
    }

    // Songs are leaf rows: tapping one starts the whole list from that point.
    private func songItems(_ songs: [Song], source: String, album: Album?, playlist: Playlist?) -> [CPListItem] {
        songs.enumerated().map { index, song in
            let item = CPListItem(text: song.title, detailText: song.artist)
            setImage(on: item, coverArt: song.coverArt, placeholder: "music.note")
            item.handler = { [weak self] _, completion in
                self?.play(songs, startIndex: index, source: source, album: album, playlist: playlist)
                completion()
            }
            return item
        }
    }

    // MARK: - Drill-down

    private func openAlbum(_ album: Album) {
        pushList(title: album.name) { [weak self] in
            guard let self, let client = self.client else { return [] }
            let full = (try? await client.album(id: album.id)) ?? album
            let songs = HiddenAlbumStore.shared.visibleSongs(full.song ?? [])
            return self.songItems(songs, source: album.name, album: full, playlist: nil)
        }
    }

    private func openArtist(_ artist: Artist) {
        pushList(title: artist.name) { [weak self] in
            guard let self, let client = self.client else { return [] }
            let full = (try? await client.artist(id: artist.id)) ?? artist
            let albums = HiddenAlbumStore.shared.visibleAlbums(full.album ?? [])
            return self.albumItems(albums)
        }
    }

    private func openPlaylist(_ playlist: Playlist) {
        pushList(title: playlist.name) { [weak self] in
            guard let self, let client = self.client else { return [] }
            let full = (try? await client.playlist(id: playlist.id)) ?? playlist
            let songs = HiddenAlbumStore.shared.visibleSongs(full.entry ?? [])
            return self.songItems(songs, source: playlist.name, album: nil, playlist: full)
        }
    }

    // MARK: - Playback

    private func play(_ songs: [Song], startIndex: Int, source: String, album: Album?, playlist: Playlist?) {
        guard let audioPlayer, songs.indices.contains(startIndex) else { return }
        audioPlayer.playQueue(songs, startIndex: startIndex, source: source, album: album, playlist: playlist)
        pushNowPlaying()
    }

    private func pushNowPlaying() {
        guard let interfaceController else { return }
        let nowPlaying = CPNowPlayingTemplate.shared
        refreshNowPlayingConfig()
        guard interfaceController.topTemplate !== nowPlaying else { return }
        interfaceController.pushTemplate(nowPlaying, animated: true, completion: nil)
    }

    // MARK: - Now Playing buttons + live state

    // Rebuild the shuffle / repeat / favorite buttons and the Up Next toggle so
    // they reflect the current player state. The CPNowPlayingButton handlers map
    // straight onto the same AudioPlayer actions the in-app player uses.
    private func refreshNowPlayingConfig() {
        let template = CPNowPlayingTemplate.shared
        guard let audioPlayer else {
            template.isUpNextButtonEnabled = false
            template.updateNowPlayingButtons([])
            return
        }
        template.isUpNextButtonEnabled = !audioPlayer.queue.isEmpty

        var buttons: [CPNowPlayingButton] = []

        // Shuffle (on / off)
        if let image = UIImage(systemName: audioPlayer.isShuffle ? "shuffle.circle.fill" : "shuffle") {
            buttons.append(CPNowPlayingImageButton(image: image) { _ in
                Task { @MainActor in IntentBridge.shared.audioPlayer?.toggleShuffle() }
            })
        }

        // Repeat (off / all / one)
        let repeatSymbol: String
        switch audioPlayer.repeatMode {
        case .off: repeatSymbol = "repeat"
        case .all: repeatSymbol = "repeat.circle.fill"
        case .one: repeatSymbol = "repeat.1.circle.fill"
        }
        if let image = UIImage(systemName: repeatSymbol) {
            buttons.append(CPNowPlayingImageButton(image: image) { _ in
                Task { @MainActor in IntentBridge.shared.audioPlayer?.cycleRepeat() }
            })
        }

        // Favorite (starred) for the current song
        if let song = audioPlayer.currentSong {
            let symbol = audioPlayer.isStarred(song.id) ? "heart.fill" : "heart"
            if let image = UIImage(systemName: symbol) {
                buttons.append(CPNowPlayingImageButton(image: image) { _ in
                    Task { @MainActor in IntentBridge.shared.audioPlayer?.toggleStar(songID: song.id) }
                })
            }
        }

        template.updateNowPlayingButtons(buttons)
    }

    // Start a fresh observation chain that refreshes the buttons whenever the
    // relevant player state changes (from CarPlay, the phone, or autoplay).
    private func startObservingPlayerState() {
        playerStateCancellable?.cancel()
        playerStateCancellable = nil
        guard interfaceController != nil else { return }
        refreshNowPlayingConfig()
        playerStateCancellable = audioPlayer?.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    Task { @MainActor in self?.refreshNowPlayingConfig() }
                }
            }
    }

    // MARK: - Helpers

    private func setImage(on item: CPListItem, coverArt: String?, placeholder: String) {
        item.setImage(UIImage(systemName: placeholder))
        guard let coverArt, let url = client?.coverArtURL(id: coverArt, size: Self.listImageSize) else { return }
        Task { @MainActor in
            if let image = await ArtworkLoader.shared.image(for: url, maxPixelSize: Self.listImageSize) {
                item.setImage(image)
            }
        }
    }

    private func loadingSection() -> CPListSection {
        messageSection("Loading…")
    }

    private func emptySection() -> CPListSection {
        messageSection(L(.home_nothing_here))
    }

    private func messageSection(_ text: String) -> CPListSection {
        CPListSection(items: [CPListItem(text: text, detailText: nil)])
    }
}

// MARK: - Now Playing observer (Up Next / album-artist)

extension CarPlayController: @MainActor CPNowPlayingTemplateObserver {
    // Tapping "Up Next" pushes the upcoming queue; selecting a row jumps to it.
    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        guard let audioPlayer else { return }
        let queue = audioPlayer.queue
        let current = audioPlayer.currentIndex
        let items: [CPListItem] = queue.enumerated().compactMap { index, song in
            guard index > current else { return nil }
            let item = CPListItem(text: song.title, detailText: song.artist)
            setImage(on: item, coverArt: song.coverArt, placeholder: "music.note")
            item.handler = { _, completion in
                Task { @MainActor in IntentBridge.shared.audioPlayer?.skipTo(index: index) }
                completion()
            }
            return item
        }
        let section = items.isEmpty ? messageSection("Nothing queued") : CPListSection(items: items)
        let list = CPListTemplate(title: "Up Next", sections: [section])
        interfaceController?.pushTemplate(list, animated: true, completion: nil)
    }

    // The album-artist button stays disabled (no rich offline navigation target),
    // but the observer method is required by the protocol.
    func nowPlayingTemplateAlbumArtistButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {}
}
#endif
