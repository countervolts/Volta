import Foundation

struct ZipSourceFile {
    let url: URL
    let path: String
}

enum AppDataExporter {
    static func makeArchive() async throws -> URL {
        try await DeveloperExperiments.runThrowingSync(priority: .utility) {
            try makeArchiveSync()
        }
    }

    private static func makeArchiveSync() throws -> URL {
        let fm = FileManager.default
        let stamp = Self.stamp()
        let temp = fm.temporaryDirectory
        let archiveURL = temp.appendingPathComponent("Volta-App-Data-\(stamp).zip")
        let manifestURL = temp.appendingPathComponent("Volta-App-Data-\(stamp).txt")
        try? fm.removeItem(at: archiveURL)
        try? fm.removeItem(at: manifestURL)

        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let roots: [(URL, String)] = [
            (documents, "Documents"),
            (library.appendingPathComponent("Application Support", isDirectory: true), "Library/Application Support"),
            (library.appendingPathComponent("Caches", isDirectory: true), "Library/Caches"),
            (library.appendingPathComponent("Preferences", isDirectory: true), "Library/Preferences"),
        ]

        var files = roots.flatMap { filesUnder(root: $0.0, label: $0.1) }
        let totalBytes = files.reduce(0) { $0 + fileSize(at: $1.url) }
        let manifest = [
            "Volta app data export",
            "Created: \(Date().formatted(date: .complete, time: .complete))",
            "Bundle: \(Bundle.main.bundleIdentifier ?? "?")",
            "Files: \(files.count)",
            "Size: \(ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file))",
            "",
            "Included roots:",
            "Documents",
            "Library/Application Support",
            "Library/Caches",
            "Library/Preferences",
            "",
            "Excluded:",
            "Library/Application Support/Volta/servers.json (server addresses and usernames)",
            "Library/Caches/artwork",
            "Library/Caches/live-artwork",
            "Spotlight thumbnail caches",
            "",
            "Note: server passwords are stored in Keychain and are never exported.",
        ].joined(separator: "\n")
        try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
        files.insert(ZipSourceFile(url: manifestURL, path: "Volta-App-Data.txt"), at: 0)

        try ZipArchiveWriter.write(files: files, to: archiveURL)
        try? fm.removeItem(at: manifestURL)
        return archiveURL
    }

