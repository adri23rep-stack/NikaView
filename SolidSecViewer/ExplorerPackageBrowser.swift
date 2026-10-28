import SwiftUI
import ZIPFoundation
import UIKit

/// Evita volver a descomprimir los iconos al desplazarse por listas grandes.
final class ExplorerPackageIconStore {
    static let shared = ExplorerPackageIconStore()
    private let lock = NSLock()
    private var resolved: [String: UIImage] = [:]
    private var missing = Set<String>()

    func icon(for url: URL) -> UIImage? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let key = url.path + "|" + String(values?.fileSize ?? 0) + "|" +
            String(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        lock.lock()
        if let icon = resolved[key] { lock.unlock(); return icon }
        if missing.contains(key) { lock.unlock(); return nil }
        lock.unlock()
        // Al listar un IPA grande no competimos con su apertura:
        // el detalle/icono se carga después de publicar el índice.
        let icon: UIImage?
        if (values?.fileSize ?? 0) > 512 * 1024 * 1024 {
            icon = nil
        } else {
            icon = (try? ExplorerPackageArchive.read(url))?.details.icon
        }
        lock.lock()
        if let icon { resolved[key] = icon } else { missing.insert(key) }
        lock.unlock()
        return icon
    }
}

/// Exploración sin ejecutar ni instalar paquetes. La extracción individual
/// escribe a un archivo temporal y solo lo publica tras verificarse el ZIP.
enum ExplorerPackageArchive {
    static let extensions = Set(["ipa", "apk", "zip"])
    private static let maxEntries = 100_000
    private static let maxSmallFile: UInt64 = 4 * 1024 * 1024
    private static let maxExportFile: UInt64 = 1024 * 1024 * 1024

    struct Entry: Identifiable, Hashable {
        let path: String
        let size: UInt64
        let directory: Bool
        var id: String { path }
        var name: String {
            path.split(separator: "/").last.map(String.init) ?? path
        }
    }

    struct Details {
        var name: String?
        var version: String?
        var identifier: String?
        var icon: UIImage?
    }

    struct Snapshot {
        let entries: [Entry]
        let details: Details
    }

