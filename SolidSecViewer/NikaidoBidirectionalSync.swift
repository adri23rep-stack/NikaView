import SwiftUI
import Foundation

// A sync operation never deletes a source. Conflicting files are skipped by default.
private enum TwoWayChoice: String, Sendable {
    case skip = "Omitir"
    case left = "Izquierda a derecha"
    case right = "Derecha a izquierda"
}

private struct TwoWayFile: Sendable {
    let url: URL
    let bytes: Int64
    let date: Date
}

private struct TwoWayChange: Identifiable, Sendable {
    let path: String
    let left: TwoWayFile?
    let right: TwoWayFile?
    var id: String { path }
    var conflict: Bool { left != nil && right != nil }
}

private enum TwoWayEngine {
    nonisolated private static func failure(_ text: String) -> NSError {
        NSError(domain: "NikaView.TwoWaySync", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }

    nonisolated private static func checkedRoot(_ url: URL) throws -> String {
        let v = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard v.isDirectory == true && v.isSymbolicLink != true else {
            throw failure("Los paneles deben apuntar a carpetas reales.")
        }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    nonisolated private static func validate(_ left: URL, _ right: URL) throws {
        let a = try checkedRoot(left), b = try checkedRoot(right)
        guard a != b && !a.hasPrefix(b + "/") && !b.hasPrefix(a + "/") else {
            throw failure("Las carpetas deben ser distintas y no estar una dentro de otra.")
        }
    }

    nonisolated private static func inventory(_ root: URL) throws -> [String: TwoWayFile] {
        let base = root.standardizedFileURL.path + "/"
        let scanned = NikaidoFileEnumerator.list(root, limit: 1501)
        guard scanned.count <= 1500 else {
            throw failure("Se superaron 1,500 elementos en un panel. No se hará una sincronización incompleta.")
        }
        var result: [String: TwoWayFile] = [:]
        for file in scanned {
            let path = file.standardizedFileURL.path
            guard path.hasPrefix(base) else { continue }
            let relative = String(path.dropFirst(base.count))
            guard !relative.contains(".nikaview-backup-") &&
                  !relative.contains(".NikaView-sync-") else { continue }
            let v = try? file.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey
            ])
            guard v?.isRegularFile == true && v?.isSymbolicLink != true else { continue }
            result[relative] = TwoWayFile(
                url: file, bytes: Int64(v?.fileSize ?? 0),
                date: v?.contentModificationDate ?? .distantPast
            )
        }
        return result
    }

    nonisolated static func preview(_ left: URL, _ right: URL) throws -> [TwoWayChange] {
        try validate(left, right)
        let la = left.startAccessingSecurityScopedResource()
        let ra = right.startAccessingSecurityScopedResource()
        defer {
            if la { left.stopAccessingSecurityScopedResource() }
            if ra { right.stopAccessingSecurityScopedResource() }
        }
        let l = try inventory(left), r = try inventory(right)
        return Set(l.keys).union(r.keys).sorted().compactMap { path in
            let a = l[path], b = r[path]
            if let a, let b, a.bytes == b.bytes,
               abs(a.date.timeIntervalSince(b.date)) < 2 { return nil }
            return TwoWayChange(path: path, left: a, right: b)
        }
    }

    nonisolated private static func checkedPath(_ root: URL, _ path: String) throws -> URL {
        let base = try checkedRoot(root)
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty && parts.count <= 100 &&
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw failure("Se detectó una ruta no válida.")
        }
        var candidate = root.standardizedFileURL
        for part in parts {
            candidate.appendPathComponent(String(part))
            // Includes dangling symbolic links, which fileExists does not detect.
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) != nil {
                throw failure("Enlace simbólico no permitido: " + path)
            }
        }
        let original = root.standardizedFileURL.path + "/"
        guard candidate.path.hasPrefix(original),
              candidate.resolvingSymlinksInPath().path.hasPrefix(base + "/") else {
            throw failure("El destino está fuera de la carpeta autorizada.")
        }
        return candidate
    }

    nonisolated private static func unchanged(_ url: URL, _ previous: TwoWayFile?) -> Bool {
        let v = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey
        ])
        guard let previous else {
            return v == nil && (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil
        }
        return v?.isRegularFile == true && v?.isSymbolicLink != true &&
            Int64(v?.fileSize ?? -1) == previous.bytes &&
            abs((v?.contentModificationDate ?? .distantPast).timeIntervalSince(previous.date)) < 0.02
    }

    nonisolated static func apply(_ left: URL, _ right: URL, _ rows: [TwoWayChange],
                                  _ decisions: [String: TwoWayChoice]) throws -> Int {
        try validate(left, right)
        let la = left.startAccessingSecurityScopedResource()
        let ra = right.startAccessingSecurityScopedResource()
        defer {
            if la { left.stopAccessingSecurityScopedResource() }
            if ra { right.stopAccessingSecurityScopedResource() }
        }
        let fm = FileManager.default
        var copied = 0
        for row in rows {
            let choice = decisions[row.path] ?? .skip
            guard choice != .skip else { continue }
            let toRight = choice == .left
            guard let source = toRight ? row.left : row.right else { continue }
            let oldTarget = toRight ? row.right : row.left
            let fromRoot = toRight ? left : right
            let toRoot = toRight ? right : left
            let from = try checkedPath(fromRoot, row.path)
            let destination = try checkedPath(toRoot, row.path)
            guard unchanged(from, source) && unchanged(destination, oldTarget) else {
                throw failure("Un archivo cambió después del análisis: " + row.path)
            }
            let parent = destination.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            let rechecked = try checkedPath(toRoot, row.path)
            let staging = parent.appendingPathComponent(".NikaView-sync-" + UUID().uuidString)
            defer { try? fm.removeItem(at: staging) }
            try fm.copyItem(at: from, to: staging)
            guard unchanged(from, source) && unchanged(rechecked, oldTarget) else {
                throw failure("Un archivo cambió durante la copia: " + row.path)
            }
            if oldTarget != nil {
                let backup = rechecked.appendingPathExtension("nikaview-backup-" + UUID().uuidString)
                try fm.moveItem(at: rechecked, to: backup)
                do { try fm.moveItem(at: staging, to: rechecked) }
                catch {
                    try? fm.moveItem(at: backup, to: rechecked)
                    throw error
                }
            } else {
                try fm.moveItem(at: staging, to: rechecked)
            }
            copied += 1
        }
        return copied
    }
}

