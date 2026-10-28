import Foundation
import ZIPFoundation
import CryptoKit

/// Portably exports the ORIGINAL encrypted Vault bytes. Never decrypts user data.
/// A .tkvault is a narrowly validated ZIP; it is not a conventional plaintext ZIP.
enum TakopiVaultBackup {
    enum BackupError: LocalizedError {
        case invalidPackage
        case missingEncryptedFile
        case tooManyEntries
        case vaultChanged
        case notEnoughSpace

        var errorDescription: String? {
            switch self {
            case .invalidPackage:
                return "La copia de Takopi Vault está dañada, incompleta o contiene rutas no permitidas."
            case .missingEncryptedFile:
                return "Falta un archivo cifrado de la bóveda. No se ha creado una copia incompleta."
            case .tooManyEntries:
                return "La copia contiene demasiados archivos."
            case .vaultChanged:
                return "La bóveda cambió mientras se creaba la copia. Reintenta el respaldo."
            case .notEnoughSpace:
                return "No hay suficiente espacio para preparar o restaurar la copia cifrada."
            }
        }
    }

    struct FileRecord: Codable {
        let path: String
        let size: Int64
        let sha256: String
    }

    struct Manifest: Codable {
        let format: String
        let version: Int
        let files: [FileRecord]
    }

    private static let maxFiles = 100_000
    private static let maxManifestBytes: UInt64 = 32 * 1024 * 1024
    private static let maxTotalBytes: Int64 = 500 * 1024 * 1024 * 1024
    private static let configFiles: Set<String> = [
        "vault.json", "vault.backup.json", "index.ssv", "index.previous.ssv"
    ]

    static func create(from root: URL) throws -> URL {
        let fm = FileManager.default
        var paths = configFiles.sorted()

        for (folder, ext) in [("blobs", "ssvb"), ("thumbnails", "nkt")] {
            let dir = root.appendingPathComponent(folder, isDirectory: true)
            let children = try fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            for child in children where child.pathExtension.lowercased() == ext {
                let path = folder + "/" + child.lastPathComponent
                guard allowedPath(path) else { throw BackupError.invalidPackage }
                paths.append(path)
            }
        }

        guard paths.count <= maxFiles else { throw BackupError.tooManyEntries }
        paths.sort()

        let tempRoot = fm.temporaryDirectory.appendingPathComponent(
            "TakopiVaultBackup-" + UUID().uuidString, isDirectory: true
        )
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let result = tempRoot.appendingPathComponent("Takopi-Vault.tkvault")
        let manifestURL = tempRoot.appendingPathComponent("manifest.json")
        var committed = false
        defer {
            if !committed { try? fm.removeItem(at: tempRoot) }
        }

        var files: [FileRecord] = []
        var total: Int64 = 0
        for path in paths {
            try Task.checkCancellation()
            let source = root.appendingPathComponent(path)
            let values = try source.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size >= 0 else {
                throw BackupError.missingEncryptedFile
            }
            let added = total.addingReportingOverflow(Int64(size))
            guard !added.overflow, added.partialValue <= maxTotalBytes else {
                throw BackupError.tooManyEntries
            }
            total = added.partialValue
            files.append(FileRecord(path: path, size: Int64(size),
                                    sha256: try digest(source)))
        }

        let manifest = Manifest(format: "takopi-encrypted-vault",
                                version: 1, files: files)
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)

        let zip = try ZIPFoundation.Archive(url: result, accessMode: .create)
        try zip.addEntry(with: "manifest.json", fileURL: manifestURL,
                         compressionMethod: .none)
        for record in files {
            try Task.checkCancellation()
            try zip.addEntry(with: record.path,
                             fileURL: root.appendingPathComponent(record.path),
                             compressionMethod: .none)
        }

