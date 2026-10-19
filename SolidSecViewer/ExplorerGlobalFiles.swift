import SwiftUI
import UIKit

// MARK: - Tipos de archivo

enum ExplorerFileKinds {
    static let images: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff"
    ]

    static let videos: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "3gp"
    ]

    static let music: Set<String> = [
        "mp3", "m4a", "aac", "wav", "flac", "ogg", "aiff", "aif", "caf", "opus"
    ]

    static let packages: Set<String> = [
        "ipa", "tipa", "dylib", "deb", "framework"
    ]

    static let documents: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages",
        "numbers", "key", "epub", "odt", "ods", "odp"
    ]

    static let text: Set<String> = [
        "txt", "md", "markdown", "rtf", "json", "xml", "yaml", "yml", "log",
        "csv", "ini", "conf", "cfg", "toml", "swift", "py", "js", "ts",
        "html", "css", "sh", "c", "h", "cpp", "java", "kt", "rs", "go",
        "srt", "vtt", "tex"
    ]
}

enum ExplorerGlobalFilter: String, CaseIterable, Identifiable {
    case all
    case music
    case images
    case videos
    case text
    case packages
    case documents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Todos"
        case .music: return "Música"
        case .images: return "Imágenes"
        case .videos: return "Videos"
        case .text: return "Texto"
        case .packages: return "IPA y dylibs"
        case .documents: return "Documentos"
        }
    }

    func matches(_ pathExtension: String) -> Bool {
        switch self {
        case .all: return true
        case .music: return ExplorerFileKinds.music.contains(pathExtension)
        case .packages: return ExplorerFileKinds.packages.contains(pathExtension)
        case .documents: return ExplorerFileKinds.documents.contains(pathExtension)
        case .images: return ExplorerFileKinds.images.contains(pathExtension)
        case .videos: return ExplorerFileKinds.videos.contains(pathExtension)
        case .text: return ExplorerFileKinds.text.contains(pathExtension)
        }
    }
}

struct ExplorerGlobalFileResult: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let size: Int64?
    let modifiedAt: Date?
    let locationID: UUID
    let locationName: String
    let sourceTitle: String
    let relativeFolder: String

    var id: String { url.standardizedFileURL.path }
    var pathExtension: String { url.pathExtension.lowercased() }
    var folderURL: URL { url.deletingLastPathComponent() }

    var fileItem: ExplorerFileItem {
        ExplorerFileItem(
            url: url,
            name: name,
            isDirectory: false,
            isHidden: false,
            size: size,
            modifiedAt: modifiedAt,
            typeIdentifier: nil
        )
    }
}

// MARK: - Escaneo (síncrono, se ejecuta en segundo plano)

enum ExplorerGlobalScanner {
    static let maximumResults = 25_000

    struct Job: Sendable {
        let id: UUID
        let name: String
        let sourceTitle: String
        let url: URL
    }

    struct Summary: Sendable {
        var failedFolders = 0
        var truncated = false
    }

    /// Recorre una raíz autorizada. No sigue enlaces simbólicos, omite la
    /// papelera interna y evita resultados repetidos entre raíces.
    static func scan(
        job: Job,
        seen: inout Set<String>,
        total: inout Int,
        summary: inout Summary,
        flush: ([ExplorerGlobalFileResult]) -> Void
    ) {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]

        var failed = 0

        guard let enumerator = FileManager.default.enumerator(
            at: job.url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in
                failed += 1
                return true
            }
        ) else {
            summary.failedFolders += 1
            return
        }

        let rootPath = job.url.standardizedFileURL.path
        var batch: [ExplorerGlobalFileResult] = []

        while let object = enumerator.nextObject() {
            if Task.isCancelled { break }

            guard let url = object as? URL else { continue }

            let values = try? url.resourceValues(forKeys: Set(keys))

            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }

            if values?.isDirectory == true {
                if url.lastPathComponent == ".NikaidoTrash" {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }

            let canonical = url.standardizedFileURL.resolvingSymlinksInPath().path

            guard seen.insert(canonical).inserted else { continue }

            total += 1

            if total > maximumResults {
                summary.truncated = true
                break
            }

            let folderPath = url.deletingLastPathComponent().standardizedFileURL.path
            var relative = folderPath.hasPrefix(rootPath)
                ? String(folderPath.dropFirst(rootPath.count))
                : folderPath

            if relative.hasPrefix("/") {
                relative.removeFirst()
            }

            batch.append(
                ExplorerGlobalFileResult(
                    url: url,
                    name: url.lastPathComponent,
                    size: values?.fileSize.map { Int64($0) },
                    modifiedAt: values?.contentModificationDate,
                    locationID: job.id,
                    locationName: job.name,
                    sourceTitle: job.sourceTitle,
                    relativeFolder: relative
                )
            )

            if batch.count >= 250 {
                flush(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }

        if !batch.isEmpty {
            flush(batch)
        }

        summary.failedFolders += failed
    }
}

