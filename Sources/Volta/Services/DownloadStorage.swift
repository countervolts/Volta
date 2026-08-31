import Foundation
import UIKit
import UniformTypeIdentifiers

/// Durable downloaded media can live either inside Volta's private container
/// or in Documents/Volta, which Files exposes as On My iPhone/Volta.
enum DownloadStorageLocation: String, CaseIterable, Identifiable, Sendable {
    case privateStorage
    case filesApp

    static let preferenceKey = "downloadStorageLocation"

    var id: String { rawValue }
    var displayName: String { self == .privateStorage ? "Private Storage" : "Files App" }
    var detail: String {
        self == .privateStorage
            ? "Only Volta can access downloaded media."
            : "On My iPhone > Volta in Files. Editing files can break downloads."
    }

    static var current: DownloadStorageLocation {
        DownloadStorageLocation(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .privateStorage
    }

    static func setCurrent(_ location: DownloadStorageLocation) {
        UserDefaults.standard.set(location.rawValue, forKey: preferenceKey)
    }

    private static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Volta", isDirectory: true)
    }

    static var filesRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Volta", isDirectory: true)
    }

    func musicDirectory() -> URL {
        switch self {
        case .privateStorage: return Self.appSupport.appendingPathComponent("Downloads", isDirectory: true)
        case .filesApp: return Self.filesRoot.appendingPathComponent("Music", isDirectory: true)
        }
    }

    func artworkDirectory() -> URL {
        switch self {
        case .privateStorage: return Self.appSupport.appendingPathComponent("OfflineArtwork", isDirectory: true)
        case .filesApp: return Self.filesRoot.appendingPathComponent("Artwork", isDirectory: true)
        }
    }

    func lyricsDirectory() -> URL {
        switch self {
        case .privateStorage: return Self.appSupport.appendingPathComponent("Lyrics", isDirectory: true)
        case .filesApp: return Self.filesRoot.appendingPathComponent("Lyrics", isDirectory: true)
        }
    }

    static func prepareFilesRoot() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: filesRoot, withIntermediateDirectories: true)
        for name in ["Music", "Artwork", "Lyrics"] {
            try manager.createDirectory(at: filesRoot.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true)
        }
        let notice = filesRoot.appendingPathComponent("READ ME.txt")
        if !manager.fileExists(atPath: notice.path) {
            let text = "Volta downloaded media\n\nDo not edit, rename, move, or delete files in this folder while Volta uses them. Changes can corrupt downloaded music, artwork, lyrics, and offline playback. Use Volta's Download Manager to move or remove downloaded data.\n"
            try text.data(using: .utf8)?.write(to: notice, options: .atomic)
        }
    }
}

enum DownloadStorageTransferMethod: String, CaseIterable, Identifiable, Sendable {
    case move
    case copyThenDelete

    var id: String { rawValue }
    var displayName: String { self == .move ? "Move" : "Copy, then delete original" }
}

enum DownloadStorageTransfer {
    static func validate(from source: URL, to destination: URL) throws {
        guard source.standardizedFileURL != destination.standardizedFileURL else { return }
        let manager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        if manager.fileExists(atPath: destination.path),
           let entries = try? manager.contentsOfDirectory(atPath: destination.path),
           !entries.isEmpty {
            throw CocoaError(.fileWriteFileExists)
        }
    }

    static func transfer(from source: URL, to destination: URL, method: DownloadStorageTransferMethod) throws {
        guard source.standardizedFileURL != destination.standardizedFileURL else { return }
        try validate(from: source, to: destination)
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        guard manager.fileExists(atPath: source.path) else {
            try manager.createDirectory(at: destination, withIntermediateDirectories: true)
            return
        }
        switch method {
        case .move:
            try manager.moveItem(at: source, to: destination)
        case .copyThenDelete:
            try manager.copyItem(at: source, to: destination)
            try manager.removeItem(at: source)
        }
    }
}

/// Presents Apple's Files browser directly at Volta's shared Documents folder.
/// `UIApplication.open(fileURL:)` does not navigate Files to sandbox folders.
enum FilesFolderBrowser {
    @MainActor
    static func presentVoltaFolder() {
        do {
            try DownloadStorageLocation.prepareFilesRoot()
        } catch {
            VoltaNotificationCenter.shared.post("Could not open Volta folder", tone: .error)
            return
        }
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = (scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first)?.rootViewController
        else { return }

        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.directoryURL = DownloadStorageLocation.filesRoot
        presenter.present(picker, animated: true)
    }
}

@MainActor
final class DownloadStorageManager: ObservableObject {
    static let shared = DownloadStorageManager()

    @Published private(set) var isMigrating = false
    @Published private(set) var progress = 0.0
    @Published private(set) var status = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var location = DownloadStorageLocation.current

    var isOfflinePlaybackBlocked: Bool {
        NetworkMonitor.shared.connection == .none
            && AppState.shared.audioPlayer.isPlaying
            && !DeveloperExperiments.allowStorageTransferDuringOfflinePlayback
    }

    var migrationBlockReason: String? {
        if isOfflinePlaybackBlocked {
            return "Stop offline playback before transferring downloaded data."
        }
        if !DownloadService.shared.transfers.isEmpty
            || DownloadService.shared.bulkProgress.isRunning
            || LyricsBulkDownloader.shared.isRunning
            || !LyricsBulkDownloader.shared.companionTransfers.isEmpty
            || ArtworkLibraryDownloader.shared.isRunning {
            return "Stop all music, artwork, and lyrics downloads before transferring."
        }
        return nil
    }

    var canMigrate: Bool {
        !isMigrating && migrationBlockReason == nil
    }

    func migrate(to destination: DownloadStorageLocation, method: DownloadStorageTransferMethod) {
        guard destination != location, canMigrate else { return }
        isMigrating = true
        progress = 0
        errorMessage = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            let source = location
            var movedMusic = false
            var movedArtwork = false
            do {
                if destination == .filesApp { try DownloadStorageLocation.prepareFilesRoot() }
                try DownloadStorageTransfer.validate(from: source.musicDirectory(), to: destination.musicDirectory())
                try DownloadStorageTransfer.validate(from: source.artworkDirectory(), to: destination.artworkDirectory())
                try DownloadStorageTransfer.validate(from: source.lyricsDirectory(), to: destination.lyricsDirectory())

                status = "Moving music…"
                try DownloadService.shared.migrateStorage(to: destination, method: method)
                movedMusic = true
                progress = 0.34
                status = "Moving artwork…"
                try await ArtworkLoader.shared.migrateStorage(to: destination, method: method)
                movedArtwork = true
                progress = 0.67
                status = "Moving lyrics…"
                try await LyricsService.shared.migrateStorage(to: destination, method: method)
                progress = 1
                DownloadStorageLocation.setCurrent(destination)
                location = destination
                status = "Done"
            } catch {
                // A partial migration must never leave storage split between
                // destinations. Every completed directory is returned first.
                status = "Restoring original storage…"
                if movedArtwork { try? await ArtworkLoader.shared.migrateStorage(to: source, method: method) }
                if movedMusic { try? DownloadService.shared.migrateStorage(to: source, method: method) }
                errorMessage = error.localizedDescription
                status = "Migration stopped"
            }
            isMigrating = false
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
