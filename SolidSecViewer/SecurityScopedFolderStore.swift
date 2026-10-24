import Foundation
import Combine

private struct SavedExplorerLocation: Codable {
    let id: UUID
    let name: String
    let bookmarkData: Data
}

@MainActor
final class SecurityScopedFolderStore: ObservableObject {
    @Published private(set) var locations: [ExplorerStorageLocation] = []
    @Published var lastError: String?
    @Published private(set) var unavailable: [ExplorerUnavailableLocation] = []

    private let defaultsKey = "NikaidoExplorer.AuthorizedLocations.v1"
    private var scopedURLs: [UUID: URL] = [:]

    init() {
        installLocalLocation()
        restoreSavedLocations()
    }

    deinit {
        for url in scopedURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    var localLocation: ExplorerStorageLocation? {
        locations.first(where: { $0.kind == .local })
    }

    @discardableResult
    func addAuthorizedFolder(_ url: URL) -> ExplorerStorageLocation? {
        lastError = nil

        let picked = url.standardizedFileURL

        // Misma carpeta aunque iOS la entregue con otra ruta (por ejemplo
        // /var frente a /private/var): se compara también la identidad real.
        if let existing = locations.first(where: {
            isSameFolder($0.rootURL, picked)
        }) {
            return existing
        }

        // A picker may hand our own Documents directory back to us. It does
        // not need a sandbox extension and should not be duplicated as an
        // "external" location.
        if let local = localLocation,
           isDescendant(canonical(picked), of: canonical(local.rootURL))
        {
            return local
        }

        // Picker URLs normally provide a security-scoped capability. Some iOS
        // File Provider/bookmark paths can nevertheless report `false` from
        // startAccessingSecurityScopedResource() even while coordinated access
        // is valid, so verify actual directory access before rejecting it.
        var normalized = picked
        var startedScope = normalized.startAccessingSecurityScopedResource()
        var probe = probeDirectoryAccessDetailed(normalized)

        if !startedScope && !probe.ok {
            // Segunda vía: pasar la URL por un bookmark. En algunas
            // ubicaciones locales la URL resuelta sí conserva el permiso que
            // concedió el selector de iOS.
            if let data = try? makeBookmark(for: picked) {
                var stale = false

                if let resolved = try? URL(
                    resolvingBookmarkData: data,
                    options: [.withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ) {
                    let candidate = resolved.standardizedFileURL
                    let candidateScope = candidate.startAccessingSecurityScopedResource()
                    let candidateProbe = probeDirectoryAccessDetailed(candidate)
                    _ = stale

                    if candidateScope || candidateProbe.ok {
                        normalized = candidate
                        startedScope = candidateScope
                        probe = candidateProbe
                    }
                }
            }
        }

        guard startedScope || probe.ok else {
            lastError = "iOS no concedió acceso utilizable a esa carpeta. "
                + "Elige una carpeta de Archivos que hayas creado tú (en iCloud Drive "
                + "o en \"En mi iPhone\"); iOS no permite carpetas del sistema ni de "
                + "otras apps.\n\n"
                + "Detalle técnico: permiso del selector = "
                + (startedScope ? "sí" : "no")
                + "; lectura = \(probe.detail); ruta = \(normalized.path)"
            return nil
        }

        let id = UUID()
        let name = normalized.lastPathComponent.isEmpty
            ? "Ubicación autorizada"
            : normalized.lastPathComponent

        if startedScope {
            scopedURLs[id] = normalized
        }

        var persistent = false

        do {
            let bookmark = try makeBookmark(for: normalized)
            var saved = loadSavedRecords()

            saved.removeAll(where: {
                resolvedPath(for: $0) == normalized.path
            })

            // Volver a autorizar una carpeta cuya referencia había caducado
            // reemplaza esa referencia en lugar de dejar un duplicado.
            let replacedIDs = Set(
                unavailable.filter { $0.name == name }.map(\.id)
            )

            if !replacedIDs.isEmpty {
                saved.removeAll(where: { replacedIDs.contains($0.id) })
                unavailable.removeAll(where: { replacedIDs.contains($0.id) })
            }

            saved.append(
                SavedExplorerLocation(
                    id: id,
                    name: name,
                    bookmarkData: bookmark
                )
            )
            persist(saved)
            persistent = true
        } catch {
            // The security scope remains valid for the current process. Make
            // that explicit instead of discarding a folder the user just chose.
            lastError = "La carpeta quedó autorizada para esta sesión, pero "
                + "iOS no permitió guardar el acceso para próximos inicios: "
                + ExplorerErrorText.message(for: error)
        }

        let location = ExplorerStorageLocation(
            id: id,
            name: name,
            rootURL: normalized,
            kind: .authorized,
            isPersistentReference: persistent
        )
        locations.append(location)
        return location
    }

    /// Quita una referencia caducada de la lista y de los datos guardados.
    func removeUnavailable(_ item: ExplorerUnavailableLocation) {
        unavailable.removeAll(where: { $0.id == item.id })

        var saved = loadSavedRecords()
        saved.removeAll(where: { $0.id == item.id })
        persist(saved)
    }

    /// Vuelve a intentar abrir las referencias que no estaban disponibles
    /// (por ejemplo, porque un disco o iCloud tardó en responder).
    func retryUnavailable() {
        let pending = Set(unavailable.map(\.id))
        guard !pending.isEmpty else { return }

        let records = loadSavedRecords().filter { pending.contains($0.id) }
        var stillUnavailable: [ExplorerUnavailableLocation] = []

        for record in records {
            var stale = false

            guard let resolved = try? URL(
                resolvingBookmarkData: record.bookmarkData,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                stillUnavailable.append(
                    ExplorerUnavailableLocation(
                        id: record.id,
                        name: record.name,
                        reason: "La carpeta se movió, se eliminó o su referencia caducó."
                    )
                )
                continue
            }

            let url = resolved.standardizedFileURL
            let startedScope = url.startAccessingSecurityScopedResource()

            guard startedScope || probeDirectoryAccess(url) else {
                stillUnavailable.append(
                    ExplorerUnavailableLocation(
                        id: record.id,
                        name: record.name,
                        reason: "iOS no da acceso a esta carpeta ahora. Vuelve a añadirla desde Archivos."
                    )
                )
                continue
            }

            if startedScope {
                scopedURLs[record.id] = url
            }

            if stale, let refreshed = try? makeBookmark(for: url) {
                var saved = loadSavedRecords()

                if let index = saved.firstIndex(where: { $0.id == record.id }) {
                    saved[index] = SavedExplorerLocation(
                        id: record.id,
                        name: record.name,
                        bookmarkData: refreshed
                    )
                    persist(saved)
                }
            }

            locations.append(
                ExplorerStorageLocation(
                    id: record.id,
                    name: record.name,
                    rootURL: url,
                    kind: .authorized,
                    isPersistentReference: !stale
                )
            )
        }

        unavailable = stillUnavailable
    }

    func remove(_ location: ExplorerStorageLocation) {
        guard location.kind == .authorized else { return }

        if let url = scopedURLs.removeValue(forKey: location.id) {
            url.stopAccessingSecurityScopedResource()
        }

        locations.removeAll(where: { $0.id == location.id })

        var saved = loadSavedRecords()
        saved.removeAll(where: { $0.id == location.id })
        persist(saved)
    }

    func location(containing url: URL) -> ExplorerStorageLocation? {
        let candidate = canonical(url)

        return locations
            .filter { isDescendant(candidate, of: canonical($0.rootURL)) }
            .max(by: {
                $0.rootURL.path.count < $1.rootURL.path.count
            })
    }

    func isAuthorized(_ url: URL) -> Bool {
        location(containing: url) != nil
    }

    /// Re-acquires any security scopes that may have been released by a future
    /// lifecycle change. Every successful start is retained in scopedURLs so
    /// there is a matching stop in deinit/remove.
    func refreshPersistentReferences() {
        for location in locations where location.kind == .authorized {
            guard scopedURLs[location.id] == nil else {
                continue
            }

            if location.rootURL.startAccessingSecurityScopedResource() {
                scopedURLs[location.id] = location.rootURL
            }
        }

        if !unavailable.isEmpty {
            retryUnavailable()
        }
    }

    private func installLocalLocation() {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        try? FileManager.default.createDirectory(
            at: documents,
            withIntermediateDirectories: true
        )

        locations = [
            ExplorerStorageLocation(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Takopi Explorer",
                rootURL: documents.standardizedFileURL,
                kind: .local,
                isPersistentReference: true
            )
        ]
    }

    private func restoreSavedLocations() {
        var records = loadSavedRecords()
        var refreshedRecords: [SavedExplorerLocation] = []
        var changed = false

        for record in records {
            var stale = false

            do {
                let url = try URL(
                    resolvingBookmarkData: record.bookmarkData,
                    options: [.withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ).standardizedFileURL

                let startedScope = url.startAccessingSecurityScopedResource()

                guard startedScope || probeDirectoryAccess(url) else {
                    // Keep the bookmark so the user can retry or remove it;
                    // it is listed as unavailable, not as a live location.
                    refreshedRecords.append(record)
                    unavailable.append(
                        ExplorerUnavailableLocation(
                            id: record.id,
                            name: record.name,
                            reason: "iOS no da acceso a esta carpeta ahora. Vuelve a añadirla desde Archivos."
                        )
                    )
                    continue
                }

                if startedScope {
                    scopedURLs[record.id] = url
                }

                var effectiveRecord = record
                var persistent = !stale

                if stale {
                    do {
                        effectiveRecord = SavedExplorerLocation(
                            id: record.id,
                            name: record.name,
                            bookmarkData: try makeBookmark(for: url)
                        )
                        persistent = true
                        changed = true
                    } catch {
                        persistent = false
                    }
                }

                refreshedRecords.append(effectiveRecord)
                locations.append(
                    ExplorerStorageLocation(
                        id: record.id,
                        name: record.name,
                        rootURL: url,
                        kind: .authorized,
                        isPersistentReference: persistent
                    )
                )
            } catch {
                // The folder was moved/deleted or the bookmark expired. Keep
                // the record visible so the user can see it and remove it.
                refreshedRecords.append(record)
                unavailable.append(
                    ExplorerUnavailableLocation(
                        id: record.id,
                        name: record.name,
                        reason: "La carpeta se movió, se eliminó o su referencia caducó."
                    )
                )
            }
        }

        // De-duplicate old records that may have accumulated before v0.9.
        let unavailableIDs = Set(unavailable.map(\.id))
        var seenPaths = Set<String>()
        records = refreshedRecords.filter { record in
            if unavailableIDs.contains(record.id) {
                return true
            }

            guard let path = resolvedPath(for: record) else {
                return false
            }
            return seenPaths.insert(path).inserted
        }

        if changed || records.count != loadSavedRecords().count {
            persist(records)
        }
    }

    /// Primero intenta listar la carpeta directamente (lo más tolerante) y, si
    /// falla, usa coordinación de archivos. Devuelve el motivo para diagnóstico.
    private func probeDirectoryAccessDetailed(_ url: URL) -> (ok: Bool, detail: String) {
        var details: [String] = []

        do {
            _ = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: []
            )
            return (true, "directa ok")
        } catch {
            let ns = error as NSError
            details.append("directa: \(ns.domain) \(ns.code)")
        }

        if probeDirectoryAccess(url) {
            return (true, "coordinada ok")
        }

        details.append("coordinada: falló")
        return (false, details.joined(separator: ", "))
    }

    private func probeDirectoryAccess(_ url: URL) -> Bool {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var readable = false

        coordinator.coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                let values = try coordinatedURL.resourceValues(
                    forKeys: [.isDirectoryKey]
                )
                guard values.isDirectory == true else { return }

                // Enumeration is the capability Explorer actually needs. An
                // empty result is still a successful access probe.
                _ = try FileManager.default.contentsOfDirectory(
                    at: coordinatedURL,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                readable = true
            } catch {
                readable = false
            }
        }

        return coordinationError == nil && readable
    }

    private func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: [
                .nameKey,
                .isDirectoryKey
            ],
            relativeTo: nil
        )
    }

    private func loadSavedRecords() -> [SavedExplorerLocation] {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let records = try? JSONDecoder().decode(
                [SavedExplorerLocation].self,
                from: data
            )
        else {
            return []
        }

        return records
    }

    private func persist(_ records: [SavedExplorerLocation]) {
        guard let data = try? JSONEncoder().encode(records) else {
            return
        }

        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func resolvedPath(
        for record: SavedExplorerLocation
    ) -> String? {
        var stale = false

        return try? URL(
            resolvingBookmarkData: record.bookmarkData,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ).standardizedFileURL.path
    }

    private func resourceIdentifier(_ url: URL) -> NSObjectProtocol? {
        (try? url.resourceValues(
            forKeys: [.fileResourceIdentifierKey]
        ))?.fileResourceIdentifier
    }

    private func isSameFolder(_ lhs: URL, _ rhs: URL) -> Bool {
        if canonical(lhs) == canonical(rhs) {
            return true
        }

        guard
            let first = resourceIdentifier(lhs),
            let second = resourceIdentifier(rhs)
        else {
            return false
        }

        return first.isEqual(second)
    }

    private func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func isDescendant(
        _ candidate: URL,
        of root: URL
    ) -> Bool {
        let rootPath = root.path.hasSuffix("/")
            ? root.path
            : root.path + "/"

        return candidate.path == root.path ||
            candidate.path.hasPrefix(rootPath)
    }
}