    private static func filesUnder(root: URL, label: String) -> [ZipSourceFile] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path),
              let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: []
              ) else { return [] }

        let rootPath = root.standardizedFileURL.path
        var files: [ZipSourceFile] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            let filePath = url.standardizedFileURL.path
            guard filePath.hasPrefix(rootPath + "/") else { continue }
            let suffix = String(filePath.dropFirst(rootPath.count + 1))
            let zipPath = (label + "/" + suffix).replacingOccurrences(of: "\\", with: "/")
            guard !shouldExclude(zipPath: zipPath) else { continue }
            files.append(ZipSourceFile(url: url, path: zipPath))
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func shouldExclude(zipPath: String) -> Bool {
        let lower = zipPath.lowercased()
        if lower == "library/application support/volta/servers.json" { return true }
        if lower.hasPrefix("library/caches/artwork/") { return true }
        if lower.hasPrefix("library/caches/live-artwork/") { return true }
        if lower.contains("spotlight") && (lower.contains("thumbnail") || lower.contains("thumb")) {
            return true
        }
        return false
    }

    private static func fileSize(at url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

enum ZipArchiveWriter {
    static func write(files: [ZipSourceFile], to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = fm.createFile(atPath: destination.path, contents: nil)

        let out = try FileHandle(forWritingTo: destination)
        defer { try? out.close() }

        var offset: UInt64 = 0
        var centralEntries: [CentralEntry] = []

        func writeData(_ data: Data) throws {
            try out.write(contentsOf: data)
            offset += UInt64(data.count)
        }

        for source in files {
            let nameData = Data(source.path.utf8)
            guard nameData.count <= Int(UInt16.max) else { continue }

            let size = UInt64(AppDataExporterFileSize.url(source.url))
            let localOffset = offset
            let localUsesZip64 = size > UInt64(UInt32.max)
            let modified = (try? source.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let dos = DosDateTime(date: modified)
            let localExtra = localUsesZip64 ? zip64Extra(values: [size, size]) : Data()

            var local = Data()
            local.appendLE(UInt32(0x04034b50))
            local.appendLE(UInt16(localUsesZip64 ? 45 : 20))
            local.appendLE(UInt16(0x0808))
            local.appendLE(UInt16(0))
            local.appendLE(dos.time)
            local.appendLE(dos.date)
            local.appendLE(UInt32(0))
            local.appendLE(localUsesZip64 ? UInt32.max : UInt32(0))
            local.appendLE(localUsesZip64 ? UInt32.max : UInt32(0))
            local.appendLE(UInt16(nameData.count))
            local.appendLE(UInt16(localExtra.count))
            local.append(nameData)
            local.append(localExtra)
            try writeData(local)

            var crc = CRC32()
            var written: UInt64 = 0
            let input = try FileHandle(forReadingFrom: source.url)
            while true {
                let chunk = try input.read(upToCount: 1_048_576) ?? Data()
                if chunk.isEmpty { break }
                crc.update(chunk)
                try writeData(chunk)
                written += UInt64(chunk.count)
            }
            try? input.close()

            let checksum = crc.checksum
            var descriptor = Data()
            descriptor.appendLE(UInt32(0x08074b50))
            descriptor.appendLE(checksum)
            if localUsesZip64 {
                descriptor.appendLE(written)
                descriptor.appendLE(written)
            } else {
                descriptor.appendLE(UInt32(written))
                descriptor.appendLE(UInt32(written))
            }
            try writeData(descriptor)

            centralEntries.append(CentralEntry(
                path: source.path,
                size: written,
                crc32: checksum,
                localHeaderOffset: localOffset,
                modified: modified,
                localUsesZip64: localUsesZip64
            ))
        }

        let centralStart = offset
        for entry in centralEntries {
            try writeData(centralDirectoryRecord(for: entry))
        }
        let centralSize = offset - centralStart
        let needsZip64End = centralEntries.count > Int(UInt16.max)
            || centralSize > UInt64(UInt32.max)
            || centralStart > UInt64(UInt32.max)

        if needsZip64End {
            let zip64EndOffset = offset
            try writeData(zip64EndRecord(
                entryCount: UInt64(centralEntries.count),
                centralSize: centralSize,
                centralOffset: centralStart
            ))
            try writeData(zip64Locator(zip64EndOffset: zip64EndOffset))
        }

        try writeData(endRecord(
            entryCount: centralEntries.count,
            centralSize: centralSize,
            centralOffset: centralStart,
            forceZip64: needsZip64End
        ))
    }

    private static func centralDirectoryRecord(for entry: CentralEntry) -> Data {
        let nameData = Data(entry.path.utf8)
        let sizeNeedsZip64 = entry.size > UInt64(UInt32.max)
        let offsetNeedsZip64 = entry.localHeaderOffset > UInt64(UInt32.max)
        let needsZip64 = entry.localUsesZip64 || sizeNeedsZip64 || offsetNeedsZip64
        let dos = DosDateTime(date: entry.modified)

        var zip64Values: [UInt64] = []
        if sizeNeedsZip64 || entry.localUsesZip64 {
            zip64Values.append(entry.size)
            zip64Values.append(entry.size)
        }
        if offsetNeedsZip64 {
            zip64Values.append(entry.localHeaderOffset)
        }
        let extra = zip64Values.isEmpty ? Data() : zip64Extra(values: zip64Values)

        var data = Data()
        data.appendLE(UInt32(0x02014b50))
        data.appendLE(UInt16(needsZip64 ? 45 : 20))
        data.appendLE(UInt16(needsZip64 ? 45 : 20))
        data.appendLE(UInt16(0x0808))
        data.appendLE(UInt16(0))
        data.appendLE(dos.time)
        data.appendLE(dos.date)
        data.appendLE(entry.crc32)
        data.appendLE(sizeNeedsZip64 || entry.localUsesZip64 ? UInt32.max : UInt32(entry.size))
        data.appendLE(sizeNeedsZip64 || entry.localUsesZip64 ? UInt32.max : UInt32(entry.size))
        data.appendLE(UInt16(nameData.count))
        data.appendLE(UInt16(extra.count))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt32(0))
        data.appendLE(offsetNeedsZip64 ? UInt32.max : UInt32(entry.localHeaderOffset))
        data.append(nameData)
        data.append(extra)
        return data
    }

    private static func zip64EndRecord(entryCount: UInt64, centralSize: UInt64, centralOffset: UInt64) -> Data {
        var data = Data()
        data.appendLE(UInt32(0x06064b50))
        data.appendLE(UInt64(44))
        data.appendLE(UInt16(45))
        data.appendLE(UInt16(45))
        data.appendLE(UInt32(0))
        data.appendLE(UInt32(0))
        data.appendLE(entryCount)
        data.appendLE(entryCount)
        data.appendLE(centralSize)
        data.appendLE(centralOffset)
        return data
    }

    private static func zip64Locator(zip64EndOffset: UInt64) -> Data {
        var data = Data()
        data.appendLE(UInt32(0x07064b50))
        data.appendLE(UInt32(0))
        data.appendLE(zip64EndOffset)
        data.appendLE(UInt32(1))
        return data
    }

    private static func endRecord(
        entryCount: Int,
        centralSize: UInt64,
        centralOffset: UInt64,
        forceZip64: Bool
    ) -> Data {
        var data = Data()
        data.appendLE(UInt32(0x06054b50))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(forceZip64 ? UInt16.max : UInt16(entryCount))
        data.appendLE(forceZip64 ? UInt16.max : UInt16(entryCount))
        data.appendLE(forceZip64 ? UInt32.max : UInt32(centralSize))
        data.appendLE(forceZip64 ? UInt32.max : UInt32(centralOffset))
        data.appendLE(UInt16(0))
        return data
    }

    private static func zip64Extra(values: [UInt64]) -> Data {
        var body = Data()
        values.forEach { body.appendLE($0) }
        var data = Data()
        data.appendLE(UInt16(0x0001))
        data.appendLE(UInt16(body.count))
        data.append(body)
        return data
    }
}

private enum AppDataExporterFileSize {
    static func url(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}

private struct CentralEntry {
    let path: String
    let size: UInt64
    let crc32: UInt32
    let localHeaderOffset: UInt64
    let modified: Date
    let localUsesZip64: Bool
}

private struct DosDateTime {
    let date: UInt16
    let time: UInt16

    init(date input: Date) {
        let comps = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: input
        )
        let year = min(max(comps.year ?? 1980, 1980), 2107)
        let month = min(max(comps.month ?? 1, 1), 12)
        let day = min(max(comps.day ?? 1, 1), 31)
        let hour = min(max(comps.hour ?? 0, 0), 23)
        let minute = min(max(comps.minute ?? 0, 0), 59)
        let second = min(max(comps.second ?? 0, 0), 59)
        self.date = UInt16((year - 1980) << 9 | month << 5 | day)
        self.time = UInt16(hour << 11 | minute << 5 | second / 2)
    }
}

private struct CRC32 {
    private static let table: [UInt32] = (0...255).map { i in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) == 1 ? (0xedb88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    private var value: UInt32 = 0xffffffff

    mutating func update(_ data: Data) {
        for byte in data {
            let index = Int((value ^ UInt32(byte)) & 0xff)
            value = Self.table[index] ^ (value >> 8)
        }
    }

    var checksum: UInt32 {
        value ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