// MARK: - Índice

@MainActor
final class ExplorerGlobalIndex: ObservableObject {
    @Published private(set) var results: [ExplorerGlobalFileResult] = []
    @Published private(set) var isScanning = false
    @Published private(set) var failedFolders = 0
    @Published private(set) var truncated = false

    private var task: Task<Void, Never>?
    private var completedSignature: String?
    private var completedAt: Date?

    func scan(locations: [ExplorerStorageLocation], force: Bool) {
        let signature = locations
            .map { "\($0.id.uuidString):\($0.rootURL.standardizedFileURL.path)" }
            .sorted()
            .joined(separator: "|")

        if
            !force,
            !isScanning,
            completedSignature == signature,
            let completedAt,
            Date().timeIntervalSince(completedAt) < 90
        {
            return
        }

        task?.cancel()
        results = []
        failedFolders = 0
        truncated = false
        isScanning = true
        completedSignature = nil

        let jobs = locations.map { location in
            ExplorerGlobalScanner.Job(
                id: location.id,
                name: location.name,
                sourceTitle: location.source.title,
                url: location.rootURL
            )
        }

        task = Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) { () -> ExplorerGlobalScanner.Summary in
                var seen = Set<String>()
                var total = 0
                var summary = ExplorerGlobalScanner.Summary()

                for job in jobs {
                    if Task.isCancelled { break }

                    ExplorerGlobalScanner.scan(
                        job: job,
                        seen: &seen,
                        total: &total,
                        summary: &summary
                    ) { batch in
                        Task { @MainActor in
                            self?.append(batch)
                        }
                    }
                }

                return summary
            }.value

            guard !Task.isCancelled else { return }

            self?.finish(outcome, signature: signature)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isScanning = false
    }

    func remove(id: String) {
        results.removeAll(where: { $0.id == id })
    }

    private func append(_ batch: [ExplorerGlobalFileResult]) {
        results.append(contentsOf: batch)
    }

    private func finish(
        _ summary: ExplorerGlobalScanner.Summary,
        signature: String
    ) {
        failedFolders = summary.failedFolders
        truncated = summary.truncated
        isScanning = false
        completedSignature = signature
        completedAt = Date()
    }
}

// MARK: - Vista

private struct ExplorerGlobalPreviewTarget: Identifiable {
    let id = UUID()
    let url: URL
}

struct ExplorerGlobalFilesView: View {
    @ObservedObject var index: ExplorerGlobalIndex
    let locations: [ExplorerStorageLocation]
    let onReveal: (ExplorerGlobalFileResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nikaidoAccent) private var nikaidoAccent

    @State private var filter: ExplorerGlobalFilter
    @State private var search = ""
    @State private var previewTarget: ExplorerGlobalPreviewTarget?
    @State private var editorTarget: ExplorerEditorTarget?
    @State private var missingNotice: String?

    init(
        index: ExplorerGlobalIndex,
        locations: [ExplorerStorageLocation],
        initialFilter: ExplorerGlobalFilter = .all,
        onReveal: @escaping (ExplorerGlobalFileResult) -> Void
    ) {
        _index = ObservedObject(wrappedValue: index)
        self.locations = locations
        self.onReveal = onReveal
        _filter = State(initialValue: initialFilter)
    }

