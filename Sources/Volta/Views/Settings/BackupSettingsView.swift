import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    // MARK: - Backups

    @ViewBuilder
    var backupSection: some View {
        let s = "Backups"
        if sectionVisible(s, [["settings backup", "settings", "backup", "restore", "export", "import"], ["playlist backup", "playlist", "deleted", "restore", "auto", "json"]]) {
            Section {
                Toggle(isOn: $autoPlaylistBackupEnabled) {
                    Label("Auto Playlist Backups", systemImage: "clock.arrow.circlepath")
                }
                .tint(Theme.accent)

                Button {
                    refreshPlaylistBackups()
                } label: {
                    HStack {
                        Label("Update Playlist Backups", systemImage: "arrow.clockwise")
                        Spacer()
                        if isRefreshingPlaylistBackups {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                        }
                    }
                }
                .foregroundStyle(Theme.primaryText)
                .disabled(!autoPlaylistBackupEnabled || isRefreshingPlaylistBackups || appState.client == nil)

                if !hasLoadedPlaylistBackups {
                    Text("Loading playlist backups...")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                } else if deletedPlaylistBackups.isEmpty {
                    Text("No deleted playlist backups")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(deletedPlaylistBackups) { snapshot in
                        HStack(spacing: 10) {
                            Button {
                                restoreDeletedPlaylist(snapshot)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.uturn.backward.circle")
                                        .foregroundStyle(Theme.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(snapshot.name)
                                            .foregroundStyle(Theme.primaryText)
                                        Text("\(snapshot.songCount) song\(snapshot.songCount == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    Spacer()
                                    if restoringPlaylistBackupID == snapshot.id {
                                        ProgressView().controlSize(.small).tint(Theme.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(restoringPlaylistBackupID != nil || appState.client == nil)

                            Button(role: .destructive) {
                                deletePlaylistBackup(snapshot)
                            } label: {
                                Image(systemName: Symbols.trash)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.error)
                                    .frame(width: 34, height: 34)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(restoringPlaylistBackupID == snapshot.id)
                            .accessibilityLabel("Delete backup for \(snapshot.name)")
                        }
                    }
                }

                if let playlistBackupStatus {
                    Text(playlistBackupStatus)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Button {
                    exportSettingsBackup()
                } label: {
                    HStack {
                        Label("Export Settings Backup", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isExportingSettings {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                        }
                    }
                }
                .foregroundStyle(Theme.primaryText)
                .disabled(isExportingSettings)

                Button {
                    showSettingsImporter = true
                } label: {
                    Label("Restore Settings Backup", systemImage: "arrow.down.doc")
                }
                .foregroundStyle(Theme.primaryText)

                if let settingsBackupStatus {
                    Text(settingsBackupStatus)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Button {
                    exportPlaylists()
                } label: {
                    HStack {
                        Label("Export Playlists", systemImage: "square.and.arrow.up.on.square")
                        Spacer()
                        if isExportingPlaylists {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                        }
                    }
                }
                .foregroundStyle(Theme.primaryText)
                .disabled(isExportingPlaylists || appState.client == nil)

                Button {
                    showPlaylistImporter = true
                } label: {
                    HStack {
                        Label("Import Playlists", systemImage: "square.and.arrow.down.on.square")
                        Spacer()
                        if isImportingPlaylists {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                        }
                    }
                }
                .foregroundStyle(Theme.primaryText)
                .disabled(isImportingPlaylists || appState.client == nil)
                .fileImporter(
                    isPresented: $showPlaylistImporter,
                    allowedContentTypes: [.json],
                    allowsMultipleSelection: false
                ) { result in
                    importPlaylists(result)
                }

                if let playlistTransferStatus {
                    Text(playlistTransferStatus)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            } header: {
                Text(sectionTitle(s))
            } footer: {
                Text("Playlist backups are kept as local JSON and refresh after playlist edits. Export/Import recreates server playlists as portable JSON files. Settings backups include app preferences and smart playlists. Server passwords stay in Keychain and are not exported.")
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    // MARK: - Backup helpers

    func exportSettingsBackup() {
        guard !isExportingSettings else { return }
        isExportingSettings = true
        settingsBackupStatus = "Preparing backup..."
        Task {
            defer { isExportingSettings = false }
            do {
                let url = try SettingsBackupManager.exportURL()
                settingsBackupStatus = "Backup ready"
                VoltaNotificationCenter.shared.post(L(.notif_settings_backup_ready), tone: .success)
                ShareSheet.present([url])
            } catch {
                settingsBackupStatus = "Backup failed: \(error.localizedDescription)"
                AppLogger.shared.log("Settings backup failed: \(error.localizedDescription)", category: .other, level: .error)
            }
        }
    }

    func restoreSettingsBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            let count = try SettingsBackupManager.restore(from: url)
            SmartPlaylistStore.shared.reload()
            PlaylistFolderStore.shared.reload()
            hiddenAlbums.reloadFromDefaults()
            settingsBackupStatus = "Restored \(count) settings"
            VoltaNotificationCenter.shared.post(L(.notif_settings_restored), tone: .success)
        } catch {
            settingsBackupStatus = "Restore failed: \(error.localizedDescription)"
            VoltaNotificationCenter.shared.post(L(.notif_settings_restore_failed), tone: .error)
            AppLogger.shared.log("Settings restore failed: \(error.localizedDescription)", category: .other, level: .error)
        }
    }

    func exportPlaylists() {
        guard !isExportingPlaylists, let client = appState.client else { return }
        isExportingPlaylists = true
        playlistTransferStatus = "Collecting playlists…"
        Task {
            defer { isExportingPlaylists = false }
            do {
                let url = try await PlaylistTransfer.exportURL(client: client)
                playlistTransferStatus = "Playlists exported"
                VoltaNotificationCenter.shared.post(L(.notif_playlists_exported), tone: .success)
                ShareSheet.present([url])
            } catch {
                playlistTransferStatus = "Export failed: \(error.localizedDescription)"
                VoltaNotificationCenter.shared.post(L(.notif_playlist_export_failed), tone: .error)
            }
        }
    }

    func importPlaylists(_ result: Result<[URL], Error>) {
        guard let client = appState.client else { return }
        do {
            guard let url = try result.get().first else { return }
            isImportingPlaylists = true
            playlistTransferStatus = "Importing playlists…"
            Task {
                defer { isImportingPlaylists = false }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let count = try await PlaylistTransfer.importPlaylists(from: url, client: client)
                    playlistTransferStatus = "Imported \(count) playlist\(count == 1 ? "" : "s")"
                    VoltaNotificationCenter.shared.post(L(.notif_imported_playlists, count), tone: .success)
                } catch {
                    playlistTransferStatus = "Import failed: \(error.localizedDescription)"
                    VoltaNotificationCenter.shared.post(L(.notif_playlist_import_failed), tone: .error)
                }
            }
        } catch {
            playlistTransferStatus = "Import failed: \(error.localizedDescription)"
        }
    }

    func refreshPlaylistBackups() {
        guard let client = appState.client else {
            playlistBackupStatus = "Connect to a server to update playlist backups"
            return
        }
        guard !isRefreshingPlaylistBackups else { return }
        isRefreshingPlaylistBackups = true
        playlistBackupStatus = "Updating playlist backups..."
        Task {
            await PlaylistBackupStore.shared.backupAll(client: client)
            let count = PlaylistBackupStore.shared.snapshots.count
            let size = SettingsView.formatBytes(PlaylistBackupStore.shared.estimatedSizeBytes())
            updateDeletedPlaylistBackupsFromStore()
            playlistBackupStatus = "Backed up \(count) playlist\(count == 1 ? "" : "s") · \(size)"
            isRefreshingPlaylistBackups = false
            VoltaNotificationCenter.shared.post(L(.notif_playlist_backups_updated), tone: .success)
        }
    }

    func restoreDeletedPlaylist(_ snapshot: PlaylistBackupSnapshot) {
        guard let client = appState.client else {
            playlistBackupStatus = "Connect to a server to restore playlists"
            return
        }
        guard restoringPlaylistBackupID == nil else { return }
        restoringPlaylistBackupID = snapshot.id
        playlistBackupStatus = "Restoring \(snapshot.name)..."
        Task {
            do {
                let playlist = try await PlaylistBackupStore.shared.restore(snapshot, client: client)
                updateDeletedPlaylistBackupsFromStore()
                playlistBackupStatus = "Restored \(playlist.name)"
                VoltaNotificationCenter.shared.post(L(.notif_playlist_restored), tone: .success)
            } catch {
                playlistBackupStatus = "Restore failed: \(error.localizedDescription)"
                VoltaNotificationCenter.shared.post(L(.notif_playlist_restore_failed), tone: .error)
                AppLogger.shared.log("Playlist restore failed: \(error.localizedDescription)", category: .other, level: .error)
            }
            restoringPlaylistBackupID = nil
        }
    }

    func deletePlaylistBackup(_ snapshot: PlaylistBackupSnapshot) {
        PlaylistBackupStore.shared.delete(snapshot)
        updateDeletedPlaylistBackupsFromStore()
        playlistBackupStatus = "Deleted backup for \(snapshot.name)"
        VoltaNotificationCenter.shared.post(L(.notif_playlist_backup_deleted), tone: .success)
    }
}
