import Foundation
import XCTest
@testable import Volta

final class EmbyCompatibilityTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: "streamingBitrate")
        UserDefaults.standard.removeObject(forKey: "streamingBitrateCell")
        UserDefaults.standard.removeObject(forKey: "networkIsCellular")
        UserDefaults.standard.removeObject(forKey: "downloadBitrate")
        UserDefaults.standard.removeObject(forKey: "transcodingFormat")
        UserDefaults.standard.removeObject(forKey: StreamingPreferences.transcodingEnabledKey)
        UserDefaults.standard.removeObject(forKey: StreamingPreferences.transcodingModeKey)
        UserDefaults.standard.removeObject(forKey: StreamingPreferences.transcodingCellularOnlyKey)
        UserDefaults.standard.removeObject(forKey: StreamingPreferences.transcodingRulesEnabledKey)
        UserDefaults.standard.removeObject(forKey: StreamingPreferences.transcodeFileTypeRulesKey)
        UserDefaults.standard.removeObject(forKey: StreamingPreferences.transcodeRuleDefaultBitrateKey)
        UserDefaults.standard.removeObject(forKey: StreamingPreferences.transcodingMigrationVersionKey)
        super.tearDown()
    }

    func testSuccessfulEmbyLoginUsesEmbyAuthorizationSchemeAndBasePath() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/emby/Users/AuthenticateByName")
            XCTAssertTrue(request.value(forHTTPHeaderField: "X-Emby-Authorization")?.hasPrefix("Emby ") == true)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return .json([
                "User": ["Id": "user-1"],
                "AccessToken": "token-1",
            ])
        }

        let client = try await JellyfinClient.connect(
            config: config("https://music.example.com/emby"),
            flavor: .emby,
            session: mockSession()
        )

        XCTAssertEqual(client.userId, "user-1")
        XCTAssertEqual(client.token, "token-1")
    }

    func testEmbyAuthenticatedItemsSendTokenHeaderAndCompatibleFields() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Emby-Token"), "token-1")
            XCTAssertTrue(request.value(forHTTPHeaderField: "X-Emby-Authorization")?.hasPrefix("Emby ") == true)
            let fields = request.url?.queryValue("Fields") ?? ""
            XCTAssertFalse(fields.contains("ImageTags"))
            XCTAssertFalse(fields.contains("PrimaryImageTag"))
            return .json(items: [
                ["Id": "album-1", "Name": "Album", "Type": "MusicAlbum"],
            ])
        }

        let albums = try await embyClient().allAlbums(size: 50, offset: 0)

        XCTAssertEqual(albums.map(\.id), ["album-1"])
    }

    func testEmbyItemsFallbackWhenServerRejectsFields() async throws {
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            if request.url?.queryValue("Fields") != nil {
                return .text(status: 400, body: #"{"error":"unsupported field"}"#)
            }
            return .json(items: [
                ["Id": "album-1", "Name": "Album", "Type": "MusicAlbum"],
            ])
        }

        let albums = try await embyClient().allAlbums(size: 50, offset: 0)

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(albums.first?.id, "album-1")
    }

    func testReverseProxySubpathAndDuplicateEmbyPathArePreserved() throws {
        let client = embyClient(baseURL: "https://music.example.com/emby/")

        XCTAssertEqual(client.url("/Users/user-1/Items")?.path, "/emby/Users/user-1/Items")
        XCTAssertEqual(client.url("/emby/Users/user-1/Items")?.path, "/emby/Users/user-1/Items")
    }

    func testDDNSHTTPSCandidateDoesNotPreferDirectEmbyPort() throws {
        let candidates = SubsonicConfig.candidateURLs(from: "volta-ddns.example.net", kind: .emby)

        XCTAssertEqual(candidates.first?.scheme, "https")
        XCTAssertNil(candidates.first?.port)
        XCTAssertEqual(candidates.first?.host, "volta-ddns.example.net")
    }

    func testEmptyEmbyMusicLibraryReturnsEmptyWithoutError() async throws {
        MockURLProtocol.handler = { _ in
            .json(["Items": [], "TotalRecordCount": 0])
        }

        let albums = try await embyClient().allAlbums(size: 50, offset: 0)

        XCTAssertTrue(albums.isEmpty)
    }

    func testAlbumResponseWithMissingOptionalMetadataDecodes() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "Items": [
                ["Id": "album-1", "Name": "Sparse Album", "Type": "MusicAlbum"],
            ],
        ])

        let response = try JSONDecoder().decode(JFItemsResponse.self, from: data)
        let album = try XCTUnwrap(response.Items?.first?.asAlbum)

        XCTAssertEqual(album.id, "album-1")
        XCTAssertEqual(album.name, "Sparse Album")
        XCTAssertNil(album.artist)
    }

    func testHTMLProxyErrorIsReportedAsServerFailure() async throws {
        MockURLProtocol.handler = { _ in
            .html(status: 502, body: "<html><body>Bad gateway</body></html>")
        }

        do {
            _ = try await embyClient().allAlbums(size: 50, offset: 0)
            XCTFail("Expected Emby HTML proxy response to throw")
        } catch SubsonicError.server(let code, let message) {
            XCTAssertEqual(code, 502)
            XCTAssertTrue(message.contains("HTML response"))
        }
    }

    func testCancelledEmbyRequestPropagatesCancellation() async throws {
        MockURLProtocol.handler = { _ in
            throw URLError(.cancelled)
        }

        do {
            _ = try await embyClient().allAlbums(size: 50, offset: 0)
            XCTFail("Expected cancellation to propagate")
        } catch is CancellationError {
            // Expected: UI refresh/navigation cancellation should not become a server error.
        }
    }

    func testPaginatedEmbyAlbumsBeyondFirstPage() async throws {
        var offsets: [String] = []
        MockURLProtocol.handler = { request in
            let offset = request.url?.queryValue("StartIndex") ?? "0"
            offsets.append(offset)
            let start = Int(offset) ?? 0
            let count = start < 4 ? 2 : 1
            let items = (0..<count).map { index in
                ["Id": "album-\(start + index)", "Name": "Album \(start + index)", "Type": "MusicAlbum"]
            }
            return .json(items: items)
        }

        var all: [Album] = []
        var offset = 0
        while true {
            let page = try await embyClient().allAlbums(size: 2, offset: offset)
            all.append(contentsOf: page)
            if page.count < 2 { break }
            offset += 2
        }

        XCTAssertEqual(offsets, ["0", "2", "4"])
        XCTAssertEqual(all.map(\.id), ["album-0", "album-1", "album-2", "album-3", "album-4"])
    }

    func testArtworkInheritedFromAlbumWhenSongHasNoOwnImage() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "Id": "song-1",
            "Name": "Track",
            "Type": "Audio",
            "AlbumId": "album-1",
        ])

        let song = try JSONDecoder().decode(JFItem.self, from: data).asSong

        XCTAssertEqual(song.coverArt, "album-1")
    }

    func testEmbyImageOriginalAndTranscodedPlaybackURLs() throws {
        let client = embyClient(baseURL: "https://music.example.com/emby")

        let imageURL = try XCTUnwrap(client.coverArtURL(id: "album-1::tag-1", size: 600))
        XCTAssertEqual(imageURL.path, "/emby/Items/album-1/Images/Primary")
        XCTAssertEqual(imageURL.queryValue("tag"), "tag-1")
        XCTAssertEqual(imageURL.queryValue("X-Emby-Token"), "token-1")

        UserDefaults.standard.set(0, forKey: "streamingBitrate")
        UserDefaults.standard.set("raw", forKey: "transcodingFormat")
        let original = try XCTUnwrap(client.streamURL(id: "song-1"))
        XCTAssertEqual(original.path, "/emby/Audio/song-1/stream")
        XCTAssertEqual(original.queryValue("static"), "true")
        XCTAssertEqual(original.queryValue("X-Emby-Token"), "token-1")

        UserDefaults.standard.set("aac", forKey: "transcodingFormat")
        let originalWithFormatPreference = try XCTUnwrap(client.streamURL(id: "song-1"))
        XCTAssertEqual(originalWithFormatPreference.path, "/emby/Audio/song-1/stream")
        XCTAssertEqual(originalWithFormatPreference.queryValue("static"), "true")
        XCTAssertNil(originalWithFormatPreference.queryValue("AudioCodec"))

        UserDefaults.standard.set(128, forKey: "streamingBitrate")
        let aac = try XCTUnwrap(client.streamURL(id: "song-1"))
        XCTAssertEqual(aac.path, "/emby/Audio/song-1/stream")
        XCTAssertEqual(aac.queryValue("static"), "false")
        XCTAssertEqual(aac.queryValue("AudioCodec"), "aac")
        XCTAssertEqual(aac.queryValue("Container"), "m4a")
        XCTAssertEqual(aac.queryValue("MaxStreamingBitrate"), "128000")

        UserDefaults.standard.set(192, forKey: "streamingBitrate")
        UserDefaults.standard.set("mp3", forKey: "transcodingFormat")
        let transcoded = try XCTUnwrap(client.streamURL(id: "song-1"))
        XCTAssertEqual(transcoded.path, "/emby/Audio/song-1/stream")
        XCTAssertEqual(transcoded.queryValue("static"), "false")
        XCTAssertEqual(transcoded.queryValue("AudioCodec"), "mp3")
        XCTAssertEqual(transcoded.queryValue("Container"), "mp3")
        XCTAssertEqual(transcoded.queryValue("MaxStreamingBitrate"), "192000")
    }

    func testEmbyLiveArtworkURLsPreferOriginalAndAvoidFlatteningWebPConversion() throws {
        let client = embyClient(baseURL: "https://music.example.com/emby")

        let urls = client.liveArtworkURLs(id: "album-1::tag-1")

        XCTAssertEqual(urls.count, 6)
        XCTAssertEqual(urls[0].path, "/emby/Items/album-1/Images/Primary")
        XCTAssertEqual(urls[0].queryValue("tag"), "tag-1")
        XCTAssertEqual(urls[0].queryValue("X-Emby-Token"), "token-1")
        XCTAssertEqual(urls[0].queryValue("format"), "original")
        XCTAssertEqual(urls[0].queryValue("keepAnimation"), "true")
        XCTAssertEqual(urls[0].queryValue("enableImageEnhancers"), "false")
        XCTAssertEqual(urls[1].path, "/emby/Items/album-1/Images/Primary/0")
        XCTAssertEqual(urls[1].queryValue("tag"), "tag-1")
        XCTAssertEqual(urls[1].queryValue("X-Emby-Token"), "token-1")
        XCTAssertEqual(urls[1].queryValue("format"), "original")
        XCTAssertEqual(urls[1].queryValue("keepAnimation"), "true")
        XCTAssertEqual(urls[1].queryValue("enableImageEnhancers"), "false")
        XCTAssertEqual(urls[2].path, "/emby/Items/album-1/Images/Primary")
        XCTAssertNil(urls[2].queryValue("format"))
        XCTAssertEqual(urls[3].path, "/emby/Items/album-1/Images/Primary/0")
        XCTAssertNil(urls[3].queryValue("format"))
        XCTAssertEqual(urls[4].path, "/emby/Items/album-1/Images/Primary")
        XCTAssertEqual(urls[4].queryValue("format"), "gif")
        XCTAssertEqual(urls[5].path, "/emby/Items/album-1/Images/Primary/0")
        XCTAssertEqual(urls[5].queryValue("format"), "gif")
        XCTAssertTrue(urls.allSatisfy { $0.queryValue("format") != "webp" })
    }

    func testSubsonicTranscodedStreamsRequestEstimatedContentLength() throws {
        let client = SubsonicClient(config: config("https://navidrome.example.com"))

        UserDefaults.standard.set(0, forKey: "streamingBitrate")
        UserDefaults.standard.set("raw", forKey: "transcodingFormat")
        let original = try XCTUnwrap(client.streamURL(id: "song-1"))
        XCTAssertEqual(original.queryValue("format"), "raw")
        XCTAssertNil(original.queryValue("estimateContentLength"))

        UserDefaults.standard.set("aac", forKey: "transcodingFormat")
        let originalWithFormatPreference = try XCTUnwrap(client.streamURL(id: "song-1"))
        XCTAssertEqual(originalWithFormatPreference.path, "/rest/stream")
        XCTAssertEqual(originalWithFormatPreference.queryValue("format"), "raw")
        XCTAssertNil(originalWithFormatPreference.queryValue("maxBitRate"))

        UserDefaults.standard.set(128, forKey: "streamingBitrate")
        let aac = try XCTUnwrap(client.streamURL(id: "song-1"))
        XCTAssertEqual(aac.path, "/rest/stream")
        XCTAssertEqual(aac.queryValue("maxBitRate"), "128")
        XCTAssertEqual(aac.queryValue("format"), "aac")
        XCTAssertEqual(aac.queryValue("estimateContentLength"), "true")

        UserDefaults.standard.set(128, forKey: "streamingBitrate")
        UserDefaults.standard.set("opus", forKey: "transcodingFormat")
        let transcoded = try XCTUnwrap(client.streamURL(id: "song-1"))
        XCTAssertEqual(transcoded.queryValue("maxBitRate"), "128")
        XCTAssertEqual(transcoded.queryValue("format"), "opus")
        XCTAssertEqual(transcoded.queryValue("estimateContentLength"), "true")

        UserDefaults.standard.set(128, forKey: "downloadBitrate")
        let download = try XCTUnwrap(client.downloadURL(id: "song-1"))
        XCTAssertEqual(download.queryValue("estimateContentLength"), "true")
    }

    func testSubsonicOpusTranscodeNegotiatesStereoStream() async throws {
        UserDefaults.standard.set(320, forKey: "streamingBitrate")
        UserDefaults.standard.set("opus", forKey: "transcodingFormat")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/rest/getTranscodeDecision")
            XCTAssertEqual(request.url?.queryValue("mediaId"), "atmos-song")
            XCTAssertEqual(request.url?.queryValue("mediaType"), "song")

            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["maxAudioBitrate"] as? Int, 320_000)
            XCTAssertEqual(json["maxTranscodingAudioBitrate"] as? Int, 320_000)
            let profiles = try XCTUnwrap(json["transcodingProfiles"] as? [[String: Any]])
            XCTAssertEqual(profiles.first?["container"] as? String, "opus")
            XCTAssertEqual(profiles.first?["audioCodec"] as? String, "opus")
            XCTAssertEqual(profiles.first?["protocol"] as? String, "http")
            XCTAssertEqual(profiles.first?["maxAudioChannels"] as? Int, 2)

            return try .json([
                "subsonic-response": [
                    "status": "ok",
                    "version": "1.16.1",
                    "transcodeDecision": [
                        "canDirectPlay": false,
                        "canTranscode": true,
                        "transcodeParams": "opaque-token",
                        "transcodeStream": [
                            "container": "opus",
                            "codec": "opus",
                            "audioChannels": 2,
                        ],
                    ],
                ],
            ])
        }

        let client = SubsonicClient(
            config: config("https://navidrome.example.com"),
            session: mockSession()
        )
        XCTAssertFalse(client.streamMetadataReady(id: "atmos-song"))

        await client.prepareForPlayback(id: "atmos-song")

        XCTAssertTrue(client.streamMetadataReady(id: "atmos-song"))
        let stream = try XCTUnwrap(client.streamURL(id: "atmos-song"))
        XCTAssertEqual(stream.path, "/rest/getTranscodeStream")
        XCTAssertEqual(stream.queryValue("mediaId"), "atmos-song")
        XCTAssertEqual(stream.queryValue("mediaType"), "song")
        XCTAssertEqual(stream.queryValue("transcodeParams"), "opaque-token")
        XCTAssertNil(stream.queryValue("estimateContentLength"))
    }

    func testSubsonicTranscodeNegotiationFallsBackToLegacyStream() async throws {
        UserDefaults.standard.set(128, forKey: "streamingBitrate")
        UserDefaults.standard.set("opus", forKey: "transcodingFormat")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/getTranscodeDecision")
            return .text(status: 404, body: "not supported")
        }

        let client = SubsonicClient(
            config: config("https://subsonic.example.com"),
            session: mockSession()
        )
        await client.prepareForPlayback(id: "song-1")

        XCTAssertTrue(client.streamMetadataReady(id: "song-1"))
        let stream = try XCTUnwrap(client.streamURL(id: "song-1"))
        XCTAssertEqual(stream.path, "/rest/stream")
        XCTAssertEqual(stream.queryValue("maxBitRate"), "128")
        XCTAssertEqual(stream.queryValue("format"), "opus")
        XCTAssertEqual(stream.queryValue("estimateContentLength"), "true")
    }

    func testJellyfinAACTranscodeUsesPlayableM4AStream() throws {
        let client = jellyfinClient(baseURL: "https://music.example.com")

        UserDefaults.standard.set(128, forKey: "streamingBitrate")
        UserDefaults.standard.set("aac", forKey: "transcodingFormat")

        let url = try XCTUnwrap(client.streamURL(id: "song-1"))
        XCTAssertEqual(url.path, "/Audio/song-1/stream")
        XCTAssertEqual(url.queryValue("static"), "false")
        XCTAssertEqual(url.queryValue("AudioCodec"), "aac")
        XCTAssertEqual(url.queryValue("Container"), "m4a")
        XCTAssertEqual(url.queryValue("MaxStreamingBitrate"), "128000")
    }

    func testFormatPreferenceAloneDoesNotEnableTranscoding() {
        UserDefaults.standard.set("aac", forKey: "transcodingFormat")

        XCTAssertFalse(StreamingPreferences.wantsTranscode(bitrateKbps: 0))
        XCTAssertTrue(StreamingPreferences.wantsTranscode(bitrateKbps: 128))
    }

    func testFileTypeRuleForcesSubsonicTargetCodec() throws {
        let client = SubsonicClient(config: config("https://navidrome.example.com"))
        let song = try song(id: "flac-song", suffix: "flac", codec: "flac", contentType: "audio/flac")

        UserDefaults.standard.set(0, forKey: "streamingBitrate")
        UserDefaults.standard.set(true, forKey: StreamingPreferences.transcodingEnabledKey)
        UserDefaults.standard.set(TranscodingSettingsMode.advanced.rawValue, forKey: StreamingPreferences.transcodingModeKey)
        UserDefaults.standard.set(256, forKey: StreamingPreferences.transcodeRuleDefaultBitrateKey)
        UserDefaults.standard.set(
            StreamingPreferences.encodeRuleTargets([.flac: .opus]),
            forKey: StreamingPreferences.transcodeFileTypeRulesKey
        )

        let decision = StreamingPreferences.streamDecision(for: song)
        XCTAssertEqual(decision.sourceKind, .flac)
        XCTAssertEqual(decision.ruleTarget, .opus)
        XCTAssertEqual(decision.bitrateKbps, 256)
        XCTAssertEqual(decision.format, "opus")

        let url = try XCTUnwrap(client.streamURL(for: song))
        XCTAssertEqual(url.queryValue("maxBitRate"), "256")
        XCTAssertEqual(url.queryValue("format"), "opus")
        XCTAssertEqual(url.queryValue("estimateContentLength"), "true")
    }

    func testOriginalRuleExemptsMatchingSourceFromBitrateCap() throws {
        let client = SubsonicClient(config: config("https://navidrome.example.com"))
        let song = try song(id: "mp3-song", suffix: "mp3", codec: "mp3", contentType: "audio/mpeg")

        UserDefaults.standard.set(128, forKey: "streamingBitrate")
        UserDefaults.standard.set("aac", forKey: "transcodingFormat")
        UserDefaults.standard.set(true, forKey: StreamingPreferences.transcodingEnabledKey)
        UserDefaults.standard.set(TranscodingSettingsMode.advanced.rawValue, forKey: StreamingPreferences.transcodingModeKey)
        UserDefaults.standard.set(
            StreamingPreferences.encodeRuleTargets([.mp3: .original]),
            forKey: StreamingPreferences.transcodeFileTypeRulesKey
        )

        let decision = StreamingPreferences.streamDecision(for: song)
        XCTAssertEqual(decision.sourceKind, .mp3)
        XCTAssertEqual(decision.ruleTarget, .original)
        XCTAssertFalse(decision.wantsTranscode)

        let url = try XCTUnwrap(client.streamURL(for: song))
        XCTAssertEqual(url.queryValue("format"), "raw")
        XCTAssertNil(url.queryValue("maxBitRate"))
        XCTAssertNil(url.queryValue("estimateContentLength"))
    }

    func testJellyfinFileTypeRuleSelectsCodecAndDefaultBitrate() throws {
        let client = jellyfinClient(baseURL: "https://music.example.com")
        let song = try song(
            id: "alac-song",
            suffix: "m4a",
            codec: "alac",
            contentType: "audio/mp4",
            bitDepth: 16
        )

        UserDefaults.standard.set(0, forKey: "streamingBitrate")
        UserDefaults.standard.set(true, forKey: StreamingPreferences.transcodingEnabledKey)
        UserDefaults.standard.set(TranscodingSettingsMode.advanced.rawValue, forKey: StreamingPreferences.transcodingModeKey)
        UserDefaults.standard.set(192, forKey: StreamingPreferences.transcodeRuleDefaultBitrateKey)
        UserDefaults.standard.set(
            StreamingPreferences.encodeRuleTargets([.alac: .mp3]),
            forKey: StreamingPreferences.transcodeFileTypeRulesKey
        )

        let url = try XCTUnwrap(client.streamURL(for: song))
        XCTAssertEqual(url.path, "/Audio/alac-song/stream")
        XCTAssertEqual(url.queryValue("static"), "false")
        XCTAssertEqual(url.queryValue("AudioCodec"), "mp3")
        XCTAssertEqual(url.queryValue("Container"), "mp3")
        XCTAssertEqual(url.queryValue("MaxStreamingBitrate"), "192000")
    }

    func testTranscodingOffOverridesSimpleBitrateCap() throws {
        let client = SubsonicClient(config: config("https://navidrome.example.com"))
        let song = try song(id: "flac-song", suffix: "flac", codec: "flac", contentType: "audio/flac")

        UserDefaults.standard.set(128, forKey: "streamingBitrate")
        UserDefaults.standard.set("opus", forKey: "transcodingFormat")
        UserDefaults.standard.set(false, forKey: StreamingPreferences.transcodingEnabledKey)
        UserDefaults.standard.set(TranscodingSettingsMode.simple.rawValue, forKey: StreamingPreferences.transcodingModeKey)

        let decision = StreamingPreferences.streamDecision(for: song)
        XCTAssertEqual(decision.requestedBitrateKbps, 128)
        XCTAssertFalse(decision.wantsTranscode)

        let url = try XCTUnwrap(client.streamURL(for: song))
        XCTAssertEqual(url.queryValue("format"), "raw")
        XCTAssertNil(url.queryValue("maxBitRate"))
    }

    func testSimpleTranscodingCellularOnlyBlocksWifiAndAllowsCellular() throws {
        let client = SubsonicClient(config: config("https://navidrome.example.com"))
        let song = try song(id: "flac-song", suffix: "flac", codec: "flac", contentType: "audio/flac")

        UserDefaults.standard.set(128, forKey: "streamingBitrate")
        UserDefaults.standard.set("aac", forKey: "transcodingFormat")
        UserDefaults.standard.set(true, forKey: StreamingPreferences.transcodingEnabledKey)
        UserDefaults.standard.set(TranscodingSettingsMode.simple.rawValue, forKey: StreamingPreferences.transcodingModeKey)
        UserDefaults.standard.set(true, forKey: StreamingPreferences.transcodingCellularOnlyKey)
        UserDefaults.standard.set(false, forKey: "networkIsCellular")

        let wifiURL = try XCTUnwrap(client.streamURL(for: song))
        XCTAssertEqual(wifiURL.queryValue("format"), "raw")
        XCTAssertNil(wifiURL.queryValue("maxBitRate"))

        UserDefaults.standard.set(true, forKey: "networkIsCellular")

        let cellularURL = try XCTUnwrap(client.streamURL(for: song))
        XCTAssertEqual(cellularURL.queryValue("maxBitRate"), "128")
        XCTAssertEqual(cellularURL.queryValue("format"), "aac")
    }

    func testAdvancedTranscodingCellularOnlyBlocksWifiAndAllowsCellularRules() throws {
        let client = SubsonicClient(config: config("https://navidrome.example.com"))
        let song = try song(id: "flac-song", suffix: "flac", codec: "flac", contentType: "audio/flac")

        UserDefaults.standard.set(0, forKey: "streamingBitrate")
        UserDefaults.standard.set(true, forKey: StreamingPreferences.transcodingEnabledKey)
        UserDefaults.standard.set(TranscodingSettingsMode.advanced.rawValue, forKey: StreamingPreferences.transcodingModeKey)
        UserDefaults.standard.set(true, forKey: StreamingPreferences.transcodingCellularOnlyKey)
        UserDefaults.standard.set(192, forKey: StreamingPreferences.transcodeRuleDefaultBitrateKey)
        UserDefaults.standard.set(
            StreamingPreferences.encodeRuleTargets([.flac: .opus]),
            forKey: StreamingPreferences.transcodeFileTypeRulesKey
        )
        UserDefaults.standard.set(false, forKey: "networkIsCellular")

        let wifiURL = try XCTUnwrap(client.streamURL(for: song))
        XCTAssertEqual(wifiURL.queryValue("format"), "raw")
        XCTAssertNil(wifiURL.queryValue("maxBitRate"))

        UserDefaults.standard.set(true, forKey: "networkIsCellular")

        let cellularURL = try XCTUnwrap(client.streamURL(for: song))
        XCTAssertEqual(cellularURL.queryValue("maxBitRate"), "192")
        XCTAssertEqual(cellularURL.queryValue("format"), "opus")
    }

    func testTranscodingMigrationDefaultsExistingSettingsToSimpleMode() {
        UserDefaults.standard.set(128, forKey: "streamingBitrate")
        UserDefaults.standard.set("aac", forKey: "transcodingFormat")

        StreamingPreferences.migrateTranscodingSettingsIfNeeded()

        XCTAssertTrue(StreamingPreferences.transcodingEnabled)
        XCTAssertEqual(StreamingPreferences.transcodingMode, .simple)
        XCTAssertEqual(StreamingPreferences.streamBitrateKbps, 128)
        XCTAssertEqual(StreamingPreferences.transcodingFormat, "aac")
    }

    func testTranscodingMigrationKeepsUnreleasedAdvancedStateAdvanced() {
        UserDefaults.standard.set(true, forKey: StreamingPreferences.transcodingRulesEnabledKey)
        UserDefaults.standard.set(
            StreamingPreferences.encodeRuleTargets([.flac: .opus]),
            forKey: StreamingPreferences.transcodeFileTypeRulesKey
        )

        StreamingPreferences.migrateTranscodingSettingsIfNeeded()

        XCTAssertTrue(StreamingPreferences.transcodingEnabled)
        XCTAssertEqual(StreamingPreferences.transcodingMode, .advanced)
        XCTAssertEqual(StreamingPreferences.ruleTarget(for: .flac), .opus)
    }

    private func embyClient(baseURL: String = "https://music.example.com") -> JellyfinClient {
        JellyfinClient(
            config: config(baseURL),
            flavor: .emby,
            userId: "user-1",
            token: "token-1",
            deviceId: "device-1",
            session: mockSession()
        )
    }

    private func jellyfinClient(baseURL: String = "https://music.example.com") -> JellyfinClient {
        JellyfinClient(
            config: config(baseURL),
            flavor: .jellyfin,
            userId: "user-1",
            token: "token-1",
            deviceId: "device-1",
            session: mockSession()
        )
    }

    private func song(
        id: String,
        suffix: String? = nil,
        codec: String? = nil,
        contentType: String? = nil,
        bitDepth: Int? = nil
    ) throws -> Song {
        var payload: [String: Any] = [
            "id": id,
            "title": "Track",
        ]
        payload["suffix"] = suffix
        payload["codec"] = codec
        payload["contentType"] = contentType
        payload["bitDepth"] = bitDepth
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(Song.self, from: data)
    }

    private func config(_ baseURL: String) -> SubsonicConfig {
        SubsonicConfig(baseURL: URL(string: baseURL)!, username: "user", password: "pass")
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class MockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> MockResponse

    nonisolated(unsafe) static var handler: Handler?

    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let response = try handler(request)
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": response.contentType]
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct MockResponse {
    let status: Int
    let contentType: String
    let data: Data

    static func json(_ object: Any, status: Int = 200) throws -> MockResponse {
        MockResponse(
            status: status,
            contentType: "application/json",
            data: try JSONSerialization.data(withJSONObject: object)
        )
    }

    static func json(items: [[String: Any]], status: Int = 200) throws -> MockResponse {
        try json(["Items": items, "TotalRecordCount": items.count], status: status)
    }

    static func text(status: Int, body: String) -> MockResponse {
        MockResponse(status: status, contentType: "application/json", data: Data(body.utf8))
    }

    static func html(status: Int, body: String) -> MockResponse {
        MockResponse(status: status, contentType: "text/html", data: Data(body.utf8))
    }
}

private extension URL {
    func queryValue(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?
            .value
    }
}
