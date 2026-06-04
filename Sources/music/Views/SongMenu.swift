import SwiftUI
import UIKit

enum SongMenuSheet: String, Identifiable {
    case info, credits
    var id: String { rawValue }
}

// Native SwiftUI Menu for song actions. The system renders it as a Liquid Glass
// contextual menu (same look as the top-right account menu). The Download /
// Favorite / Share row uses a ControlGroup so the system lays them out as the
// compact icon row at the top, Apple Music style.
//
// Usage:
//   SongMenu(song: song, onGoToArtist: ..., onAddToPlaylist: ...) {
//       Image(systemName: Symbols.more)
//   }
struct SongMenu<Trigger: View>: View {
    let song: Song

    var onGoToAlbum: (() -> Void)? = nil
    var onGoToArtist: (() -> Void)? = nil
    var onAddToPlaylist: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var deleteLabel: String = "Delete"

    @ViewBuilder var label: () -> Trigger

    @Environment(AppState.self) private var appState
    @State private var tasteStore = TasteStore.shared
    @State private var sheet: SongMenuSheet? = nil

    private var audio: AudioPlayer { appState.audioPlayer }
    private var isStarred: Bool { audio.isStarred(song.id) }
    private var taste: TasteState { tasteStore.state(for: song.id) }
    private var dlState: DownloadState { DownloadService.shared.state(for: song) }

    var body: some View {
        Menu {
            ControlGroup {
                Button(action: toggleDownload) {
                    Label(downloadLabel, systemImage: downloadIcon)
                }
                Button {
                    audio.toggleStar(songID: song.id)
                } label: {
                    Label(isStarred ? "Unfavorite" : "Favorite",
                          systemImage: isStarred ? Symbols.star : Symbols.starEmpty)
                }
                Button {
                    tasteStore.toggleLove(song.id)
                } label: {
                    Label(taste == .loved ? "Unlove" : "Love",
                          systemImage: taste == .loved ? "heart.fill" : "heart")
                }
                Button {
                    tasteStore.toggleDislike(song.id)
                } label: {
                    Label(taste == .disliked ? "Remove Dislike" : "Dislike",
                          systemImage: taste == .disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                }
            }

            Section {
                Button {
                    audio.playNext(song)
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Button {
                    audio.addToQueue(song)
                } label: {
                    Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
                }
                if let add = onAddToPlaylist {
                    Button(action: add) {
                        Label("Add to Playlist", systemImage: Symbols.addToPlaylist)
                    }
                }
            }

            Section {
                Button {
                    sheet = .info
                } label: {
                    Label("Info", systemImage: Symbols.info)
                }
                if let albumAction = onGoToAlbum {
                    Button(action: albumAction) {
                        Label("Go to Album", systemImage: "square.stack")
                    }
                }
                if let artistAction = onGoToArtist {
                    Button(action: artistAction) {
                        Label("Go to Artist", systemImage: "music.mic")
                    }
                }
                Button {
                    sheet = .credits
                } label: {
                    Label("View Credits", systemImage: "list.star")
                }
                if appState.sharingAvailable {
                    Button(action: shareSong) {
                        Label("Share", systemImage: Symbols.share)
                    }
                }
            }

            if let del = onDelete {
                Section {
                    Button(role: .destructive, action: del) {
                        Label(deleteLabel, systemImage: Symbols.trash)
                    }
                }
            }
        } label: {
            label()
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .info:    SongInfoSheet(song: song)
            case .credits: SongCreditsSheet(song: song)
            }
        }
    }

    // MARK: - Actions

    private func shareSong() {
        Task {
            if let url = try? await appState.client?.createShare(id: song.id) {
                ShareSheet.present([url])
            }
        }
    }

    private func toggleDownload() {
        switch dlState {
        case .notDownloaded: DownloadService.shared.download(song: song)
        case .downloaded:    DownloadService.shared.removeDownload(for: song)
        case .downloading:   DownloadService.shared.cancelDownload(for: song)
        }
    }

    private var downloadIcon: String {
        switch dlState {
        case .notDownloaded: return "arrow.down.circle"
        case .downloading:   return "xmark.circle"
        case .downloaded:    return "checkmark.circle.fill"
        }
    }
    private var downloadLabel: String {
        switch dlState {
        case .notDownloaded: return "Download"
        case .downloading:   return "Cancel"
        case .downloaded:    return "Remove"
        }
    }
}

// Default ellipsis label matching the old "more" button styling.
extension SongMenu where Trigger == AnyView {
    init(
        song: Song,
        onGoToAlbum: (() -> Void)? = nil,
        onGoToArtist: (() -> Void)? = nil,
        onAddToPlaylist: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        deleteLabel: String = "Delete"
    ) {
        self.init(
            song: song,
            onGoToAlbum: onGoToAlbum,
            onGoToArtist: onGoToArtist,
            onAddToPlaylist: onAddToPlaylist,
            onDelete: onDelete,
            deleteLabel: deleteLabel
        ) {
            AnyView(
                Image(systemName: Symbols.more)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            )
        }
    }
}