    static func recognizes(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// Rechaza rutas absolutas, saltos de directorio y separadores alternos.
    /// También se valida de nuevo justo antes de escribir.
    static func validatedComponents(_ raw: String) throws -> [String] {
        guard !raw.isEmpty, !raw.hasPrefix("/"), !raw.contains("\\"),
              !raw.contains("\0") else {
            throw ExplorerOperationError.unsafeArchivePath(raw)
        }
        let parts = raw.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." &&
            !$0.contains(":") && !$0.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
        }) else {
            throw ExplorerOperationError.unsafeArchivePath(raw)
        }
        return parts
    }

    /// ZIPFoundation busca la firma de cierre desde el final del archivo.
    /// Si un IPA está incompleto puede recorrer sus gigabytes byte a byte.
    /// Comprobamos únicamente los últimos 65 KiB (ZIP + comentario máximo).
    static func verifyZipTail(_ url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let window = Int(min(size, 65_557))
        guard window >= 22 else {
            throw ExplorerOperationError.operationFailed("Paquete incompleto o no es ZIP.")
        }
        try handle.seek(toOffset: size - UInt64(window))
        let tail = try handle.read(upToCount: window) ?? Data()
        guard tail.count >= 22 else {
            throw ExplorerOperationError.operationFailed("No se pudo leer el final del paquete.")
        }
        for offset in stride(from: tail.count - 22, through: 0, by: -1) {
            if tail[offset] == 0x50 && tail[offset + 1] == 0x4B &&
               tail[offset + 2] == 0x05 && tail[offset + 3] == 0x06 {
                let commentLength = Int(tail[offset + 20]) |
                    (Int(tail[offset + 21]) << 8)
                if offset + 22 + commentLength == tail.count { return }
            }
        }
        throw ExplorerOperationError.operationFailed(
            "No encuentro el final del ZIP. El IPA puede estar incompleto o dañado. " +
            "Si está en iCloud, descarga el archivo completo antes de abrirlo."
        )
    }

    /// Fase rápida: solo lee el catálogo del ZIP. No infla assets, iconos ni
    /// ejecutables, aunque el IPA mida varios gigabytes.
    static func readIndex(_ url: URL) throws -> Snapshot {
        try verifyZipTail(url)
        let zip = try ZIPFoundation.Archive(url: url, accessMode: .read)
        var entries: [Entry] = []
        entries.reserveCapacity(256)
        var visited = 0
        for entry in zip {
            try Task.checkCancellation()
            visited += 1
            guard visited <= maxEntries else {
                throw ExplorerOperationError.tooManyArchiveEntries
            }
            guard entry.type != .symlink,
                  (try? validatedComponents(entry.path)) != nil else { continue }
            entries.append(Entry(
                path: entry.path,
                size: entry.uncompressedSize,
                directory: entry.type == .directory
            ))
        }
        return Snapshot(entries: entries, details: Details())
    }

    static func read(_ url: URL) throws -> Snapshot {
        try verifyZipTail(url)
        let zip = try ZIPFoundation.Archive(url: url, accessMode: .read)
        var entries: [Entry] = []
        var infoPlist: ZIPFoundation.Entry?
        var appRoot: String?
        var icons: [ZIPFoundation.Entry] = []

        for entry in zip {
            try Task.checkCancellation()
            guard entries.count < maxEntries else {
                throw ExplorerOperationError.tooManyArchiveEntries
            }
            // Los enlaces simbólicos jamás son destinos de exportación.
            let safe = (try? validatedComponents(entry.path)) != nil
            if safe {
                entries.append(Entry(path: entry.path, size: entry.uncompressedSize,
                                     directory: entry.type == .directory))
            }
            let parts = entry.path.split(separator: "/").map(String.init)
            if url.pathExtension.lowercased() == "ipa",
               parts.count >= 3, parts[0] == "Payload", parts[1].hasSuffix(".app") {
                let prefix = "Payload/" + parts[1] + "/"
                if appRoot == nil { appRoot = prefix }
                if entry.path == prefix + "Info.plist", entry.uncompressedSize <= maxSmallFile {
                    infoPlist = entry
                }
            }
            if entry.type == .file && entry.uncompressedSize <= maxSmallFile {
                let last = parts.last?.lowercased() ?? ""
                if last.hasSuffix(".png") &&
                    (last.contains("icon") || last.contains("launcher")) {
                    icons.append(entry)
                } else if last == "itunesartwork" || last == "itunesartwork@2x" {
                    icons.append(entry)
                }
            }
        }

        var details = Details()
        var iconNames: [String] = []
        if let infoPlist,
           let data = try? readSmall(infoPlist, from: zip),
           let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
           ) as? [String: Any] {
            details.name = (plist["CFBundleDisplayName"] as? String)
                ?? (plist["CFBundleName"] as? String)
            details.version = (plist["CFBundleShortVersionString"] as? String)
                ?? (plist["CFBundleVersion"] as? String)
            details.identifier = plist["CFBundleIdentifier"] as? String
            if let primary = (plist["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"]
                as? [String: Any] {
                iconNames = primary["CFBundleIconFiles"] as? [String] ?? []
            }
            if iconNames.isEmpty, let single = plist["CFBundleIconFile"] as? String {
                iconNames = [single]
            }
        }

        let selectedIcons: [ZIPFoundation.Entry]
        if let appRoot {
            selectedIcons = icons.filter { $0.path.hasPrefix(appRoot) ||
                $0.path.lowercased().contains("itunesartwork") }
        } else if url.pathExtension.lowercased() == "apk" {
            selectedIcons = icons.filter {
                let p = $0.path.lowercased()
                return p.contains("mipmap") || p.contains("drawable")
            }
        } else {
            selectedIcons = []
        }

        let ranked = selectedIcons.sorted { a, b in
            func score(_ item: ZIPFoundation.Entry) -> Int {
                let name = item.path.lowercased()
                var rank = 0
                if name.contains("itunesartwork") { rank += 100 }
                if iconNames.contains(where: { name.contains($0.lowercased()) }) { rank += 80 }
                if name.contains("@3x") || name.contains("xxxhdpi") { rank += 40 }
                if name.contains("@2x") || name.contains("xxhdpi") { rank += 30 }
                if name.contains("appicon") || name.contains("ic_launcher") { rank += 25 }
                if name.contains("180") || name.contains("120") { rank += 20 }
                return rank
            }
            return score(a) > score(b)
        }

        // En paquetes enormes, no probamos 16 imágenes potencialmente
        // grandes mientras el usuario ya navega las carpetas.
        let isLarge = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            > 512 * 1024 * 1024
        for entry in ranked.prefix(isLarge ? 3 : 16) {
            if let data = try? readSmall(entry, from: zip),
               let icon = UIImage(data: data), icon.size.width >= 32,
               icon.size.height >= 32 {
                details.icon = icon
                break
            }
        }
        return Snapshot(entries: entries, details: details)
    }

    private static func readSmall(
        _ entry: ZIPFoundation.Entry,
        from zip: ZIPFoundation.Archive
    ) throws -> Data {
        guard entry.type == .file, entry.uncompressedSize <= maxSmallFile else {
            throw ExplorerOperationError.operationFailed("El recurso es demasiado grande.")
        }
        var data = Data()
        _ = try zip.extract(entry) { chunk in
            guard data.count <= Int(maxSmallFile) - chunk.count else {
                throw ExplorerOperationError.operationFailed("Recurso demasiado grande.")
            }
            data.append(chunk)
        }
        return data
    }

    static func export(
        path: String, from packageURL: URL, into directory: URL,
        sourceRoot: URL, destinationRoot: URL
    ) throws -> URL {
        try ExplorerFileEngine.ensureInsideRoot(packageURL, root: sourceRoot)
        try ExplorerFileEngine.ensureInsideRoot(directory, root: destinationRoot)
        let parts = try validatedComponents(path)
        try verifyZipTail(packageURL)
        let zip = try ZIPFoundation.Archive(url: packageURL, accessMode: .read)
        guard let entry = zip[path], entry.type == .file,
              entry.uncompressedSize <= maxExportFile else {
            throw ExplorerOperationError.operationFailed(
                "No se puede extraer este elemento (carpeta, enlace o más de 1 GB)."
            )
        }
        let fm = FileManager.default
        let free = (try? fm.attributesOfFileSystem(forPath: directory.path)[.systemFreeSize]
            as? NSNumber)?.uint64Value ?? 0
        if free > 0 && free < entry.uncompressedSize {
            throw ExplorerOperationError.operationFailed("No hay espacio para extraer el archivo.")
        }
        let temporary = directory.appendingPathComponent(
            ".takopi-package-" + UUID().uuidString, isDirectory: false
        )
        try ExplorerFileEngine.ensureInsideRoot(temporary, root: destinationRoot)
        defer { try? fm.removeItem(at: temporary) }
        // Una ruta interna puede contener carpetas; solo se exporta su archivo final.
        let destinationName = parts.last ?? "extraido"
        let requested = directory.appendingPathComponent(destinationName)
        try ExplorerFileEngine.ensureInsideRoot(requested, root: destinationRoot)
        let destination = fm.fileExists(atPath: requested.path)
            ? ExplorerFileEngine.uniqueDestination(for: requested, in: directory)
            : requested
        try ExplorerFileEngine.ensureInsideRoot(destination, root: destinationRoot)
        _ = try zip.extract(entry, to: temporary)
        try fm.moveItem(at: temporary, to: destination)
        return destination
    }
}

