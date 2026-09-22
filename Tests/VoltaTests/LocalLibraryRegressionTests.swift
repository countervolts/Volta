import Foundation
import XCTest

@testable import Volta

final class LocalLibraryRegressionTests: XCTestCase {
    func testRootDirectoryReturnsSongsAndFoldersWithoutFakeSongFolders() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeAudio("root song.mp3", in: root)
        try writeAudio("Beyoncé/Album/track.flac", in: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Empty"), withIntermediateDirectories: true)

        let service = try await LocalMusicService.make(rootURL: root, libraryID: "root-browser")
        let rootEntries = try await service.indexes(musicFolderId: nil)

        XCTAssertEqual(rootEntries.filter(\.isDirectory).map(\.name), ["Beyoncé", "Empty"])
        XCTAssertEqual(rootEntries.filter { !$0.isDirectory }.map(\.name), ["root song"])
        XCTAssertFalse(rootEntries.contains { $0.isDirectory && $0.name == "root song.mp3" })

        let artistID = try XCTUnwrap(rootEntries.first(where: { $0.name == "Beyoncé" })?.id)
        let artistEntries = try await service.musicDirectory(id: artistID)
        XCTAssertEqual(artistEntries.filter(\.isDirectory).map(\.name), ["Album"])
    }

    func testDuplicateArtworkStemDoesNotTrapAndUsesDeterministicSelection() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeAudio("Artist/Album/track.mp3", in: root)
        let album = root.appendingPathComponent("Artist/Album")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: album.appendingPathComponent("cover.png"))
        try Data([0xFF, 0xD8, 0xFF]).write(to: album.appendingPathComponent("cover.jpg"))

        let service = try await LocalMusicService.make(rootURL: root, libraryID: "artwork-stems")
        let songs = try await service.randomSongs(size: 1)
        let song = try XCTUnwrap(songs.first)

        XCTAssertNotNil(song.coverArt)
        XCTAssertNotNil(service.coverArtURL(id: song.coverArt, size: nil))
    }

    func testLibraryIdentitySeparatesIdenticalRelativePathsAndLyricsUseSongID() async throws {
        let firstRoot = try temporaryDirectory()
        let secondRoot = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        try writeAudio("Artist/Album/01.mp3", in: firstRoot)
        try writeAudio("Artist/Album/01.mp3", in: secondRoot)
        let lyricsURL = firstRoot.appendingPathComponent("Artist/Album/01.lrc")
        try "[00:01.00]Hello 世界".write(to: lyricsURL, atomically: true, encoding: .utf8)

        let first = try await LocalMusicService.make(rootURL: firstRoot, libraryID: "library-a")
        let second = try await LocalMusicService.make(rootURL: secondRoot, libraryID: "library-b")
        let firstSongs = try await first.randomSongs(size: 1)
        let secondSongs = try await second.randomSongs(size: 1)
        let firstSong = try XCTUnwrap(firstSongs.first)
        let secondSong = try XCTUnwrap(secondSongs.first)

        XCTAssertNotEqual(firstSong.id, secondSong.id)
        XCTAssertNotEqual(firstSong.albumId, secondSong.albumId)
        let loadedLyrics = try await first.lyricsBySongId(id: firstSong.id)
        let lyrics = try XCTUnwrap(loadedLyrics)
        XCTAssertEqual(LyricsService.displayLines(from: lyrics)?.first?.text, "Hello 世界")
    }

    func testAppleMusicNormalizationAndStorefrontAreUnicodeAndRegionSafe() throws {
        XCTAssertEqual(AppleMusicLinkService.normalized("Beyoncé — 東京の夜!"), "beyonce 東京の夜")
        XCTAssertEqual(AppleMusicLinkService.normalized("Привет, мир"), "привет мир")
        XCTAssertEqual(AppleMusicLinkService.normalized("한국어·中文"), "한국어 中文")
        XCTAssertEqual(AppleMusicLinkService.storefront(for: Locale(identifier: "en_CA")), "ca")
        XCTAssertEqual(AppleMusicLinkService.storefront(for: Locale(identifier: "en_US")), "us")
        XCTAssertEqual(AppleMusicLinkService.storefront(for: Locale(identifier: "en_GB")), "gb")
        XCTAssertEqual(AppleMusicLinkService.storefront(for: Locale(identifier: "ja_JP")), "jp")
        XCTAssertTrue(AppleMusicLinkService.searchURL(term: "東京", locale: Locale(identifier: "en_CA"))?.absoluteString.contains("music.apple.com/ca/search") == true)
        XCTAssertFalse(AppleMusicLinkService.songCandidateIsConfident(
            title: "Song", artist: "Artist", album: "Album", duration: 200,
            candidateTitle: "Song (Live)", candidateArtist: "Artist", candidateAlbum: "Album", candidateDuration: 200
        ))
        XCTAssertFalse(AppleMusicLinkService.songCandidateIsConfident(
            title: "Song", artist: "Artist", album: nil, duration: nil,
            candidateTitle: "Song", candidateArtist: "Another Artist", candidateAlbum: nil, candidateDuration: nil
        ))
    }

    func testSourcePreferenceRoundTripsAndStatsLabelsUseRealConcepts() throws {
        let source = ActiveMusicSource.server(id: "server-1")
        XCTAssertEqual(try JSONDecoder().decode(ActiveMusicSource.self, from: JSONEncoder().encode(source)), source)
        XCTAssertEqual(LibraryStatsViewModel.Scope.library.label(isLocalLibrary: false), "Server")
        XCTAssertEqual(LibraryStatsViewModel.Scope.library.label(isLocalLibrary: true), "Local Files")
        XCTAssertEqual(LibraryStatsViewModel.Scope.downloads.label(isLocalLibrary: true), "Downloads")
        XCTAssertEqual(LibraryStatsData().commonResolution, "Unavailable")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeAudio(_ relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }
}