struct NikaidoBidirectionalSync: View {
    let left: URL
    let right: URL
    let onChanged: () -> Void
    @State private var rows: [TwoWayChange] = []
    @State private var decisions: [String: TwoWayChoice] = [:]
    @State private var busy = false
    @State private var analyzed = false
    @State private var confirm = false
    @State private var result: String?

    private var count: Int { rows.filter { (decisions[$0.path] ?? .skip) != .skip }.count }

    var body: some View {
        Form {
            Section("Dos sentidos, sin eliminar archivos") {
                Text("Se proponen los archivos faltantes. Los archivos distintos en ambos paneles se omiten hasta que elijas qué versión conservar.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Analizar ambos paneles") { inspect() }.disabled(busy)
                if busy { ProgressView("Procesando…") }
                if analyzed { Text("\(rows.count) diferencias encontradas · límite 1,500 elementos por panel") }
            }
            if !rows.isEmpty {
                Section("Vista previa") {
                    ForEach(rows) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.path).font(.subheadline).lineLimit(2)
                            Text(item.conflict ? "Conflicto: distintas en ambos paneles" :
                                (item.left == nil ? "Solo existe a la derecha" : "Solo existe a la izquierda"))
                                .font(.caption).foregroundStyle(.secondary)
                            Picker("Acción", selection: Binding(
                                get: { decisions[item.path] ?? .skip },
                                set: { decisions[item.path] = $0 }
                            )) {
                                Text("Omitir").tag(TwoWayChoice.skip)
                                if item.left != nil { Text("Izquierda → derecha").tag(TwoWayChoice.left) }
                                if item.right != nil { Text("Derecha → izquierda").tag(TwoWayChoice.right) }
                            }.pickerStyle(.menu)
                        }
                    }
                }
                Section {
                    Button("Revisar \(count) operaciones") { confirm = true }
                        .disabled(count == 0 || busy)
                    Text("Los reemplazos elegidos guardan un respaldo con nombre único. No se borran carpetas ni originales.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let result { Section("Resultado") { Text(result).textSelection(.enabled) } }
        }
        .confirmationDialog("¿Aplicar \(count) cambios?", isPresented: $confirm,
                            titleVisibility: .visible) {
            Button("Confirmar sincronización") { sync() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Los conflictos solo se reemplazan si elegiste expresamente una dirección.")
        }
    }

    private func inspect() {
        busy = true
        analyzed = false
        result = nil
        rows = []
        decisions = [:]
        let a = left, b = right
        Task {
            do {
                let proposed = try await Task.detached(priority: .userInitiated) {
                    try TwoWayEngine.preview(a, b)
                }.value
                rows = proposed
                for item in proposed {
                    decisions[item.path] = item.conflict ? .skip : (item.left == nil ? .right : .left)
                }
                analyzed = true
            } catch { result = error.localizedDescription }
            busy = false
        }
    }

    private func sync() {
        guard count > 0, !busy else { return }
        busy = true
        result = nil
        let proposed = rows, chosen = decisions, a = left, b = right
        Task {
            do {
                let done = try await Task.detached(priority: .userInitiated) {
                    try TwoWayEngine.apply(a, b, proposed, chosen)
                }.value
                result = "\(done) archivos copiados. Los archivos anteriores se guardaron como respaldos."
            } catch {
                result = "Se detuvo la sincronización: \(error.localizedDescription). Vuelve a analizar."
            }
            rows = []
            decisions = [:]
            analyzed = false
            busy = false
            onChanged()
        }
    }
}
