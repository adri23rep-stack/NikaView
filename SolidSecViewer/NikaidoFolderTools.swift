import SwiftUI
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

private struct NikaidoComparedFile: Identifiable {
    let path: String
    let source: URL
    let destination: URL
    let reason: String
    var id: String { path }
}

struct NikaidoCompareFolders: View {
    let left: URL
    let right: URL
    let onChanged: () -> Void
    @State private var differences: [NikaidoComparedFile] = []
    @State private var count = 0
    @State private var busy = false
    @State private var alert: String?
    @State private var confirm = false
    @State private var directionLeft = true
    @State private var showTwoWaySync = false

    var body: some View {
        Form {
            Section("Comparar sin modificar nada") {
                Picker("Dirección", selection: $directionLeft) {
                    Text("Izquierda → derecha").tag(true)
                    Text("Derecha → izquierda").tag(false)
                }
                Button("Analizar carpetas") { inspect() }.disabled(busy)
                Button("Sincronizar en ambos sentidos…") {
                    showTwoWaySync = true
                }.disabled(busy)
                if busy { ProgressView("Revisando…") }
                Text("Compara archivos por ruta, tamaño y fecha. La sincronización solo copia archivos faltantes o más nuevos; no borra el destino.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Diferencias: \(differences.count)") {
                ForEach(differences.prefix(150)) { file in
                    VStack(alignment: .leading) {
                        Text(file.path).lineLimit(2)
                        Text(file.reason).foregroundStyle(.secondary).font(.caption)
                    }
                }
                Text("\(count) archivos revisados · límite de 2,000")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !differences.isEmpty {
                Section {
                    Button("Sincronizar los archivos mostrados") { confirm = true }
                        .disabled(busy)
                }
            }
            if let alert { Text(alert).foregroundStyle(.secondary) }
        }
        .confirmationDialog("¿Copiar \(differences.count) archivos al otro panel?", isPresented: $confirm) {
            Button("Copiar archivos") { sync() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Los destinos modificados se respaldarán primero. Nunca se eliminarán archivos por estar ausentes en el origen.")
        }
        .task(id: directionLeft) { differences = [] }
        .sheet(isPresented: $showTwoWaySync) {
            NavigationStack {
                NikaidoBidirectionalSync(left: left, right: right, onChanged: onChanged)
                    .navigationTitle("Sincronizar ambos paneles")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        Button("Cerrar") { showTwoWaySync = false }
                    }
            }
        }
    }

    private func inspect() {
        busy = true
        let origin = directionLeft ? left : right
        let dest = directionLeft ? right : left
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ([NikaidoComparedFile], Int) in
                let walker = NikaidoFileEnumerator.list(origin, limit: 2400)
                var result: [NikaidoComparedFile] = []
                var count = 0
                for file in walker {
                    guard count < 2000 else { break }
                    let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                    guard values?.isRegularFile == true && values?.isSymbolicLink != true else { continue }
                    count += 1
                    let originPath = origin.standardizedFileURL.path + "/"
                    guard file.standardizedFileURL.path.hasPrefix(originPath) else { continue }
                    let relative = String(file.standardizedFileURL.path.dropFirst(originPath.count))
                    let target = dest.appendingPathComponent(relative)
                    let targetValues = try? target.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                    if targetValues?.isSymbolicLink == true { continue }
                    var reason: String?
                    if targetValues?.isRegularFile != true { reason = "Falta en el destino" }
                    else if (values?.contentModificationDate ?? .distantPast) > (targetValues?.contentModificationDate ?? .distantPast).addingTimeInterval(2) { reason = "Origen más reciente" }
                    else if values?.fileSize != targetValues?.fileSize && (values?.contentModificationDate ?? .distantPast) >= (targetValues?.contentModificationDate ?? .distantPast) { reason = "Distinto tamaño" }
                    if let reason { result.append(NikaidoComparedFile(path: relative, source: file, destination: target, reason: reason)) }
                }
                return (result, count)
            }.value
            differences = result.0
            count = result.1
            busy = false
        }
    }

    private func sync() {
        busy = true
        let changes = differences
        let targetRoot = directionLeft ? right : left
        Task {
            var done = 0
            do {
                for item in changes {
                    let dest = item.destination.standardizedFileURL
                    // Prevent writes outside the destination root.
                    guard dest.path.hasPrefix(targetRoot.standardizedFileURL.path + "/") else { continue }
                    let parent = dest.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: dest.path) {
                        // Keep a dated backup in the same folder; do not silently overwrite.
                        let backup = dest.appendingPathExtension("nikaview-backup-\(UUID().uuidString.prefix(8))")
                        try FileManager.default.moveItem(at: dest, to: backup)
                        do { try FileManager.default.copyItem(at: item.source, to: dest) }
                        catch {
                            try? FileManager.default.moveItem(at: backup, to: dest)
                            throw error
                        }
                    } else {
                        try FileManager.default.copyItem(at: item.source, to: dest)
                    }
                    done += 1
                }
                alert = "\(done) archivos copiados; los destinos anteriores se conservaron con extensión de respaldo."
                differences = []
                onChanged()
            } catch {
                alert = "Copiados: \(done). Se detuvo por un error: \(error.localizedDescription)"
            }
            busy = false
        }
    }
}

