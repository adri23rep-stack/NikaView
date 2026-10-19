import SwiftUI
import UIKit

// MARK: - Colores personalizables (entorno)

private struct NikaidoAccentKey: EnvironmentKey {
    static let defaultValue: Color = NikaidoTheme.accent
}

private struct NikaidoFolderColorKey: EnvironmentKey {
    static let defaultValue: Color = NikaidoTheme.accent
}

extension EnvironmentValues {
    var nikaidoAccent: Color {
        get { self[NikaidoAccentKey.self] }
        set { self[NikaidoAccentKey.self] = newValue }
    }

    var nikaidoFolderColor: Color {
        get { self[NikaidoFolderColorKey.self] }
        set { self[NikaidoFolderColorKey.self] = newValue }
    }
}

extension Color {
    init?(nikaidoHex: String) {
        var text = nikaidoHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }

        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var nikaidoHexString: String {
        let color = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return String(
            format: "%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}

struct NikaidoSwatch: Identifiable {
    let name: String
    let hex: String

    var id: String { hex }
}

enum NikaidoThemePalette {
    static let defaultAccentHex = "615CF5"

    static let swatches: [NikaidoSwatch] = [
        NikaidoSwatch(name: "Índigo", hex: "615CF5"),
        NikaidoSwatch(name: "Azul", hex: "0A84FF"),
        NikaidoSwatch(name: "Turquesa", hex: "30B0C7"),
        NikaidoSwatch(name: "Verde", hex: "34C759"),
        NikaidoSwatch(name: "Amarillo", hex: "FFCC00"),
        NikaidoSwatch(name: "Naranja", hex: "FF9F0A"),
        NikaidoSwatch(name: "Rojo", hex: "FF453A"),
        NikaidoSwatch(name: "Rosa", hex: "FF5C93"),
        NikaidoSwatch(name: "Morado", hex: "AF52DE"),
        NikaidoSwatch(name: "Grafito", hex: "636366")
    ]
}

/// Colores individuales por carpeta (se guardan por ruta).
final class NikaidoFolderColors: ObservableObject {
    static let shared = NikaidoFolderColors()

    @Published private(set) var map: [String: String]

    private let key = "NikaidoTheme.folderColors.v1"

    private init() {
        map = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    func hex(for url: URL) -> String? {
        map[url.standardizedFileURL.path]
    }

    func set(_ hex: String?, for url: URL) {
        var copy = map
        let path = url.standardizedFileURL.path

        if let hex {
            copy[path] = hex
        } else {
            copy.removeValue(forKey: path)
        }

        map = copy
        UserDefaults.standard.set(copy, forKey: key)
    }

    func removeAll() {
        map = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Uso de espacio

struct ExplorerFolderSummary: Sendable {
    var files = 0
    var folders = 0
    var bytes: Int64 = 0
}

enum ExplorerStorageUsage {
    static func summary(of url: URL) -> ExplorerFolderSummary {
        var result = ExplorerFolderSummary()
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let manager = FileManager.default
        var isDirectory: ObjCBool = false

        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return result
        }

        if !isDirectory.boolValue {
            let values = try? url.resourceValues(forKeys: Set(keys))
            result.files = 1
            result.bytes = Int64(values?.fileSize ?? 0)
            return result
        }

        guard let enumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return result
        }

        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: Set(keys))

            if values?.isDirectory == true {
                result.folders += 1
            } else {
                result.files += 1
                result.bytes += Int64(values?.fileSize ?? 0)
            }
        }

        return result
    }

    static func size(of url: URL) -> Int64 {
        summary(of: url).bytes
    }

    static func freeSpace() -> Int64? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

enum ExplorerSpaceNotice: Identifiable {
    case trash(Int64)
    case lowSpace(Int64)

    var id: String {
        switch self {
        case .trash: return "trash"
        case .lowSpace: return "lowSpace"
        }
    }

    var isTrash: Bool {
        if case .trash = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .trash: return "La papelera está llena"
        case .lowSpace: return "Queda poco espacio"
        }
    }

    var message: String {
        switch self {
        case .trash(let bytes):
            return "La papelera ocupa \(ExplorerStorageUsage.format(bytes)). Si la vacías liberas ese espacio."
        case .lowSpace(let bytes):
            return "Solo quedan \(ExplorerStorageUsage.format(bytes)) libres en el iPhone."
        }
    }
}

// MARK: - Mover a la bóveda

enum ExplorerVaultBridge {
    /// Cifra un archivo (o una carpeta completa) dentro de la bóveda.
    @MainActor
    static func send(
        _ url: URL,
        into vault: PrivateVaultSession,
        parentID: UUID?
    ) async throws {
        let values = try url.resourceValues(
            forKeys: [.isDirectoryKey, .isRegularFileKey]
        )

        if values.isDirectory == true {
            let before = Set(vault.children(of: parentID).map(\.id))
            vault.errorMessage = nil
            vault.createFolder(name: url.lastPathComponent, parentID: parentID)

            if let message = vault.errorMessage {
                throw ExplorerOperationError.operationFailed(message)
            }

            guard let folder = vault.children(of: parentID).first(where: {
                !before.contains($0.id) && $0.kind == .folder
            }) else {
                throw ExplorerOperationError.operationFailed(
                    "No se pudo crear la carpeta en la bóveda."
                )
            }

            let children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: []
            )

            for child in children {
                try await send(child, into: vault, parentID: folder.id)
            }
        } else if values.isRegularFile == true {
            vault.errorMessage = nil
            await vault.importFiles(urls: [url], parentID: parentID)

            if let message = vault.errorMessage {
                throw ExplorerOperationError.operationFailed(message)
            }
        }
    }
}

// MARK: - Editor de texto

/// This limit is also read from a detached I/O task. Keep it outside the
/// SwiftUI view so the access is not inferred as MainActor-isolated.
private enum ExplorerTextEditorLimits {
    static let maximumBytes: Int64 = 2_000_000
}

struct ExplorerEditorTarget: Identifiable {
    let id = UUID()
    let url: URL
    let root: URL
}

struct ExplorerTextEditorView: View {
    let url: URL
    let root: URL
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var original = ""
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var showDiscardConfirm = false

