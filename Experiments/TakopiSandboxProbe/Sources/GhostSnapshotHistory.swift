import Foundation

/// Capturas guardadas voluntariamente en el contenedor de esta aplicación.
/// Solo son nombres de rutas; nunca contenidos de archivos.
struct GhostSavedSnapshot: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let source: String
    let paths: [String]

    var numberOfPaths: Int { paths.count }
}

enum GhostHistoryError: LocalizedError {
    case emptySnapshot
    case tooManySnapshots
    case tooManyPaths

    var errorDescription: String? {
        switch self {
        case .emptySnapshot: return "No hay rutas que guardar."
        case .tooManySnapshots: return "El historial tiene ocho capturas. Borra una antes de guardar otra."
        case .tooManyPaths: return "La captura contiene demasiadas rutas para almacenarla."
        }
    }
}

/// Almacenamiento local de opt-in, sin sincronización ni telemetría.
/// No guarda capturas automáticamente: la persona debe pulsar Guardar.
struct GhostSnapshotHistory {
    static let maximumSnapshots = 8
    static let maximumPaths = 30_000
    private let directory: URL

    init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first ??
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        self.directory = directory ?? base.appendingPathComponent("TakopiGhostHistory",
                                                                 isDirectory: true)
    }

    private func snapshotFile(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".json", isDirectory: false)
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        var folder = directory
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try folder.setResourceValues(attributes)
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: directory.path
        )
        #endif
    }

    func list() throws -> [GhostSavedSnapshot] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let urls = try fm.contentsOfDirectory(at: directory,
                                              includingPropertiesForKeys: nil)
        var records: [GhostSavedSnapshot] = []
        let decoder = JSONDecoder()
        for url in urls where url.pathExtension == "json" {
            guard let uuid = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  url == snapshotFile(uuid) else { continue }
            let data = try Data(contentsOf: url)
            let record = try decoder.decode(GhostSavedSnapshot.self, from: data)
            guard record.id == uuid else { continue }
            records.append(record)
        }
        return records.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func save(paths: Set<String>, source: String = "Barrido local") throws -> GhostSavedSnapshot {
        let valid = Set(paths.filter { $0.hasPrefix("/") && $0.utf8.count <= 4096 })
        guard !valid.isEmpty else { throw GhostHistoryError.emptySnapshot }
        guard valid.count <= Self.maximumPaths else { throw GhostHistoryError.tooManyPaths }
        guard try list().count < Self.maximumSnapshots else {
            throw GhostHistoryError.tooManySnapshots
        }

        try prepareDirectory()
        let record = GhostSavedSnapshot(id: UUID(), createdAt: Date(),
                                        source: String(source.prefix(64)),
                                        paths: valid.sorted())
        let destination = snapshotFile(record.id)
        let data = try JSONEncoder().encode(record)
        try data.write(to: destination, options: .atomic)

        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: destination.path
        )
        #endif

        return record
    }

    func delete(id: UUID) throws {
        let file = snapshotFile(id)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }
}
