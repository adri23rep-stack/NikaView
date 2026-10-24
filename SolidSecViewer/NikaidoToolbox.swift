import SwiftUI
import Foundation
import PDFKit
import Vision
import ImageIO
import UniformTypeIdentifiers
import SQLite3

/// Tools operate only on paths explicitly opened by the user in Explorer.
/// All destructive operations require a separate confirmation.
struct NikaidoToolboxView: View {
    let left: URL?
    let right: URL?
    let selected: [URL]
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tool: Tool?

    private enum Tool: String, Identifiable, CaseIterable {
        case inspect = "Inspector y hexadecimal"
        case search = "Buscar dentro de archivos y fotos"
        case compare = "Comparar y sincronizar paneles"
        case space = "Mapa de espacio"
        case rename = "Renombrado masivo"
        case clean = "Compartir sin metadatos"
        case versions = "Versiones de texto"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .inspect: return "chevron.left.forwardslash.chevron.right"
            case .search: return "text.magnifyingglass"
            case .compare: return "arrow.left.arrow.right"
            case .space: return "chart.bar.xaxis"
            case .rename: return "pencil.line"
            case .clean: return "person.crop.circle.badge.xmark"
            case .versions: return "clock.arrow.circlepath"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Herramientas") {
                    ForEach(Tool.allCases) { item in
                        Button {
                            tool = item
                        } label: {
                            Label(item.rawValue, systemImage: item.symbol)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(!isEnabled(item))
                    }
                }
                Section {
                    Text("Inspector: selecciona un archivo. Para renombrar, selecciona uno o varios. La comparación usa las carpetas abiertas en ambos paneles.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Herramientas Takopi")
            .toolbar { Button("Cerrar") { dismiss() } }
            .sheet(item: $tool) { value in
                NavigationStack {
                    Group {
                        switch value {
                        case .inspect: NikaidoFileInspector(url: selected[0])
                        case .search: NikaidoContentSearch(root: left ?? right!)
                        case .compare: NikaidoCompareFolders(left: left!, right: right!, onChanged: onChanged)
                        case .space: NikaidoSpaceMap(root: left ?? right!)
                        case .rename: NikaidoBatchRename(urls: selected, onChanged: onChanged)
                        case .clean: NikaidoCleanShare(url: selected[0])
                        case .versions: NikaidoTextVersions(url: selected[0], onChanged: onChanged)
                        }
                    }
                    .navigationTitle(value.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Cerrar") { tool = nil } }
                }
            }
        }
    }

    private func isEnabled(_ item: Tool) -> Bool {
        switch item {
        case .inspect, .clean, .versions: return selected.count == 1 && !selected[0].hasDirectoryPath
        case .rename: return !selected.isEmpty
        case .compare: return left != nil && right != nil && left != right
        case .search, .space: return left != nil || right != nil
        }
    }
}

// MARK: - File inspection, previews and read-only SQLite tables
struct NikaidoFileInspector: View {
    let url: URL
    @State private var report = "Leyendo…"
    @State private var hexDump = ""
    @State private var databaseTables: [String] = []
    @State private var chosenTable: String?
    @State private var page = 0
    @State private var rows: [String] = []
    @State private var error: String?