private struct NikaidoSizeEntry: Identifiable {
    let url: URL
    let bytes: Int64
    var id: URL { url }
}

struct NikaidoSpaceMap: View {
    let root: URL
    @State private var entries: [NikaidoSizeEntry] = []
    @State private var scanning = true
    @State private var truncated = false

    var body: some View {
        List {
            if scanning { ProgressView("Calculando tamaños…") }
            if truncated { Text("Cálculo limitado a 5,000 archivos para evitar bloqueos.").font(.caption).foregroundStyle(.orange) }
            let maxSize = max(entries.first?.bytes ?? 1, 1)
            ForEach(entries) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.url.lastPathComponent).lineLimit(1)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)).font(.caption)
                    }
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor)
                            .frame(width: max(2, geometry.size.width * CGFloat(Double(item.bytes) / Double(maxSize))), height: 8)
                    }.frame(height: 8)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .task { await calculate() }
    }

    private func calculate() async {
        scanning = true
        let result = await Task.detached(priority: .userInitiated) { () -> ([NikaidoSizeEntry], Bool) in
            let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])) ?? []
            var items: [NikaidoSizeEntry] = []
            var scanned = 0
            for child in children {
                guard scanned < 5000 else { break }
                var bytes: Int64 = 0
                let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values?.isSymbolicLink != true else { continue }
                if values?.isRegularFile == true { bytes = Int64(values?.fileSize ?? 0); scanned += 1 }
                else {
                    for file in NikaidoFileEnumerator.list(child, limit: 5000 - scanned) {
                        guard scanned < 5000 else { break }
                        let value = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                        guard value?.isRegularFile == true && value?.isSymbolicLink != true else { continue }
                        bytes += Int64(value?.fileSize ?? 0)
                        scanned += 1
                    }
                }
                items.append(NikaidoSizeEntry(url: child, bytes: bytes))
            }
            return (items.sorted { $0.bytes > $1.bytes }, scanned >= 5000)
        }.value
        entries = result.0
        truncated = result.1
        scanning = false
    }
}

struct NikaidoBatchRename: View {
    let urls: [URL]
    let onChanged: () -> Void
    @State private var prefix = ""
    @State private var suffix = ""
    @State private var find = ""
    @State private var replacement = ""
    @State private var confirm = false
    @State private var result: String?

    private var plan: [(URL, URL)] {
        urls.map { file in
            let old = file.deletingPathExtension().lastPathComponent
            let ext = file.pathExtension
            let stem = find.isEmpty ? old : old.replacingOccurrences(of: find, with: replacement)
            let newName = prefix + stem + suffix + (ext.isEmpty ? "" : "." + ext)
            return (file, file.deletingLastPathComponent().appendingPathComponent(newName))
        }
    }

