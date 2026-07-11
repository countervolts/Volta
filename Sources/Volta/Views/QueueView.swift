import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var appState: AppState
    private var audio: AudioPlayer { appState.audioPlayer }

    var body: some View {
        VStack(spacing: 0) {
            modeToggles
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
            Divider().background(.white.opacity(0.15))
            queueList
        }
    }

    // MARK: - Mode toggles

    private var modeToggles: some View {
        HStack(spacing: 8) {
            modeButton(icon: Symbols.shuffle, label: L(.action_shuffle), active: audio.isShuffle) { audio.toggleShuffle() }
            modeButton(icon: audio.repeatMode == .one ? Symbols.repeatOne : Symbols.repeatAll,
                       label: audio.repeatMode == .one ? L(.queue_repeat_one) : L(.queue_repeat),
                       active: audio.repeatMode != .off) { audio.cycleRepeat() }
            autoplayButton
            transitionButton
        }
    }

    private var autoplayButton: some View {
        let (icon, label): (String, String) = switch audio.autoplayMode {
        case .off:       ("play.circle", "Autoplay")
        case .random:    ("play.circle.fill", "AutoPlay")
        case .algorithm: ("wand.and.stars", "Algorithm")
        }
        let active = audio.autoplayMode != .off
        return modeButton(icon: icon, label: label, active: active) { audio.cycleAutoplay() }
    }

    private var transitionButton: some View {
        modeButton(
            icon: audio.transitionMode.icon,
            label: audio.transitionMode.label,
            active: audio.transitionMode != .off
        ) { audio.cycleTransitionMode() }
    }

    private func modeButton(icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(label).font(.caption2.weight(.medium))
            }
            .foregroundStyle(active ? Theme.accent : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(active ? Theme.accent.opacity(0.12) : Color.white.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: active)
    }

    // MARK: - Queue list

    private var queueList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(.queue_continue_playing)).font(.headline).foregroundStyle(.white)
                    if !audio.queueSourceTitle.isEmpty {
                        Text(audio.queueSourceTitle).font(.caption).foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 10)

            let upcoming: [Song] = {
                let next = audio.currentIndex + 1
                guard next < audio.queue.count else { return [] }
                return Array(audio.queue[next...])
            }()

            List {
                if upcoming.isEmpty {
                    Text("Nothing queued")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.42))
                        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                        .padding(.horizontal, 20)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(Array(upcoming.enumerated()), id: \.element.id) { i, song in
                        let globalIndex = audio.currentIndex + 1 + i
                        queueRow(song: song, globalIndex: globalIndex)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    let nextSlot = audio.currentIndex + 1
                                    if globalIndex != nextSlot {
                                        audio.moveQueueItem(
                                            from: IndexSet(integer: globalIndex),
                                            to: nextSlot
                                        )
                                    }
                                } label: {
                                    Label(L(.action_play_next), systemImage: "text.line.first.and.arrowtriangle.forward")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    audio.removeQueueItem(at: globalIndex)
                                } label: {
                                    Label(L(.action_remove), systemImage: Symbols.trash)
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                    .onMove { indices, destination in
                        let offset = audio.currentIndex + 1
                        let globalFrom = IndexSet(indices.map { $0 + offset })
                        let globalTo = destination + offset
                        audio.moveQueueItem(from: globalFrom, to: globalTo)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
    }

    private func queueRow(song: Song, globalIndex: Int) -> some View {
        HStack(spacing: 12) {
            ArtworkView(coverArtID: song.coverArt, size: 80, cornerRadius: 6).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.body).foregroundStyle(.white).lineLimit(1)
                Text(song.artist ?? "").font(.caption).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { audio.skipTo(index: globalIndex) }
    }
}