    @AppStorage("NikaidoExplorer.editorMonospaced") private var monospaced = true
    @AppStorage("NikaidoExplorer.editorFontSize") private var fontSize = 15.0

    static let maxBytes = ExplorerTextEditorLimits.maximumBytes

    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "xml", "yaml", "yml", "log", "csv",
        "ini", "conf", "cfg", "toml", "swift", "py", "js", "ts", "html",
        "css", "sh", "c", "h", "cpp", "java", "kt", "rs", "go", "srt",
        "vtt", "tex"
    ]

    static func canEdit(_ item: ExplorerFileItem) -> Bool {
        guard !item.isDirectory else { return false }
        guard textExtensions.contains(item.pathExtension) else { return false }
        return (item.size ?? 0) <= maxBytes
    }

    private var isDirty: Bool {
        text != original
    }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Abriendo…")
                } else if let loadError {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(.secondary)

                        Text(loadError)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                } else {
                    TextEditor(text: $text)
                        .font(
                            monospaced
                            ? Font.system(size: fontSize, design: .monospaced)
                            : Font.system(size: fontSize)
                        )
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 8)
                }
            }
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        if isDirty {
                            showDiscardConfirm = true
                        } else {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Guardar").fontWeight(.semibold)
                        }
                    }
                    .disabled(!isDirty || isSaving || loadError != nil)
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        monospaced.toggle()
                    } label: {
                        Image(systemName: "textformat")
                    }

                    Spacer()

                    Button {
                        fontSize = max(11, fontSize - 1)
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                    }

                    Button {
                        fontSize = min(30, fontSize + 1)
                    } label: {
                        Image(systemName: "textformat.size.larger")
                    }
                }
            }
            .confirmationDialog(
                "¿Descartar los cambios?",
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Descartar cambios", role: .destructive) {
                    dismiss()
                }

                Button("Seguir editando", role: .cancel) {}
            }
            .alert(
                "No se pudo guardar",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("Entendido", role: .cancel) {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "")
            }
        }
        .interactiveDismissDisabled(isDirty)
        .task {
            await load()
        }
    }

    private func load() async {
        let fileURL = url

        do {
            let data = try await Task.detached(priority: .userInitiated) { () -> Data in
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])

                if Int64(values.fileSize ?? 0) > ExplorerTextEditorLimits.maximumBytes {
                    throw ExplorerOperationError.operationFailed(
                        "El archivo es muy grande para editarlo aquí (máximo 2 MB)."
                    )
                }

                return try Data(contentsOf: fileURL)
            }.value

            guard let string = String(data: data, encoding: .utf8) else {
                throw ExplorerOperationError.operationFailed(
                    "Este archivo no es texto UTF-8, así que no se puede editar."
                )
            }

            text = string
            original = string
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true

        let content = text

        Task {
            do {
                try await ExplorerFileEngine.writeText(
                    content,
                    to: url,
                    root: root
                )
                original = content
                onSaved()
            } catch {
                saveError = error.localizedDescription
            }

            isSaving = false
        }
    }
}