    private var filtered: [ExplorerGlobalFileResult] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)

        return index.results
            .filter { result in
                filter.matches(result.pathExtension)
                    && (query.isEmpty || result.name.localizedCaseInsensitiveContains(query))
            }
            .sorted {
                ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast)
            }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ExplorerGlobalFilter.allCases) { option in
                            Button {
                                filter = option
                            } label: {
                                Text(option.title)
                                    .font(.system(size: 15, weight: filter == option ? .bold : .semibold))
                                    .foregroundStyle(filter == option ? Color.white : Color.primary)
                                    .padding(.horizontal, 16)
                                    .frame(height: 36)
                                    .background(
                                        Capsule().fill(
                                            filter == option
                                            ? nikaidoAccent
                                            : Color.primary.opacity(0.10)
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                content
            }
            .navigationTitle(filter == .all ? "Todos los archivos" : filter.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Buscar por nombre")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        index.scan(locations: locations, force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(index.isScanning)
                    .accessibilityLabel("Volver a buscar")
                }
            }
            .task {
                index.scan(locations: locations, force: false)
            }
            .onDisappear {
                index.cancel()
            }
        }
        .sheet(item: $previewTarget) { target in
            ExplorerPreviewSheet(url: target.url)
        }
        .sheet(item: $editorTarget) { target in
            ExplorerTextEditorView(url: target.url, root: target.root) {}
        }
        .alert(
            "Archivo no disponible",
            isPresented: Binding(
                get: { missingNotice != nil },
                set: { if !$0 { missingNotice = nil } }
            )
        ) {
            Button("Entendido", role: .cancel) {
                missingNotice = nil
            }
        } message: {
            Text(missingNotice ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        let shown = filtered

        if shown.isEmpty {
            VStack(spacing: 12) {
                Spacer()

                if index.isScanning {
                    ProgressView("Buscando archivos…")
                } else {
                    NikaidoEmptyState(
                        systemName: "magnifyingglass",
                        title: "Sin resultados",
                        message: "No hay archivos de este tipo en las carpetas autorizadas."
                    )
                }

                footerNotes

                Spacer()
            }
        } else {
            List {
                ForEach(shown) { result in
                    row(result)
                }

                Section {
                    footerNotes
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var footerNotes: some View {
        if index.isScanning && !index.results.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text("Buscando… \(index.results.count) archivos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if index.failedFolders > 0 {
            Text("No se pudieron leer \(index.failedFolders) elemento(s) por permisos o porque cambiaron.")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        if index.truncated {
            Text("Se muestran los primeros \(ExplorerGlobalScanner.maximumResults) archivos.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ result: ExplorerGlobalFileResult) -> some View {
        Button {
            open(result)
        } label: {
            HStack(spacing: 12) {
                thumbnail(result)

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.name)
                        .font(.body.weight(.medium))
                        .lineLimit(2)

                    Text(locationLine(result))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)

                    Text(detailLine(result))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onReveal(result)
            } label: {
                Label("Mostrar en su carpeta", systemImage: "folder")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                onReveal(result)
            } label: {
                Label("Ver carpeta", systemImage: "folder")
            }
            .tint(nikaidoAccent)
        }
    }

    @ViewBuilder
    private func thumbnail(_ result: ExplorerGlobalFileResult) -> some View {
        let item = result.fileItem

        if item.hasMediaThumbnail {
            ExplorerMediaThumbnail(item: item, tint: Color.secondary)
                .frame(width: 48, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        } else {
            NikaidoIconBadge(
                systemName: item.systemImage,
                tint: Color.secondary,
                size: 30
            )
            .frame(width: 48, height: 44)
        }
    }

    private func locationLine(_ result: ExplorerGlobalFileResult) -> String {
        result.relativeFolder.isEmpty
            ? "\(result.sourceTitle) › \(result.locationName)"
            : "\(result.sourceTitle) › \(result.locationName) › \(result.relativeFolder)"
    }

    private func detailLine(_ result: ExplorerGlobalFileResult) -> String {
        var parts: [String] = []

        if let size = result.size {
            parts.append(ExplorerStorageUsage.format(size))
        }

        if let modified = result.modifiedAt {
            parts.append(modified.formatted(date: .abbreviated, time: .omitted))
        }

        return parts.joined(separator: " • ")
    }

    private func open(_ result: ExplorerGlobalFileResult) {
        guard FileManager.default.fileExists(atPath: result.url.path) else {
            index.remove(id: result.id)
            missingNotice = "“\(result.name)” ya no existe o la carpeta perdió el permiso de acceso."
            return
        }

        if
            ExplorerTextEditorView.canEdit(result.fileItem),
            let root = locations.first(where: { $0.id == result.locationID })?.rootURL
        {
            editorTarget = ExplorerEditorTarget(url: result.url, root: root)
        } else {
            previewTarget = ExplorerGlobalPreviewTarget(url: result.url)
        }
    }
}