struct ExplorerPackageTarget: Identifiable {
    let url: URL
    let sourceRoot: URL
    let destinationDirectory: URL
    let destinationRoot: URL
    let otherDirectory: URL?
    let otherRoot: URL?
    var id: String { url.absoluteString }
}

struct ExplorerPackageBrowserView: View {
    let target: ExplorerPackageTarget
    let onExtracted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: ExplorerPackageArchive.Snapshot?
    @State private var path = ""
    @State private var search = ""
    @State private var selected: ExplorerPackageArchive.Entry?
    @State private var loading = true
    @State private var loadingDetails = false
    @State private var details: ExplorerPackageArchive.Details?
    @State private var exporting = false
    @State private var message: String?
    @State private var failed = false
    @State private var showBloomBoxHandoff = false

    private var visible: [ExplorerPackageArchive.Entry] {
        guard let snapshot else { return [] }
        let filtered = snapshot.entries.filter { entry in
            search.isEmpty || entry.path.localizedCaseInsensitiveContains(search)
        }
        if !search.isEmpty { return Array(filtered.prefix(300)) }
        var children: [String: ExplorerPackageArchive.Entry] = [:]
        for entry in filtered {
            guard entry.path.hasPrefix(path) else { continue }
            let rest = String(entry.path.dropFirst(path.count))
            let pieces = rest.split(separator: "/")
            guard let first = pieces.first else { continue }
            let childPath = path + first + (pieces.count > 1 || entry.directory ? "/" : "")
            if children[childPath] == nil {
                children[childPath] = ExplorerPackageArchive.Entry(
                    path: childPath, size: pieces.count > 1 ? 0 : entry.size,
                    directory: pieces.count > 1 || entry.directory
                )
            }
        }
        return children.values.sorted {
            if $0.directory != $1.directory { return $0.directory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if target.url.pathExtension.lowercased() == "ipa" ||
                    target.url.pathExtension.lowercased() == "tipa" {
                    Section("Instalación") {
                        Button {
                            showBloomBoxHandoff = true
                        } label: {
                            Label("Instalar con BloomBox", systemImage: "square.and.arrow.up.on.square")
                        }
                        Text("Elige BloomBox en el menú de iOS para entregar el IPA a su instalador. Si no aparece, guarda el IPA en Archivos y selecciónalo desde BloomBox.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let details {
                    Section {
                        HStack(spacing: 12) {
                            if let icon = details.icon {
                                Image(uiImage: icon).resizable().scaledToFit()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                Image(systemName: "shippingbox.fill")
                                    .font(.title).frame(width: 56, height: 56)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(details.name ?? target.url.lastPathComponent)
                                    .font(.headline)
                                if let version = details.version {
                                    Text("Versión " + version).font(.caption)
                                }
                                if let identifier = details.identifier {
                                    Text(identifier).font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                if !path.isEmpty && search.isEmpty {
                    Button {
                        let parts = path.split(separator: "/").dropLast()
                        path = parts.isEmpty ? "" : parts.joined(separator: "/") + "/"
                    } label: {
                        Label("Volver a carpeta anterior", systemImage: "arrow.up.left")
                    }
                }
                if loadingDetails {
                    Section { Label("Leyendo nombre e icono en segundo plano…", systemImage: "photo")
                        .foregroundStyle(.secondary).font(.footnote) }
                }
                if let message {
                    Section {
                        Text(message).foregroundStyle(failed ? Color.red : Color.secondary)
                            .font(.footnote)
                    }
                }
                Section(path.isEmpty ? "Contenido" : path) {
                    if loading {
                        ProgressView("Leyendo índice del paquete…")
                    } else if visible.isEmpty {
                        Text("No hay archivos en esta ubicación.").foregroundStyle(.secondary)
                    }
                    ForEach(visible) { entry in
                        Button {
                            if entry.directory {
                                path = entry.path
                                search = ""
                            } else {
                                selected = entry
                            }
                        } label: {
                            HStack {
                                Image(systemName: entry.directory ? "folder.fill" : "doc.fill")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name).lineLimit(2)
                                    if !entry.directory {
                                        Text(ByteCountFormatter.string(
                                            fromByteCount: Int64(clamping: entry.size),
                                            countStyle: .file
                                        )).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if entry.directory {
                                    Image(systemName: "chevron.right").font(.caption)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        .disabled(exporting)
                    }
                }
            }
            .sheet(isPresented: $showBloomBoxHandoff) {
                ExplorerShareSheet(urls: [target.url])
            }
            .searchable(text: $search, prompt: "Buscar dentro del paquete")
            .navigationTitle("Explorar paquete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task(id: target.id) {
                loading = true
                let package = target.url
                snapshot = nil
                details = nil
                failed = false
                message = nil
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try ExplorerPackageArchive.readIndex(package) }
                }.value
                guard !Task.isCancelled else { return }
                switch result {
                case .success(let value):
                    snapshot = value
                    loading = false
                    loadingDetails = true
                    // Segunda fase: la carpeta ya está disponible aunque la
                    // lectura del icono o Info.plist tarde en este iPhone.
                    let info = await Task.detached(priority: .utility) {
                        try? ExplorerPackageArchive.read(package).details
                    }.value
                    guard !Task.isCancelled else { return }
                    details = info
                    loadingDetails = false
                case .failure(let error):
                    failed = true
                    message = error.localizedDescription
                    loading = false
                }
            }
            .confirmationDialog(
                selected?.name ?? "Extraer archivo",
                isPresented: Binding(
                    get: { selected != nil },
                    set: { if !$0 { selected = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Extraer en esta carpeta") {
                    if let selected { export(selected, toOther: false) }
                    selected = nil
                }
                if target.otherDirectory != nil && target.otherRoot != nil {
                    Button("Extraer al otro panel") {
                        if let selected { export(selected, toOther: true) }
                        selected = nil
                    }
                }
            } message: {
                Text("Se copiará solo este archivo. El IPA original no se modifica.")
            }
        }
    }

    private func export(_ entry: ExplorerPackageArchive.Entry, toOther: Bool) {
        let destination = toOther ? (target.otherDirectory ?? target.destinationDirectory)
            : target.destinationDirectory
        let root = toOther ? (target.otherRoot ?? target.destinationRoot)
            : target.destinationRoot
        let package = target.url
        let sourceRoot = target.sourceRoot
        exporting = true
        message = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try ExplorerPackageArchive.export(
                        path: entry.path, from: package, into: destination,
                        sourceRoot: sourceRoot, destinationRoot: root
                    )
                }
            }.value
            switch result {
            case .success(let saved):
                failed = false
                message = "Extraído: " + saved.lastPathComponent
                onExtracted()
            case .failure(let error):
                failed = true
                message = error.localizedDescription
            }
            exporting = false
        }
    }
}
