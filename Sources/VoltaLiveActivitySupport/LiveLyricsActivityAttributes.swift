#if canImport(ActivityKit)
import ActivityKit
import Foundation

@available(iOS 16.1, *)
public struct LiveLyricsActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public let songTitle: String
        public let artist: String
        public let currentLine: String
        public let nextLine: String
        public let isPlaying: Bool
        public let lineIndex: Int

        public init(
            songTitle: String,
            artist: String,
            currentLine: String,
            nextLine: String,
            isPlaying: Bool,
            lineIndex: Int
        ) {
            self.songTitle = songTitle
            self.artist = artist
            self.currentLine = currentLine
            self.nextLine = nextLine
            self.isPlaying = isPlaying
            self.lineIndex = lineIndex
        }
    }

    public let sessionID: String

    public init(sessionID: String = "playback") {
        self.sessionID = sessionID
    }
}
#endif
