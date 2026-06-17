import SwiftUI
import UIKit

enum SongMenuSheet: String, Identifiable {
    case info, credits
    var id: String { rawValue }
}

// Native song action menu.
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
    var deleteLabel: String? = nil

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
                    Label(isStarred ? L(.action_unfavorite) : L(.action_favorite),
                          systemImage: isStarred ? Symbols.star : Symbols.starEmpty)
                }
                Button {
                    tasteStore.toggleLove(song.id)
                } label: {
                    Label(taste == .loved ? L(.action_unlove) : L(.action_love),
                          systemImage: taste == .loved ? "heart.fill" : "heart")
                }
                Button {
                    tasteStore.toggleDislike(song.id)
                } label: {
                    Label(taste == .disliked ? L(.action_remove_dislike) : L(.action_dislike),
                          systemImage: taste == .disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                }
            }

            Section {
                Button {
                    audio.playNext(song)
                } label: {
                    Label(L(.action_play_next), systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Button {
                    audio.addToQueue(song)
                } label: {
                    Label(L(.action_play_last), systemImage: "text.line.last.and.arrowtriangle.forward")
                }
                if let add = onAddToPlaylist {
                    Button(action: add) {
                        Label(L(.action_add_to_playlist), systemImage: Symbols.addToPlaylist)
                    }
                }
            }

            Section {
                Button {
                    sheet = .info
                } label: {
                    Label(L(.action_info), systemImage: Symbols.info)
                }
                if let albumAction = onGoToAlbum {
                    Button(action: albumAction) {
                        Label(L(.action_go_to_album), systemImage: "square.stack")
                    }
                }
                if let artistAction = onGoToArtist {
                    Button(action: artistAction) {
                        Label(L(.action_go_to_artist), systemImage: "music.mic")
                    }
                }
                Button {
                    sheet = .credits
                } label: {
                    Label(L(.action_view_credits), systemImage: "list.star")
                }
                Button(action: shareSong) {
                    Label(L(.action_share), systemImage: Symbols.share)
                }
            }

            if let del = onDelete {
                Section {
                    Button(role: .destructive, action: del) {
                        Label(deleteLabel ?? L(.action_delete), systemImage: Symbols.trash)
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
            if let url = await SongLinkService.pageURL(for: song) {
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
    @MainActor
    private var downloadLabel: String {
        switch dlState {
        case .notDownloaded: return L(.action_download)
        case .downloading:   return L(.action_cancel)
        case .downloaded:    return L(.action_remove)
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
        deleteLabel: String? = nil
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