    var body: some View {
        List {
            Section(url.lastPathComponent) {
                Text(report).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
            }
            if !databaseTables.isEmpty {
                Section("SQLite · solo lectura") {
                    Picker("Tabla", selection: $chosenTable) {
                        Text("Elegir tabla").tag(String?.none)
                        ForEach(databaseTables, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    HStack {
                        Button("Anterior") { page = max(0, page - 1) }.disabled(page == 0)
                        Spacer()
                        Text("Página \(page + 1)").font(.caption)
                        Spacer()
                        Button("Siguiente") { page = min(199, page + 1) }
                            .disabled(rows.count < 50 || page >= 199)
                    }
                    ForEach(rows, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
                }
            }
            Section("Hexadecimal · primeros 4 KB") {
                Text(hexDump).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .task { await load() }
        .task(id: chosenTable) { page = 0 }
        .task(id: "\(chosenTable ?? "")|\(page)") {
            guard let table = chosenTable else { rows = []; return }
            let file = url
            let offset = page
            let selected = await Task.detached(priority: .userInitiated) {
                Self.readTable(at: file, name: table, page: offset)
            }.value
            guard !Task.isCancelled else { return }
            rows = selected
        }
    }

    private func load() async {
        let result = await Task.detached(priority: .userInitiated) { () -> (String, String, [String]) in
            let data = (try? Data(contentsOf: url, options: .mappedIfSafe)) ?? Data()
            let prefix = data.prefix(4096)
            let hex = stride(from: 0, to: prefix.count, by: 16).map { i in
                let chunk = prefix.dropFirst(i).prefix(16)
                return String(format: "%08X", i) + "  " + chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
            }.joined(separator: "\n")
            var summary = "Tamaño: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))\n"
            let ext = url.pathExtension.lowercased()
            if ["json", "plist"].contains(ext) {
                if ext == "json", let object = try? JSONSerialization.jsonObject(with: data),
                   let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
                   let text = String(data: pretty, encoding: .utf8) {
                    summary += String(text.prefix(32000))
                } else if ext == "plist", let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
                          let text = String(data: (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .fragmentsAllowed])) ?? Data(), encoding: .utf8) {
                    summary += String(text.prefix(32000))
                } else { summary += "No se pudo decodificar el documento." }
            } else if ["ipa", "zip"].contains(ext) {
                summary += "ZIP/IPA: cabecera " + (data.starts(with: [0x50,0x4B]) ? "válida" : "no reconocida") + ".\nContenido completo: usar vista previa de archivos."
            } else if ext == "deb" {
                summary += "DEB/ar: " + (data.starts(with: Array("!<arch>\n".utf8)) ? "cabecera válida" : "cabecera no reconocida")
            } else if ["dylib", "so", "a"].contains(ext) {
                let signature = data.prefix(4).map { String(format: "%02X", $0) }.joined()
                summary += "Biblioteca binaria. Magic: \(signature).\nNo se ejecuta código del archivo."
            } else if ["sqlite", "sqlite3", "db"].contains(ext) {
                summary += "SQLite · estructura y primeras 50 filas por tabla · solo lectura."
            } else { summary += "Vista genérica sin ejecutar contenido." }
            if let binary = NikaidoBinaryInspector.report(url: url, mappedData: data) {
                summary += "\n\n" + String(binary.prefix(16000))
            }
            return (summary, hex, Self.listTables(at: url))
        }.value
        report = result.0
        hexDump = result.1
        databaseTables = result.2
    }

    nonisolated private static func listTables(at url: URL) -> [String] {
        guard ["sqlite", "sqlite3", "db"].contains(url.pathExtension.lowercased()) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            return []
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name LIMIT 100", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var tables: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = sqlite3_column_text(stmt, 0) { tables.append(String(cString: text)) }
        }
        return tables
    }

    nonisolated private static func readTable(at url: URL, name: String, page: Int) -> [String] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            return []
        }
        defer { sqlite3_close(db) }
        let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
        var stmt: OpaquePointer?
        let offset = max(0, min(page, 199)) * 50
        guard sqlite3_prepare_v2(db, "SELECT * FROM \"\(escaped)\" LIMIT 50 OFFSET \(offset)", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var rows: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let columns = (0..<sqlite3_column_count(stmt)).map { col -> String in
                let label = String(cString: sqlite3_column_name(stmt, col))
                if sqlite3_column_type(stmt, col) == SQLITE_BLOB { return "\(label)=<binary>" }
                return "\(label)=\(sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? "NULL")"
            }
            rows.append(columns.joined(separator: "  ·  "))
        }
        return rows
    }
}

// MARK: - Content search, including PDFKit, on-device image classification and OCR
struct NikaidoSearchHit: Identifiable {
    let id = UUID()
    let url: URL
    let explanation: String
}

struct NikaidoContentSearch: View {
    let root: URL
    @State private var query = ""
    @State private var hits: [NikaidoSearchHit] = []
    @State private var working = false
    @State private var searched = 0

    var body: some View {
        Form {
            Section("Buscar dentro de esta carpeta") {
                TextField("Texto, palabra u objeto en fotos", text: $query)
                    .textInputAutocapitalization(.never)
                Button("Buscar") { start() }.disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || working)
                if working { ProgressView("Analizando archivos…") }
                Text("Se buscan nombres, texto de PDFs, archivos de texto y fotos usando reconocimiento local de imágenes y texto. No se sube nada a internet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Resultados (\(hits.count))") {
                ForEach(hits) { hit in
                    VStack(alignment: .leading) {
                        Text(hit.url.lastPathComponent).bold()
                        Text(hit.explanation).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if !working { Text("\(searched) archivos revisados (máximo 1,000)").font(.caption) }
            }
        }
    }

    private func start() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return }
        working = true
        hits = []
        let base = root
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ([NikaidoSearchHit], Int) in
                let iterator = NikaidoFileEnumerator.list(base, limit: 1500)
                var found: [NikaidoSearchHit] = []
                var count = 0
                for url in iterator {
                    guard count < 1000, found.count < 100 else { break }
                    let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    guard v?.isRegularFile == true, v?.isSymbolicLink != true else { continue }
                    count += 1
                    let ext = url.pathExtension.lowercased()
                    var reason: String?
                    if url.lastPathComponent.lowercased().contains(term) { reason = "Nombre" }
                    if reason == nil, (v?.fileSize ?? 0) < 12_000_000 {
                        if ext == "pdf" {
                            if (PDFDocument(url: url)?.string ?? "").lowercased().contains(term) { reason = "Texto del PDF" }
                        } else if ["txt", "md", "csv", "json", "xml", "log", "swift", "py", "html", "yaml"].contains(ext) {
                            if let raw = try? String(contentsOf: url, encoding: .utf8), raw.lowercased().contains(term) { reason = "Contenido" }
                        } else if ["jpg", "jpeg", "png", "heic"].contains(ext) {
                            let request = VNClassifyImageRequest()
                            let text = VNRecognizeTextRequest()
                            text.recognitionLevel = .fast
                            let handler = VNImageRequestHandler(url: url)
                            if (try? handler.perform([request, text])) != nil {
                                let labels = (request.results ?? []).filter { $0.confidence > 0.17 }.prefix(12).map(\.identifier).joined(separator: " ").lowercased()
                                let words = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
                                if labels.contains(term) { reason = "Objeto detectado: \(labels.prefix(95))" }
                                else if words.contains(term) { reason = "Texto detectado en foto" }
                            }
                        }
                    }
                    if let reason { found.append(NikaidoSearchHit(url: url, explanation: reason)) }
                }
                return (found, count)
            }.value
            hits = result.0
            searched = result.1
            working = false
        }
    }
}

// Foundation's directory enumerator must be iterated in a synchronous context;
// async Tasks call this bounded helper rather than invoking its iterator directly.
enum NikaidoFileEnumerator {
    nonisolated static func list(_ root: URL, limit: Int) -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }
        var paths: [URL] = []
        for case let item as URL in walker {
            guard paths.count < limit else { break }
            paths.append(item)
        }
        return paths
    }
}