    var body: some View {
        Form {
            Section("Transformación") {
                TextField("Prefijo", text: $prefix)
                TextField("Buscar", text: $find)
                TextField("Reemplazar por", text: $replacement)
                TextField("Sufijo (antes de extensión)", text: $suffix)
            }
            Section("Vista previa") {
                ForEach(plan, id: \.0) { entry in
                    let before = entry.0
                    let after = entry.1
                    VStack(alignment: .leading) {
                        Text(before.lastPathComponent).foregroundStyle(.secondary)
                        Text(after.lastPathComponent).bold()
                    }
                }
            }
            Button("Aplicar \(urls.count) cambios") { confirm = true }
                .disabled(urls.isEmpty || (prefix.isEmpty && suffix.isEmpty && find.isEmpty))
            if let result { Text(result).foregroundStyle(.secondary) }
        }
        .confirmationDialog("¿Renombrar estos archivos?", isPresented: $confirm) {
            Button("Renombrar") { apply() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func apply() {
        let ops = plan
        let names = ops.map { $0.1.standardizedFileURL.path }
        guard Set(names).count == names.count,
              ops.allSatisfy({ !$0.1.lastPathComponent.isEmpty && !$0.1.lastPathComponent.contains("/") && !$0.1.lastPathComponent.contains("\\") && !$0.1.lastPathComponent.hasPrefix(".") }),
              ops.allSatisfy({ $0.0 == $0.1 || !FileManager.default.fileExists(atPath: $0.1.path) }) else {
            result = "Nombres inválidos o destinos ya existentes. No se cambió nada."
            return
        }
        var changed = 0
        do {
            for (from, to) in ops where from != to {
                try FileManager.default.moveItem(at: from, to: to)
                changed += 1
            }
            result = "\(changed) nombres actualizados."
            onChanged()
        } catch { result = "\(changed) cambios aplicados antes del error: \(error.localizedDescription)" }
    }
}

struct NikaidoCleanShare: View {
    let url: URL
    @State private var cleanURL: URL?
    @State private var error: String?
    @State private var showShare = false
    @State private var isPreparing = false
    @State private var exportTask: Task<Void, Never>?

    private var isVideo: Bool {
        ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }
    private var isImage: Bool {
        ["jpg", "jpeg", "png", "heic"].contains(url.pathExtension.lowercased())
    }

    var body: some View {
        Form {
            Section("Privacidad antes de compartir") {
                Text(isVideo
                     ? "Genera una copia temporal MOV y elimina metadatos identificables de ubicación, fecha y autor. El video puede volver a codificarse y usar espacio adicional. El original permanece intacto."
                     : "Crea una copia nueva de la imagen sin ubicación GPS ni fecha EXIF. El original permanece intacto.")
                    .font(.footnote)
                Button(isVideo ? "Preparar video sin metadatos" : "Preparar imagen sin metadatos") {
                    prepare()
                }
                .disabled(isPreparing || !(isImage || isVideo))
                if isPreparing {
                    ProgressView("Exportando y revisando datos de privacidad…")
                }
                if let cleanURL {
                    Text(cleanURL.lastPathComponent)
                    Button("Compartir copia revisada") { showShare = true }
                        .disabled(isPreparing)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                Text("La copia solo se puede compartir después de terminar la exportación. La fecha del nuevo archivo puede ser la actual.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showShare) {
            if let cleanURL { ExplorerShareSheet(urls: [cleanURL]) }
        }
        .onDisappear {
            exportTask?.cancel()
            if let cleanURL { try? FileManager.default.removeItem(at: cleanURL) }
        }
    }

    private func prepare() {
        guard !isPreparing else { return }
        if let cleanURL {
            try? FileManager.default.removeItem(at: cleanURL)
            self.cleanURL = nil
        }
        error = nil
        if isVideo {
            isPreparing = true
            let source = url
            exportTask = Task {
                do {
                    let output = try await NikaidoVideoCleanExporter.exportCleanCopy(from: source)
                    guard !Task.isCancelled else {
                        try? FileManager.default.removeItem(at: output)
                        isPreparing = false
                        return
                    }
                    cleanURL = output
                } catch {
                    self.error = error.localizedDescription
                }
                isPreparing = false
            }
            return
        }

        guard isImage, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            error = "No se pudo decodificar la imagen."
            return
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("NikaView-clean-" + UUID().uuidString + ".png")
        guard let destination = CGImageDestinationCreateWithURL(
            out as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            error = "No se pudo crear la copia."
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            error = "No se pudo guardar la copia."
            return
        }
        cleanURL = out
    }
}

/// Private, bounded text snapshots. No backups are stored in the user's shared folder.
enum NikaidoTextHistory {
    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NikaView/TextHistory", isDirectory: true)
    }

    private static func folder(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(hash, isDirectory: true)
    }

    static func snapshot(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let content = try Data(contentsOf: url)
        guard content.count <= 2_000_000 else { return }
        let folder = folder(for: url)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        try content.write(to: folder.appendingPathComponent("\(timestamp)-\(UUID().uuidString).txt"), options: .atomic)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]).sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
            ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for older in files.dropFirst(10) { try? FileManager.default.removeItem(at: older) }
    }

    static func versions(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder(for: url), includingPropertiesForKeys: nil))?.sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
    }

    static func restore(_ snapshot: URL, to file: URL) throws {
        // Preserve the current content before restoring an earlier revision.
        try self.snapshot(file)
        let data = try Data(contentsOf: snapshot)
        try data.write(to: file, options: .atomic)
    }
}

struct NikaidoTextVersions: View {
    let url: URL
    let onChanged: () -> Void
    @State private var versions: [URL] = []
    @State private var restore: URL?
    @State private var status: String?

    var body: some View {
        List {
            Section {
                Text("Se guarda una versión local antes de cada cambio desde el editor de Takopi Explorer (máximo 10). No se sincroniza a iCloud.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Versiones guardadas") {
                ForEach(versions, id: \.self) { version in
                    Button(version.lastPathComponent) { restore = version }
                }
                if versions.isEmpty { Text("Sin versiones anteriores").foregroundStyle(.secondary) }
            }
            if let status { Text(status) }
        }
        .onAppear { versions = NikaidoTextHistory.versions(url) }
        .confirmationDialog("¿Restaurar esta versión de texto?", isPresented: Binding(get: { restore != nil }, set: { if !$0 { restore = nil } })) {
            Button("Restaurar") {
                guard let version = restore else { return }
                do {
                    try NikaidoTextHistory.restore(version, to: url)
                    status = "Versión restaurada."
                    onChanged()
                    versions = NikaidoTextHistory.versions(url)
                } catch { status = error.localizedDescription }
                restore = nil
            }
            Button("Cancelar", role: .cancel) { restore = nil }
        }
    }
}