// MARK: - Información de archivo

struct ExplorerFileInfoView: View {
    let item: ExplorerFileItem

    @Environment(\.dismiss) private var dismiss

    @State private var summary: ExplorerFolderSummary?
    @State private var created: Date?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    infoRow("Nombre", item.name)
                    infoRow("Tipo", kindText)
                }

                Section("Tamaño") {
                    if item.isDirectory {
                        if let summary {
                            infoRow("Total", ExplorerStorageUsage.format(summary.bytes))
                            infoRow("Archivos", "\(summary.files)")
                            infoRow("Carpetas", "\(summary.folders)")
                        } else {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Calculando…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        infoRow(
                            "Tamaño",
                            item.size.map(ExplorerStorageUsage.format) ?? "—"
                        )
                    }
                }

                Section("Fechas") {
                    infoRow("Modificado", item.modifiedAt.map(dateText) ?? "—")
                    infoRow("Creado", created.map(dateText) ?? "—")
                }

                Section("Ubicación") {
                    Text(item.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Información")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await load()
        }
    }

    private var kindText: String {
        if item.isDirectory { return "Carpeta" }

        let ext = item.pathExtension
        return ext.isEmpty ? "Archivo" : "Archivo \(ext.uppercased())"
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(date: .long, time: .shortened)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)

            Spacer()

            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func load() async {
        let fileURL = item.url
        let isDirectory = item.isDirectory

        created = (try? fileURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate

        if isDirectory {
            summary = await Task.detached(priority: .utility) {
                ExplorerStorageUsage.summary(of: fileURL)
            }.value
        }
    }
}

// MARK: - Ajustes: apariencia

struct NikaidoAppearanceSettingsSection: View {
    @AppStorage("NikaidoTheme.accentHex")
    private var accentHex = NikaidoThemePalette.defaultAccentHex

    @AppStorage("NikaidoTheme.folderHex")
    private var folderHex = ""

    @AppStorage("NikaidoTheme.appearance")
    private var appearance = "system"

    @ObservedObject private var folderColors = NikaidoFolderColors.shared

    private var accentBinding: Binding<Color> {
        Binding(
            get: { Color(nikaidoHex: accentHex) ?? NikaidoTheme.accent },
            set: { accentHex = $0.nikaidoHexString }
        )
    }

    private var folderBinding: Binding<Color> {
        Binding(
            get: {
                Color(nikaidoHex: folderHex)
                    ?? Color(nikaidoHex: accentHex)
                    ?? NikaidoTheme.accent
            },
            set: { folderHex = $0.nikaidoHexString }
        )
    }

    var body: some View {
        Section("Apariencia") {
            Picker("Tema", selection: $appearance) {
                Text("Automático").tag("system")
                Text("Claro").tag("light")
                Text("Oscuro").tag("dark")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Color principal")
                    .font(.subheadline)

                swatchRow(selectedHex: accentHex) { hex in
                    accentHex = hex
                }
            }

            ColorPicker(
                "Otro color principal",
                selection: accentBinding,
                supportsOpacity: false
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Color de las carpetas")
                    .font(.subheadline)

                swatchRow(selectedHex: folderHex) { hex in
                    folderHex = hex
                }
            }

            ColorPicker(
                "Otro color de carpetas",
                selection: folderBinding,
                supportsOpacity: false
            )

            if !folderHex.isEmpty {
                Button("Carpetas con el color principal") {
                    folderHex = ""
                }
            }

            if !folderColors.map.isEmpty {
                Button("Quitar colores individuales (\(folderColors.map.count))") {
                    folderColors.removeAll()
                }
            }

            Button("Restablecer colores") {
                accentHex = NikaidoThemePalette.defaultAccentHex
                folderHex = ""
            }
        }
    }

    private func swatchRow(
        selectedHex: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(NikaidoThemePalette.swatches) { swatch in
                    Button {
                        onSelect(swatch.hex)
                    } label: {
                        Circle()
                            .fill(Color(nikaidoHex: swatch.hex) ?? Color.gray)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .stroke(
                                        Color.primary,
                                        lineWidth: selectedHex.uppercased() == swatch.hex ? 2.5 : 0
                                    )
                                    .padding(-4)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(swatch.name)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
        }
    }
}

// MARK: - Ajustes: espacio

struct NikaidoStorageSettingsSection: View {
    let trash: ExplorerTrashManager

    @AppStorage("NikaidoExplorer.trashWarnMB") private var trashWarnMB = 500
    @AppStorage("NikaidoExplorer.lowSpaceWarnMB") private var lowSpaceWarnMB = 1000

    @State private var trashBytes: Int64?
    @State private var vaultBytes: Int64?
    @State private var localBytes: Int64?
    @State private var freeBytes: Int64?
    @State private var confirmEmpty = false

    var body: some View {
        Section("Espacio") {
            usageRow("Papelera", trashBytes)
                .task {
                    await refreshUsage()
                }

            usageRow("Bóveda cifrada", vaultBytes)
            usageRow("Archivos locales de Nikaido", localBytes)
            usageRow("Libre en el iPhone", freeBytes)

            Picker("Avisar si la papelera pasa de", selection: $trashWarnMB) {
                Text("Nunca").tag(0)
                Text("100 MB").tag(100)
                Text("500 MB").tag(500)
                Text("1 GB").tag(1000)
                Text("5 GB").tag(5000)
            }

            Picker("Avisar si quedan menos de", selection: $lowSpaceWarnMB) {
                Text("Nunca").tag(0)
                Text("500 MB").tag(500)
                Text("1 GB").tag(1000)
                Text("5 GB").tag(5000)
            }

            Button("Vaciar papelera", role: .destructive) {
                confirmEmpty = true
            }
            .disabled(!trash.canUndo)
            .confirmationDialog(
                "¿Vaciar la papelera?",
                isPresented: $confirmEmpty,
                titleVisibility: .visible
            ) {
                Button("Vaciar", role: .destructive) {
                    Task {
                        await trash.empty()
                        await refreshUsage()
                    }
                }

                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Los archivos de la papelera se borran para siempre.")
            }
        }
    }

    private func usageRow(_ title: String, _ bytes: Int64?) -> some View {
        HStack {
            Text(title)

            Spacer()

            if let bytes {
                Text(ExplorerStorageUsage.format(bytes))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func refreshUsage() async {
        freeBytes = ExplorerStorageUsage.freeSpace()
        trashBytes = await trash.totalBytes()

        vaultBytes = await Task.detached(priority: .utility) {
            ExplorerStorageUsage.size(of: PrivateVaultSession.blobsURL)
        }.value

        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first

        localBytes = await Task.detached(priority: .utility) {
            documents.map { ExplorerStorageUsage.size(of: $0) } ?? 0
        }.value
    }
}


// MARK: - Mensajes de error comprensibles

enum ExplorerErrorText {
    private static let permissionText =
        "iOS no permite hacer esto en esa carpeta. Puede ser del sistema, estar "
        + "en modo solo lectura o haber perdido el permiso. Vuelve a añadirla "
        + "desde Archivos o usa una carpeta que hayas creado tú."

    static func message(for error: Error) -> String {
        if let cocoa = error as? CocoaError {
            switch cocoa.code {
            case .fileWriteNoPermission, .fileReadNoPermission:
                return permissionText
            case .fileNoSuchFile, .fileReadNoSuchFile:
                return "El archivo o la carpeta ya no existe. Puede haberse movido o eliminado."
            case .fileWriteOutOfSpace:
                return "No hay espacio suficiente en el almacenamiento."
            case .fileWriteVolumeReadOnly:
                return "Este almacenamiento es de solo lectura."
            default:
                break
            }
        }

        if let posix = error as? POSIXError {
            switch posix.code {
            case .EPERM, .EACCES:
                return permissionText
            default:
                break
            }
        }

        return error.localizedDescription
    }
}