        // A live mutation during ZIP creation would make a misleading backup.
        for name in ["index.ssv", "vault.json"] {
            guard let record = files.first(where: { $0.path == name }),
                  try digest(root.appendingPathComponent(name)) == record.sha256 else {
                throw BackupError.vaultChanged
            }
        }
        try fm.removeItem(at: manifestURL)
        committed = true
        return result
    }

    /// Extracts to a distinct sibling staging folder; never writes into the live vault.
    /// Caller authenticates the *restored* encrypted index with the user's password
    /// before swapping anything on disk.
    static func stage(_ archiveURL: URL, nextTo liveVault: URL) throws -> URL {
        let fm = FileManager.default
        let sibling = liveVault.deletingLastPathComponent()
        let stage = sibling.appendingPathComponent(
            ".TakopiVault-restore-" + UUID().uuidString, isDirectory: true
        )
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        var committed = false
        defer { if !committed { try? fm.removeItem(at: stage) } }

        guard let zip = ZIPFoundation.Archive(url: archiveURL, accessMode: .read) else {
            throw BackupError.invalidPackage
        }
        var names = Set<String>()
        var expectedTotal: Int64 = 0
        var manifest: ZIPFoundation.Entry?
        var entries: [ZIPFoundation.Entry] = []

        for item in zip {
            try Task.checkCancellation()
            guard item.type == .file, names.insert(item.path).inserted,
                  item.uncompressedSize <= UInt64(Int64.max) else {
                throw BackupError.invalidPackage
            }
            if item.path == "manifest.json" {
                guard item.uncompressedSize <= maxManifestBytes else {
                    throw BackupError.invalidPackage
                }
                manifest = item
            } else {
                guard allowedPath(item.path) else { throw BackupError.invalidPackage }
                let added = expectedTotal.addingReportingOverflow(Int64(item.uncompressedSize))
                guard !added.overflow, added.partialValue <= maxTotalBytes else {
                    throw BackupError.tooManyEntries
                }
                expectedTotal = added.partialValue
                entries.append(item)
            }
            guard names.count <= maxFiles + 1 else {
                throw BackupError.tooManyEntries
            }
        }

        guard let manifest, configFiles.isSubset(of: names) else {
            throw BackupError.invalidPackage
        }

        // Ensure the device has room before extracting very large archives.
        if let available = try? sibling.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage,
           available > 0 && expectedTotal > available {
            throw BackupError.notEnoughSpace
        }

        let manifestURL = stage.appendingPathComponent("manifest.json")
        _ = try zip.extract(manifest, to: manifestURL)
        let manifestData = try Data(contentsOf: manifestURL)
        let parsed = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard parsed.version == 1, parsed.format == "takopi-encrypted-vault",
              parsed.files.count == entries.count else {
            throw BackupError.invalidPackage
        }
        let indexed = Dictionary(uniqueKeysWithValues: parsed.files.map { ($0.path, $0) })
        guard indexed.count == parsed.files.count,
              Set(indexed.keys) == Set(entries.map(\.path)) else {
            throw BackupError.invalidPackage
        }

        for entry in entries {
            try Task.checkCancellation()
            guard let expected = indexed[entry.path],
                  expected.size == Int64(entry.uncompressedSize),
                  expected.sha256.count == 64 else {
                throw BackupError.invalidPackage
            }
            let output = stage.appendingPathComponent(entry.path)
            try fm.createDirectory(
                at: output.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            _ = try zip.extract(entry, to: output)
            guard try digest(output) == expected.sha256 else {
                throw BackupError.invalidPackage
            }
            try PrivateVaultSession.applyProtection(to: output)
        }
        try fm.removeItem(at: manifestURL)
        try PrivateVaultSession.applyProtection(to: stage)
        committed = true
        return stage
    }

    static func removeTemporaryBackup(_ url: URL?) {
        guard let url else { return }
        let parent = url.deletingLastPathComponent()
        if parent.lastPathComponent.hasPrefix("TakopiVaultBackup-") {
            try? FileManager.default.removeItem(at: parent)
        }
    }

    private static func allowedPath(_ path: String) -> Bool {
        if configFiles.contains(path) { return true }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let folder = String(parts[0]), file = String(parts[1])
        guard !file.contains("\\"), !file.contains(":"), !file.contains("\0"),
              !file.hasPrefix("."), !file.hasSuffix(".") else { return false }
        if folder == "blobs" && file.hasSuffix(".ssvb") {
            return UUID(uuidString: String(file.dropLast(5))) != nil
        }
        if folder == "thumbnails" && file.hasSuffix(".nkt") {
            return UUID(uuidString: String(file.dropLast(4))) != nil
        }
        return false
    }

    private static func digest(_ url: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let data = try input.read(upToCount: 256 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
