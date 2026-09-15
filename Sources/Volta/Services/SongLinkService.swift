import Foundation

// Kept as a compatibility shim for callers outside the share UI.
enum SongLinkService {
    static func pageURL(for song: Song) async -> URL? {
        await AppleMusicLinkService.url(for: song)
    }
}
