import SwiftUI
import UIKit
import UniformTypeIdentifiers
import QuickLookThumbnailing

private enum ExplorerNewItemKind: String, Identifiable {
    case textDocument
    case zipArchive

    var id: String { rawValue }

    var alertTitle: String {
        switch self {
        case .textDocument: return "Nuevo documento de texto"
        case .zipArchive: return "Nuevo archivo ZIP"
        }
    }

    var defaultName: String {
        switch self {
        case .textDocument: return "Nuevo documento"
        case .zipArchive: return "Nuevo archivo"
        }
    }

    func finalName(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        switch self {
        case .textDocument:
            return (trimmed as NSString).pathExtension.isEmpty
                ? trimmed + ".txt"
                : trimmed
        case .zipArchive:
            return trimmed.lowercased().hasSuffix(".zip")
                ? trimmed
                : trimmed + ".zip"
        }
    }

    /// Un ZIP vacío válido es solo el registro final (End Of Central Directory).
    var initialData: Data {
        switch self {
        case .textDocument:
            return Data()
        case .zipArchive:
            var bytes: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
            bytes.append(contentsOf: [UInt8](repeating: 0, count: 18))
            return Data(bytes)
        }
    }
}

private enum ExplorerPendingAction {
    case rename(ExplorerFileItem, pane: Int)
    case delete([ExplorerFileItem], pane: Int)
    case extract(ExplorerFileItem, pane: Int)
}

struct ExplorerView: View {
    @Environment(\.nikaidoAccent) private var nikaidoAccent
    @ObservedObject var locations: SecurityScopedFolderStore
    let launchRequest: ExplorerLaunchRequest?
    let onOpenHome: () -> Void
    let onOpenVault: () -> Void
    let onOpenSecReader: () -> Void

    @StateObject private var favorites = ExplorerFavoritesStore()
    @StateObject private var leftPane = ExplorerPaneState()
    @StateObject private var rightPane = ExplorerPaneState()
    @StateObject private var operationQueue = ExplorerOperationQueue()
    @StateObject private var trash = ExplorerTrashManager()

    @State private var activePane = 0
    @State private var showFolderPicker = false
    @State private var showStorageLocations = false
    @State private var showSettings = false
    @State private var showToolbox = false
    @State private var pendingDrop: ExplorerDropRequest?
    @State private var showOperations = false
    @State private var showTrash = false
    @State private var showSMB = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var newItemKind: ExplorerNewItemKind?
    @State private var newItemName = ""
    @State private var renameText = ""
    @State private var pendingAction: ExplorerPendingAction?
    @State private var previewTarget: ExplorerPreviewTarget?
    @State private var packageTarget: ExplorerPackageTarget?
    @State private var regularVideoTarget: NikaidoRegularVideoTarget?
    @State private var shareURLs: [URL] = []
    @State private var showShareSheet = false
    @State private var archivePassword = ""
    @State private var globalError: String?
    @State private var isOperating = false

    @AppStorage("NikaidoExplorer.conflictPolicy")
    private var conflictPolicyRaw = ExplorerConflictPolicy.rename.rawValue

    @AppStorage("NikaidoExplorer.confirmDelete")
    private var confirmDelete = true

    /// El segundo panel solo aparece cuando lo necesitas.
    @State private var splitOpen = false
    @State private var vaultPaneOpen = false
    @State private var vaultSplitFolderID: UUID?
    @State private var splitFraction: CGFloat = 0.5
    @State private var splitHint: String?
    @State private var showFileImporter = false
    @State private var editorTarget: ExplorerEditorTarget?
    @State private var showGlobalFiles = false
    @State private var globalInitialFilter: ExplorerGlobalFilter = .all
    @State private var searchingPaneIndex: Int?
    @State private var handledLaunchID: UUID?
    @StateObject private var globalIndex = ExplorerGlobalIndex()
    @StateObject private var dragState = ExplorerDragState()
    @State private var infoTarget: ExplorerFileItem?
    @State private var vaultSendItems: [ExplorerFileItem] = []
    @State private var vaultSendDestinationID: UUID?
    @State private var vaultSendPane = 0
    @State private var showVaultSendConfirm = false
    @State private var vaultNeedsUnlock = false
    @State private var spaceNotice: ExplorerSpaceNotice?
    @State private var spaceChecked = false

    @AppStorage("NikaidoExplorer.trashWarnMB") private var trashWarnMB = 500
    @AppStorage("NikaidoExplorer.lowSpaceWarnMB") private var lowSpaceWarnMB = 1000

    @EnvironmentObject private var privateVault: PrivateVaultSession

    private var conflictPolicy: ExplorerConflictPolicy {
        ExplorerConflictPolicy(rawValue: conflictPolicyRaw) ?? .rename
    }

    private var active: ExplorerPaneState {
        activePane == 0 ? leftPane : rightPane
    }

    private var other: ExplorerPaneState {
        activePane == 0 ? rightPane : leftPane
    }

    var body: some View {
        lifecycleConfiguredExplorer
    }

    /// Keep each SwiftUI composition small.  The complete Explorer screen owns
    /// many sheets and dialogs; expressing them as one giant `body` makes the
    /// Swift 5 type checker in Xcode 16.4 time out before compiling the app.
    private var explorerLayout: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {

                if !splitOpen {
                    paneView(
                        active,
                        index: activePane
                    )
                } else {
                    ExplorerResizableSplit(fraction: $splitFraction) {
                        paneView(leftPane, index: 0)
                    } second: {
                        if vaultPaneOpen {
                            ExplorerVaultSplitPane(
                                currentFolderID: $vaultSplitFolderID,
                                dragState: dragState,
                                onOpenFullVault: onOpenVault,
                                onSwitchToFiles: showTwoFilePanes,
                                onFilesDropped: handleVaultDrop,
                                onFilesDroppedToFolder: { providers, id in
                                    handleVaultDrop(providers, destinationFolderID: id)
                                }
                            )
                            .environmentObject(privateVault)
                        } else {
                            paneView(rightPane, index: 1)
                        }
                    }
                }

                if active.selectionMode {
                    Divider()
                    selectionToolbar
                }
            }
            .background(Color(uiColor: .systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                explorerBottomDock
            }
            .overlay {
                ExplorerDragGhostLayer(
                    dragState: dragState,
                    pointer: dragState.pointer
                )
            }
        }
    }

    private var basicPresentedExplorer: some View {
        explorerLayout
        .navigationBarHidden(true)
        .sheet(isPresented: $showFolderPicker) {
            ExplorerFolderPicker { url in
                if let location = locations.addAuthorizedFolder(url) {
                    active.openLocation(location)
                } else if let message = locations.lastError {
                    globalError = message
                }
            }
        }
        .sheet(isPresented: $showFileImporter) {
            ExplorerFilePicker { urls in
                importFiles(urls)
            }
        }
        .alert(
            "Panel de destino",
            isPresented: Binding(
                get: { splitHint != nil },
                set: { if !$0 { splitHint = nil } }
            )
        ) {
            Button("Entendido", role: .cancel) {
                splitHint = nil
            }
        } message: {
            Text(splitHint ?? "")
        }
        .sheet(isPresented: $showStorageLocations) {
            ExplorerStorageLocationsView(
                locations: locations,
                favorites: favorites,
                leftPane: leftPane,
                rightPane: rightPane,
                activePane: $activePane
            ) {
                showStorageLocations = false

                DispatchQueue.main.async {
                    showFolderPicker = true
                }
            }
        }
        .confirmationDialog(
            "¿Qué deseas hacer al soltar?",
            isPresented: Binding(
                get: { pendingDrop != nil },
                set: { if !$0 { pendingDrop = nil } }
            )
        ) {
            Button("Mover") { executeDrop(moving: true) }
            Button("Copiar") { executeDrop(moving: false) }
            Button("Cancelar", role: .cancel) { pendingDrop = nil }
        }
        .sheet(isPresented: $showToolbox) {
            NikaidoToolboxView(
                left: active.currentURL,
                right: splitOpen ? other.currentURL : nil,
                selected: active.selectedItems.map(\.url),
                onChanged: {
                    Task {
                        await leftPane.refresh()
                        await rightPane.refresh()
                    }
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            ExplorerSettingsView(
                conflictPolicyRaw: $conflictPolicyRaw,
                confirmDelete: $confirmDelete,
                trash: trash
            )
        }
    }

    private var vaultPresentedExplorer: some View {
        basicPresentedExplorer
        .sheet(item: $regularVideoTarget) { target in
            NikaidoRegularVideoPlayer(url: target.url)
        }
        .sheet(item: $editorTarget) { target in
            ExplorerTextEditorView(
                url: target.url,
                root: target.root
            ) {
                Task {
                    await leftPane.refresh()
                    await rightPane.refresh()
                }
            }
        }
        .sheet(item: $infoTarget) { item in
            ExplorerFileInfoView(item: item)
        }
        .alert(
            "Bóveda bloqueada",
            isPresented: $vaultNeedsUnlock
        ) {
            Button("Abrir bóveda") {
                onOpenVault()
            }

            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Desbloquea Takopi Vault y vuelve a intentarlo. Los archivos se cifran dentro de la bóveda.")
        }
        .confirmationDialog(
            "Mover a la bóveda",
            isPresented: $showVaultSendConfirm,
            titleVisibility: .visible
        ) {
            Button("Cifrar y conservar originales") {
                performSendToVault(deleteOriginals: false)
            }
            Button("Cifrar y borrar originales", role: .destructive) {
                performSendToVault(deleteOriginals: true)
            }

            Button("Cancelar", role: .cancel) {
                vaultSendItems = []
                vaultSendDestinationID = nil
            }
        } message: {
            Text("Destino: \(privateVault.folderName(vaultSendDestinationID)). Primero se cifran los archivos. Puedes conservar o borrar los originales.")
        }
        .alert(
            spaceNotice?.title ?? "Espacio",
            isPresented: Binding(
                get: { spaceNotice != nil },
                set: { if !$0 { spaceNotice = nil } }
            )
        ) {
            if spaceNotice?.isTrash == true {
                Button("Vaciar papelera", role: .destructive) {
                    Task {
                        await trash.empty()
                    }
                }
            }

            Button("Ahora no", role: .cancel) {
                spaceNotice = nil
            }
        } message: {
            Text(spaceNotice?.message ?? "")
        }
        .task {
            await checkSpaceWarnings()
        }
    }

    private var utilityPresentedExplorer: some View {
        vaultPresentedExplorer
        .sheet(isPresented: $showOperations) {
            ExplorerOperationQueueView(queue: operationQueue)
        }
        .sheet(isPresented: $showGlobalFiles) {
            ExplorerGlobalFilesView(
                index: globalIndex,
                locations: locations.locations,
                initialFilter: globalInitialFilter
            ) { result in
                revealGlobalResult(result)
            }
        }
        .sheet(isPresented: $showTrash) {
            ExplorerTrashView(trash: trash) {
                Task {
                    await leftPane.refresh()
                    await rightPane.refresh()
                }
            }
        }
        .sheet(isPresented: $showSMB) {
            ExplorerSMBView(
                destinationDirectory: active.currentURL,
                uploadItems: active.selectedItems,
                onLocalChanged: {
                    Task { await active.refresh() }
                }
            )
        }
        .sheet(item: $previewTarget) { target in
            ExplorerPreviewSheet(url: target.url)
        }
        .sheet(item: $packageTarget) { target in
            ExplorerPackageBrowserView(target: target) {
                Task {
                    await leftPane.refresh()
                    await rightPane.refresh()
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ExplorerShareSheet(urls: shareURLs)
        }
    }

    private var dialogPresentedExplorer: some View {
        utilityPresentedExplorer
        .alert(
            "Nueva carpeta",
            isPresented: $showNewFolder
        ) {
            TextField("Nombre", text: $newFolderName)

            Button("Cancelar", role: .cancel) {
                newFolderName = ""
            }

            Button("Crear") {
                createFolder()
            }
        } message: {
            Text(active.relativePath)
        }
        .alert(
            newItemKind?.alertTitle ?? "Nuevo",
            isPresented: Binding(
                get: { newItemKind != nil },
                set: {
                    if !$0 {
                        newItemKind = nil
                    }
                }
            )
        ) {
            TextField("Nombre", text: $newItemName)

            Button("Cancelar", role: .cancel) {
                newItemName = ""
                newItemKind = nil
            }

            Button("Crear") {
                createNewItem()
            }
        } message: {
            Text(active.relativePath)
        }
        .alert(
            "Renombrar",
            isPresented: Binding(
                get: {
                    if case .rename = pendingAction {
                        return true
                    }
                    return false
                },
                set: {
                    if !$0, case .rename = pendingAction {
                        pendingAction = nil
                    }
                }
            )
        ) {
            TextField("Nombre", text: $renameText)

            Button("Cancelar", role: .cancel) {
                renameText = ""
                pendingAction = nil
            }

            Button("Guardar") {
                performRename()
            }
        }
        .alert(
            "Eliminar",
            isPresented: Binding(
                get: {
                    if case .delete = pendingAction {
                        return true
                    }
                    return false
                },
                set: {
                    if !$0, case .delete = pendingAction {
                        pendingAction = nil
                    }
                }
            )
        ) {
            Button("Cancelar", role: .cancel) {
                pendingAction = nil
            }

            Button("Eliminar", role: .destructive) {
                performDelete()
            }
        } message: {
            Text(
                "Los elementos seleccionados se moverán a la Papelera de Takopi. "
                + "Podrás restaurarlos o deshacer la última eliminación."
            )
        }
        .sheet(
            isPresented: Binding(
                get: {
                    if case .extract = pendingAction {
                        return true
                    }
                    return false
                },
                set: {
                    if !$0, case .extract = pendingAction {
                        pendingAction = nil
                        archivePassword = ""
                    }
                }
            )
        ) {
            ExplorerExtractSheet(
                password: $archivePassword,
                isOperating: isOperating,
                onCancel: {
                    pendingAction = nil
                    archivePassword = ""
                },
                onExtract: {
                    performExtract()
                }
            )
        }
        .alert(
            "Takopi Explorer",
            isPresented: Binding(
                get: { globalError != nil },
                set: {
                    if !$0 {
                        globalError = nil
                    }
                }
            )
        ) {
            Button("Entendido", role: .cancel) {
                globalError = nil
            }
        } message: {
            Text(globalError ?? "")
        }
    }

    private var lifecycleConfiguredExplorer: some View {
        dialogPresentedExplorer
        .onAppear {
            locations.refreshPersistentReferences()

            if leftPane.location == nil,
               let local = locations.localLocation
            {
                leftPane.openLocation(local)
            }

            if rightPane.location == nil,
               let local = locations.localLocation
            {
                rightPane.openLocation(local)
            }

            handleLaunchRequest()
        }
    }

    /// Atiende lo que se pidió desde el inicio (abrir una carpeta, un tipo de
    /// archivo o los ajustes). Se atiende una sola vez por petición.
    private func handleLaunchRequest() {
        guard let request = launchRequest, handledLaunchID != request.id else {
            return
        }

        handledLaunchID = request.id

        switch request.kind {
        case .files:
            if let local = locations.localLocation {
                activePane = 0
                leftPane.openLocation(local)
            }
        case .location(let id):
            if let location = locations.locations.first(where: { $0.id == id }) {
                activePane = 0
                leftPane.openLocation(location)
            }
        case .folder(let id, let url):
            if let location = locations.locations.first(where: { $0.id == id }) {
                activePane = 0
                leftPane.openLocation(location, folderURL: url)
            }
        case .global(let filter):
            globalInitialFilter = filter
            showGlobalFiles = true
        case .settings:
            showSettings = true
        case .smb:
            showSMB = true
        }
    }

    private var explorerBottomDock: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                Button {
                    onOpenHome()
                } label: {
                    Image(systemName: "house")
                }
                .accessibilityLabel("Inicio")

                Button {
                    if active.canGoBack {
                        active.goBack()
                    } else if active.canGoUp {
                        active.goUp()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!active.canGoBack && !active.canGoUp)
                .accessibilityLabel("Volver a la carpeta anterior")

                Button {
                    toggleSplit()
                } label: {
                    Image(systemName: splitOpen ? "rectangle" : "rectangle.split.1x2")
                }
                .accessibilityLabel(splitOpen ? "Un solo panel" : "Dividir pantalla")

                Button {
                    if vaultPaneOpen {
                        showTwoFilePanes()
                    } else {
                        openVaultSplit()
                    }
                    NikaidoTheme.haptic(.light)
                } label: {
                    Image(systemName: vaultPaneOpen ? "lock.open.fill" : "lock.shield")
                        .foregroundStyle(vaultPaneOpen ? nikaidoAccent : .primary)
                }
                .accessibilityLabel(vaultPaneOpen
                    ? "Volver a dos paneles de archivos"
                    : "Abrir Takopi Vault en pantalla dividida")
                .accessibilityHint("Alterna entre archivos y bóveda sin salir de Liquid Glass")

            Menu {
                Button {
                    showToolbox = true
                } label: {
                    Label("Herramientas avanzadas", systemImage: "wrench.and.screwdriver")
                }
                Button {
                    globalInitialFilter = .all
                    showGlobalFiles = true
                } label: {
                    Label(
                        "Todos los archivos",
                        systemImage: "square.stack"
                    )
                }

                Section("Navegación") {
                    Button {
                        searchingPaneIndex = activePane
                    } label: {
                        Label("Buscar en carpeta", systemImage: "magnifyingglass")
                    }

                    Button {
                        active.goForward()
                    } label: {
                        Label("Adelante", systemImage: "chevron.right")
                    }
                    .disabled(!active.canGoForward)

                    Button {
                        active.goUp()
                    } label: {
                        Label("Carpeta superior", systemImage: "arrow.up")
                    }
                    .disabled(!active.canGoUp)

                    Button {
                        active.viewMode = active.viewMode == .list ? .grid : .list
                    } label: {
                        Label("Cambiar vista", systemImage: "square.grid.2x2")
                    }

                    if trash.canUndo {
                        Button {
                            operationQueue.enqueue(title: "Deshacer eliminación", kind: .restore) {
                                try await trash.undoLast()
                                await leftPane.refresh()
                                await rightPane.refresh()
                            }
                        } label: {
                            Label("Deshacer última eliminación", systemImage: "arrow.uturn.backward")
                        }
                    }

                    if operationQueue.activeCount > 0 {
                        Button {
                            showOperations = true
                        } label: {
                            Label("Cola de operaciones", systemImage: "list.bullet.rectangle")
                        }
                    }
                }

                Section("Archivos") {
                    Button {
                        newFolderName = ""
                        showNewFolder = true
                    } label: {
                        Label(
                            "Nueva carpeta",
                            systemImage: "folder.badge.plus"
                        )
                    }
                    .disabled(active.currentURL == nil)

                    Button {
                        active.selectionMode.toggle()

                        if !active.selectionMode {
                            active.clearSelection()
                        }
                    } label: {
                        Label(
                            active.selectionMode
                            ? "Salir de selección"
                            : "Seleccionar",
                            systemImage: "checkmark.circle"
                        )
                    }

                    Button {
                        active.goRoot()
                    } label: {
                        Label(
                            "Acceso directo a la raíz",
                            systemImage: "arrow.up.to.line.compact"
                        )
                    }

                    Button {
                        guard
                            let location = active.location,
                            let currentURL = active.currentURL
                        else { return }

                        do {
                            try favorites.add(
                                location: location,
                                folderURL: currentURL
                            )
                        } catch {
                            globalError = ExplorerErrorText.message(for: error)
                        }
                    } label: {
                        Label(
                            "Añadir carpeta actual a favoritos",
                            systemImage: "star"
                        )
                    }
                    .disabled(active.currentURL == nil)

                    Button {
                        showStorageLocations = true
                    } label: {
                        Label(
                            "Favoritos",
                            systemImage: "star.fill"
                        )
                    }

                    Button {
                        Task {
                            await active.refresh()
                        }
                    } label: {
                        Label(
                            "Recargar",
                            systemImage: "arrow.clockwise"
                        )
                    }
                }

                Section("Vista") {
                    Menu("Modo de vista") {
                        ForEach(ExplorerViewMode.allCases) { mode in
                            Button {
                                active.viewMode = mode
                            } label: {
                                if active.viewMode == mode {
                                    Label(mode.title, systemImage: "checkmark")
                                } else {
                                    Label(mode.title, systemImage: mode.systemImage)
                                }
                            }
                        }
                    }

                    Menu("Ordenar por") {
                        ForEach(ExplorerSortMode.allCases) { mode in
                            Button {
                                active.sortMode = mode

                                Task {
                                    await active.refresh()
                                }
                            } label: {
                                if active.sortMode == mode {
                                    Label(
                                        mode.title,
                                        systemImage: "checkmark"
                                    )
                                } else {
                                    Text(mode.title)
                                }
                            }
                        }
                    }

                    Button {
                        active.ascending.toggle()

                        Task {
                            await active.refresh()
                        }
                    } label: {
                        Label(
                            active.ascending
                            ? "Ascendente"
                            : "Descendente",
                            systemImage: active.ascending
                            ? "arrow.up"
                            : "arrow.down"
                        )
                    }

                    Button {
                        active.showHidden.toggle()

                        Task {
                            await active.refresh()
                        }
                    } label: {
                        Label(
                            active.showHidden
                            ? "Ocultar archivos ocultos"
                            : "Mostrar archivos ocultos",
                            systemImage: active.showHidden
                            ? "eye.slash"
                            : "eye"
                        )
                    }
                }

                Section("Takopi") {
                    Button {
                        showSMB = true
                    } label: {
                        Label("Servidor SMB", systemImage: "network")
                    }

                    Button {
                        showTrash = true
                    } label: {
                        Label("Papelera", systemImage: "trash")
                    }

                    Button {
                        showOperations = true
                    } label: {
                        Label("Cola de operaciones", systemImage: "list.bullet.rectangle")
                    }

                    Button {
                        showStorageLocations = true
                    } label: {
                        Label(
                            "Dispositivos de almacenamiento",
                            systemImage: "externaldrive.connected.to.line.below"
                        )
                    }

                    Button {
                        onOpenVault()
                    } label: {
                        Label(
                            "Takopi Vault",
                            systemImage: "lock.square.stack.fill"
                        )
                    }

                    Button {
                        openVaultSplit()
                    } label: {
                        Label("Bóveda en pantalla dividida", systemImage: "rectangle.split.2x1")
                    }
                    if vaultPaneOpen {
                        Button {
                            showTwoFilePanes()
                        } label: {
                            Label("Dos paneles de archivos", systemImage: "folder.badge.gearshape")
                        }
                    }

                    Button {
                        onOpenSecReader()
                    } label: {
                        Label(
                            "Abrir colección .sec",
                            systemImage: "folder.badge.gearshape"
                        )
                    }

                    Button {
                        onOpenVault()
                    } label: {
                        Label(
                            "Nikaido Link",
                            systemImage: "wifi"
                        )
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Label(
                            "Ajustes",
                            systemImage: "gearshape"
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("Acciones")
            }
            .buttonStyle(NikaidoGlassActionStyle())
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .modifier(NikaidoGlassCapsule())

            // Independiente de la cápsula: acción principal claramente separada.
            floatingAddButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// Abre la carpeta de origen de un resultado del filtro global.
    private func revealGlobalResult(_ result: ExplorerGlobalFileResult) {
        guard
            let location = locations.locations.first(where: {
                $0.id == result.locationID
            })
        else {
            return
        }

        showGlobalFiles = false
        active.openLocation(location, folderURL: result.folderURL)
    }

    private func checkSpaceWarnings() async {
        guard !spaceChecked else { return }
        spaceChecked = true

        if trashWarnMB > 0 {
            let bytes = await trash.totalBytes()

            if bytes > Int64(trashWarnMB) * 1_000_000 {
                spaceNotice = .trash(bytes)
                return
            }
        }

        if
            lowSpaceWarnMB > 0,
            let free = ExplorerStorageUsage.freeSpace(),
            free < Int64(lowSpaceWarnMB) * 1_000_000
        {
            spaceNotice = .lowSpace(free)
        }
    }

    private func openEditor(_ item: ExplorerFileItem, paneIndex: Int) {
        activePane = paneIndex

        guard let root = pane(at: paneIndex).location?.rootURL else { return }

        editorTarget = ExplorerEditorTarget(url: item.url, root: root)
    }

    private func addFavorite(_ item: ExplorerFileItem, paneIndex: Int) {
        guard
            item.isDirectory,
            let location = pane(at: paneIndex).location
        else {
            return
        }

        do {
            try favorites.add(location: location, folderURL: item.url)
        } catch {
            globalError = ExplorerErrorText.message(for: error)
        }
    }

    private func requestSendToVault(
        _ items: [ExplorerFileItem],
        paneIndex: Int,
        destinationFolderID: UUID? = nil
    ) {
        guard !items.isEmpty else { return }

        guard privateVault.isUnlocked else {
            vaultNeedsUnlock = true
            return
        }

        vaultSendItems = items
        vaultSendPane = paneIndex
        vaultSendDestinationID = destinationFolderID
        showVaultSendConfirm = true
    }

    private func performSendToVault(deleteOriginals: Bool) {
        let items = vaultSendItems
        let sourcePane = pane(at: vaultSendPane)
        let destinationID = vaultSendDestinationID

        vaultSendItems = []
        vaultSendDestinationID = nil

        guard let root = sourcePane.location?.rootURL, !items.isEmpty else {
            return
        }

        let title = items.count == 1
            ? "\(deleteOriginals ? "Mover" : "Copiar") \(items[0].name) a la bóveda"
            : "\(deleteOriginals ? "Mover" : "Copiar") \(items.count) elementos a la bóveda"

        let vault = privateVault

        operationQueue.enqueue(title: title, kind: deleteOriginals ? .move : .copy) {
            for item in items {
                try ExplorerFileEngine.ensureInsideRoot(item.url, root: root)
                guard vault.isUnlocked else { throw PrivateVaultError.locked }
                try await ExplorerVaultBridge.send(
                    item.url,
                    into: vault,
                    parentID: destinationID
                )
            }

            if deleteOriginals {
                guard vault.isUnlocked else { throw PrivateVaultError.locked }
                try await ExplorerFileEngine.delete(items, root: root)
            }
            await sourcePane.refresh()
        }
    }

    private func toggleSplit() {
        if splitOpen {
            withAnimation(.easeInOut(duration: 0.2)) {
                splitOpen = false
                vaultPaneOpen = false
                vaultSplitFolderID = nil
            }
        } else {
            openSplit()
        }
    }

    /// El segundo panel es una vista de la sesión cifrada, NO una carpeta
    /// con archivos descifrados. El original nunca se borra sin confirmación.
    private func openVaultSplit() {
        if activePane == 1, let location = rightPane.location,
           let folder = rightPane.currentURL {
            leftPane.openLocation(location, folderURL: folder)
        }
        activePane = 0
        vaultSplitFolderID = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            vaultPaneOpen = true
            splitOpen = true
        }
    }

    private func showTwoFilePanes() {
        vaultSplitFolderID = nil
        if let location = leftPane.location,
           let folder = leftPane.currentURL,
           rightPane.currentURL == nil {
            rightPane.openLocation(location, folderURL: folder)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            vaultPaneOpen = false
            splitOpen = true
        }
    }

    /// Abre el segundo panel mostrando la misma carpeta que el activo.
    private func openSplit() {
        if
            let location = active.location,
            let folder = active.currentURL,
            other.currentURL == nil
        {
            other.openLocation(location, folderURL: folder)
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            splitOpen = true
        }
    }

    /// Mover/copiar necesita un destino: si el segundo panel está cerrado, se
    /// abre para que elijas la carpeta y vuelvas a tocar la acción.
    private func requestTransfer(
        _ items: [ExplorerFileItem],
        fromPane paneIndex: Int,
        moving: Bool
    ) {
        guard !items.isEmpty else { return }

        if !splitOpen {
            openSplit()
            splitHint = "Abrí el segundo panel. Elige ahí la carpeta de destino y vuelve a tocar "
                + (moving ? "Mover." : "Copiar.")
            return
        }

        transfer(items, fromPane: paneIndex, moving: moving)
    }

    private func importFiles(_ urls: [URL]) {
        guard
            !urls.isEmpty,
            let currentURL = active.currentURL,
            let location = active.location
        else {
            return
        }

        let targetPane = active

        Task {
            isOperating = true
            defer { isOperating = false }

            do {
                for url in urls {
                    try await ExplorerFileEngine.importFile(
                        from: url,
                        into: currentURL,
                        root: location.rootURL
                    )
                }
                await targetPane.refresh()
            } catch {
                globalError = ExplorerErrorText.message(for: error)
            }
        }
    }

    @ViewBuilder
    private func paneView(
        _ pane: ExplorerPaneState,
        index: Int
    ) -> some View {
        ExplorerPaneView(
            pane: pane,
            paneIndex: index,
            isActive: activePane == index,
            showsActiveMarker: splitOpen,
            showSearch: Binding(
                get: { searchingPaneIndex == index },
                set: { searchingPaneIndex = $0 ? index : nil }
            ),
            onActivate: {
                activePane = index
            },
            onOpenFile: { item in
                activePane = index

                if ExplorerPackageArchive.recognizes(item.url),
                   let root = pane.location?.rootURL,
                   let dir = pane.currentURL {
                    let alternate = index == 0 ? rightPane : leftPane
                    packageTarget = ExplorerPackageTarget(
                        url: item.url,
                        sourceRoot: root,
                        destinationDirectory: dir,
                        destinationRoot: root,
                        otherDirectory: splitOpen ? alternate.currentURL : nil,
                        otherRoot: splitOpen ? alternate.location?.rootURL : nil
                    )
                } else if ExplorerTextEditorView.canEdit(item) {
                    openEditor(item, paneIndex: index)
                } else if NikaidoRegularVideoPlayer.supports(item) {
                    regularVideoTarget = NikaidoRegularVideoTarget(url: item.url)
                } else {
                    previewTarget = ExplorerPreviewTarget(url: item.url)
                }
            },
            onRename: { item in
                activePane = index
                renameText = item.name
                pendingAction = .rename(item, pane: index)
            },
            onDelete: { item in
                activePane = index
                requestDelete(
                    [item],
                    paneIndex: index
                )
            },
            onCopyToOther: { item in
                activePane = index
                requestTransfer(
                    [item],
                    fromPane: index,
                    moving: false
                )
            },
            onMoveToOther: { item in
                activePane = index
                requestTransfer(
                    [item],
                    fromPane: index,
                    moving: true
                )
            },
            onShare: { item in
                activePane = index
                shareURLs = [item.url]
                showShareSheet = true
            },
            onExtract: { item in
                activePane = index
                archivePassword = ""
                pendingAction = .extract(
                    item,
                    pane: index
                )
            },
            onCompress: { item in
                activePane = index
                compress(
                    [item],
                    paneIndex: index
                )
            },
            onFavorite: { item in
                activePane = index
                addFavorite(item, paneIndex: index)
            },
            onSendToVault: { item in
                activePane = index
                requestSendToVault([item], paneIndex: index)
            },
            onInfo: { item in
                activePane = index
                infoTarget = item
            },
            onEdit: { item in
                openEditor(item, paneIndex: index)
            },
            onDropProviders: { providers in
                handleDrop(providers, destinationPane: index)
            },
            onDropIntoFolder: { providers, folder in
                handleDrop(providers, destinationPane: index, folder: folder)
            },
            onCustomDrop: { request in
                performDrop(request)
            },
            dragState: dragState,
            externalLocations: locations.locations.filter { $0.kind == .authorized },
            onOpenLocation: { location in
                activePane = index
                self.pane(at: index).openLocation(location)
            },
            onGoHome: {
                activePane = index

                if let local = locations.localLocation {
                    self.pane(at: index).openLocation(local)
                }
            }
        )
    }

    private var selectionToolbar: some View {
        HStack(spacing: 8) {
            Text(
                "\(active.selectedItems.count) seleccionado(s)"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                active.selectAll()
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Seleccionar todo")

            Button {
                requestTransfer(
                    active.selectedItems,
                    fromPane: activePane,
                    moving: false
                )
            } label: {
                Label("Copiar", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(active.selectedItems.isEmpty)

            Button {
                requestTransfer(
                    active.selectedItems,
                    fromPane: activePane,
                    moving: true
                )
            } label: {
                Label("Mover", systemImage: "arrow.right.square")
            }
            .buttonStyle(.borderedProminent)
            .disabled(active.selectedItems.isEmpty)

            Menu {
                Button {
                    shareURLs = active.selectedItems.map(\.url)
                    showShareSheet = !shareURLs.isEmpty
                } label: {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }

                Button {
                    compress(
                        active.selectedItems,
                        paneIndex: activePane
                    )
                } label: {
                    Label("Comprimir ZIP", systemImage: "archivebox")
                }

                Button {
                    requestSendToVault(
                        active.selectedItems,
                        paneIndex: activePane
                    )
                } label: {
                    Label("Mover a la bóveda", systemImage: "lock.shield")
                }

                Button(role: .destructive) {
                    requestDelete(
                        active.selectedItems,
                        paneIndex: activePane
                    )
                } label: {
                    Label("Eliminar", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(.bordered)
            .disabled(active.selectedItems.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func pane(at index: Int) -> ExplorerPaneState {
        index == 0 ? leftPane : rightPane
    }

    private func oppositePane(
        of index: Int
    ) -> ExplorerPaneState {
        index == 0 ? rightPane : leftPane
    }

    private var floatingAddButton: some View {
        let canCreate = active.currentURL != nil

        return Menu {
            Button {
                newFolderName = ""
                showNewFolder = true
            } label: {
                Label("Nueva carpeta", systemImage: "folder.badge.plus")
            }

            Button {
                newItemName = ExplorerNewItemKind.textDocument.defaultName
                newItemKind = .textDocument
            } label: {
                Label("Documento de texto", systemImage: "doc.text")
            }

            Button {
                newItemName = ExplorerNewItemKind.zipArchive.defaultName
                newItemKind = .zipArchive
            } label: {
                Label("Archivo ZIP", systemImage: "doc.zipper")
            }

            Divider()

            Button {
                showFileImporter = true
            } label: {
                Label("Importar desde Archivos", systemImage: "square.and.arrow.down")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .modifier(NikaidoGlassFloatingCircle(tint: nikaidoAccent))
        }
        .disabled(!canCreate)
        .opacity(canCreate ? 1 : 0.4)
        .padding(.horizontal, 3)
    }

    private func createNewItem() {
        guard
            let kind = newItemKind,
            let currentURL = active.currentURL,
            let location = active.location
        else {
            newItemKind = nil
            newItemName = ""
            return
        }

        let targetPane = active
        let fileName = kind.finalName(from: newItemName)
        newItemName = ""
        newItemKind = nil

        Task {
            isOperating = true
            defer { isOperating = false }

            do {
                try await ExplorerFileEngine.createFile(
                    named: fileName,
                    contents: kind.initialData,
                    in: currentURL,
                    root: location.rootURL
                )
                await targetPane.refresh()
            } catch {
                globalError = ExplorerErrorText.message(for: error)
            }
        }
    }

    private func createFolder() {
        guard
            let currentURL = active.currentURL,
            let location = active.location
        else {
            return
        }

        let name = newFolderName
        newFolderName = ""

        Task {
            isOperating = true
            defer { isOperating = false }

            do {
                try await ExplorerFileEngine.createFolder(
                    named: name,
                    in: currentURL,
                    root: location.rootURL
                )
                await active.refresh()
            } catch {
                globalError = ExplorerErrorText.message(for: error)
            }
        }
    }

    private func performRename() {
        guard case .rename(let item, let paneIndex) = pendingAction else {
            return
        }

        let targetPane = pane(at: paneIndex)

        guard let location = targetPane.location else {
            return
        }

        let name = renameText
        renameText = ""
        pendingAction = nil

        Task {
            isOperating = true
            defer { isOperating = false }

            do {
                try await ExplorerFileEngine.rename(
                    item,
                    to: name,
                    root: location.rootURL
                )
                await targetPane.refresh()
            } catch {
                globalError = ExplorerErrorText.message(for: error)
            }
        }
    }

    private func requestDelete(
        _ items: [ExplorerFileItem],
        paneIndex: Int
    ) {
        guard !items.isEmpty else { return }

        if confirmDelete {
            pendingAction = .delete(
                items,
                pane: paneIndex
            )
        } else {
            pendingAction = .delete(
                items,
                pane: paneIndex
            )
            performDelete()
        }
    }

    private func performDelete() {
        guard case .delete(let items, let paneIndex) = pendingAction else {
            return
        }
        let targetPane = pane(at: paneIndex)
        guard let location = targetPane.location else { return }
        pendingAction = nil

        operationQueue.enqueue(
            title: items.count == 1 ? "Eliminar \(items[0].name)" : "Eliminar \(items.count) elementos",
            kind: .trash,
            totalUnits: items.count
        ) {
            try await trash.moveToTrash(items, root: location.rootURL)
            await targetPane.refresh()
        }
    }

    private func transfer(
        _ items: [ExplorerFileItem],
        fromPane paneIndex: Int,
        moving: Bool
    ) {
        guard !items.isEmpty else { return }

        let sourcePane = pane(at: paneIndex)
        let destinationPane = oppositePane(of: paneIndex)
        guard let sourceRoot = sourcePane.location?.rootURL,
              let destinationRoot = destinationPane.location?.rootURL,
              let destinationDirectory = destinationPane.currentURL
        else {
            globalError = "Abre una ubicación en ambos paneles primero."
            return
        }

        let title = moving
            ? (items.count == 1 ? "Mover \(items[0].name)" : "Mover \(items.count) elementos")
            : (items.count == 1 ? "Copiar \(items[0].name)" : "Copiar \(items.count) elementos")

        operationQueue.enqueue(
            title: title,
            kind: moving ? .move : .copy,
            totalUnits: items.count
        ) {
            if moving {
                try await ExplorerFileEngine.move(
                    items, sourceRoot: sourceRoot, to: destinationDirectory,
                    destinationRoot: destinationRoot, conflictPolicy: conflictPolicy
                )
            } else {
                try await ExplorerFileEngine.copy(
                    items, sourceRoot: sourceRoot, to: destinationDirectory,
                    destinationRoot: destinationRoot, conflictPolicy: conflictPolicy
                )
            }
            await sourcePane.refresh()
            await destinationPane.refresh()
        }
        sourcePane.clearSelection()
        sourcePane.selectionMode = false
    }

    /// Arrastre del sistema (por si llega desde otra fuente): mueve a la
    /// carpeta indicada o a la carpeta actual del panel donde se soltó.
    private func handleDrop(
        _ providers: [NSItemProvider],
        destinationPane: Int,
        folder: ExplorerFileItem? = nil
    ) -> Bool {
        Task {
            do {
                let payload = try await ExplorerDragPayload.load(from: providers)
                let sourcePane = pane(at: payload.sourcePane)
                let urlSet = Set(payload.urls)
                let dragged = sourcePane.items.filter {
                    urlSet.contains($0.url.absoluteString)
                }

                guard !dragged.isEmpty else {
                    globalError = "Los archivos arrastrados ya no están en el panel de origen."
                    return
                }

                if let folder {
                    moveItems(
                        dragged,
                        fromPane: payload.sourcePane,
                        intoFolder: folder.url,
                        destinationPane: destinationPane
                    )
                } else {
                    guard
                        payload.sourcePane != destinationPane,
                        let destination = pane(at: destinationPane).currentURL
                    else {
                        return
                    }

                    moveItems(
                        dragged,
                        fromPane: payload.sourcePane,
                        intoFolder: destination,
                        destinationPane: destinationPane
                    )
                }
            } catch {
                globalError = ExplorerErrorText.message(for: error)
            }
        }

        return true
    }

    /// Soltar con el asa de arrastre: sobre una carpeta o sobre el otro panel.
    private func performDrop(_ request: ExplorerDropRequest) {
        switch request.target {
        case .vaultFolder(let id) where splitOpen && vaultPaneOpen && request.sourcePane == 0:
            requestSendToVault(request.items, paneIndex: 0, destinationFolderID: id)
        case .pane(let index) where index == 1 && splitOpen && vaultPaneOpen
                                    && request.sourcePane == 0:
            requestSendToVault(
                request.items,
                paneIndex: request.sourcePane,
                destinationFolderID: vaultSplitFolderID
            )
        default:
            pendingDrop = request
        }
    }

    /// Arrastre nativo opcional, usa el mismo token seguro que Takopi Files.
    private func handleVaultDrop(
        _ providers: [NSItemProvider],
        destinationFolderID: UUID? = nil
    ) -> Bool {
        guard splitOpen, vaultPaneOpen, privateVault.isUnlocked else { return false }
        Task {
            do {
                let payload = try await ExplorerDragPayload.load(from: providers)
                guard payload.sourcePane == 0 else { return }
                let urlSet = Set(payload.urls)
                let items = leftPane.items.filter { urlSet.contains($0.url.absoluteString) }
                guard items.count == urlSet.count, !items.isEmpty else {
                    globalError = "No se encontraron todos los archivos originales del arrastre."
                    return
                }
                requestSendToVault(
                    items,
                    paneIndex: 0,
                    destinationFolderID: destinationFolderID ?? vaultSplitFolderID
                )
            } catch {
                globalError = ExplorerErrorText.message(for: error)
            }
        }
        return true
    }

    private func executeDrop(moving: Bool) {
        guard let request = pendingDrop else { return }
        pendingDrop = nil
        switch request.target {
        case .vaultFolder(let folderID):
            guard vaultPaneOpen, splitOpen, request.sourcePane == 0 else { return }
            requestSendToVault(request.items, paneIndex: 0, destinationFolderID: folderID)
        case .folder(let folder, let paneIndex):
            moveItems(
                request.items,
                fromPane: request.sourcePane,
                intoFolder: folder.url,
                destinationPane: paneIndex, moving: moving
            )
        case .pane(let paneIndex):
            guard
                paneIndex != request.sourcePane,
                let destination = pane(at: paneIndex).currentURL
            else {
                return
            }

            moveItems(
                request.items,
                fromPane: request.sourcePane,
                intoFolder: destination,
                destinationPane: paneIndex, moving: moving
            )
        case .location(let location):
            moveItems(
                request.items,
                fromPane: request.sourcePane,
                intoFolder: location.rootURL,
                destinationRoot: location.rootURL, moving: moving
            )
        }
    }

    /// Mueve elementos a una carpeta concreta (de cualquiera de los paneles).
    private func moveItems(
        _ items: [ExplorerFileItem],
        fromPane sourceIndex: Int,
        intoFolder destinationDirectory: URL,
        destinationPane destinationIndex: Int,
        moving: Bool = true
    ) {
        guard let destinationRoot = pane(at: destinationIndex).location?.rootURL else {
            globalError = "Abre una ubicación en ambos paneles primero."
            return
        }

        moveItems(
            items,
            fromPane: sourceIndex,
            intoFolder: destinationDirectory,
            destinationRoot: destinationRoot,
            moving: moving
        )
    }

    /// Mueve a una carpeta de cualquier ubicación (raíz de destino explícita).
    private func moveItems(
        _ items: [ExplorerFileItem],
        fromPane sourceIndex: Int,
        intoFolder destinationDirectory: URL,
        destinationRoot: URL,
        moving: Bool = true
    ) {
        let sourcePane = pane(at: sourceIndex)

        guard let sourceRoot = sourcePane.location?.rootURL else {
            globalError = "Abre una ubicación en el panel de origen primero."
            return
        }

        let destinationPath = destinationDirectory.standardizedFileURL.path

        // No tiene sentido mover algo adonde ya está, ni una carpeta dentro de
        // sí misma o de sus subcarpetas.
        let movable = items.filter { item in
            let itemPath = item.url.standardizedFileURL.path
            let parentPath = item.url.deletingLastPathComponent().standardizedFileURL.path

            if parentPath == destinationPath {
                return false
            }

            if item.isDirectory,
               destinationPath == itemPath || destinationPath.hasPrefix(itemPath + "/")
            {
                return false
            }

            return true
        }

        guard !movable.isEmpty else {
            globalError = "Ese elemento ya está en esa carpeta, o no se puede mover dentro de sí mismo."
            return
        }

        let folderName = destinationDirectory.lastPathComponent
        let title = movable.count == 1
            ? "\(moving ? "Mover" : "Copiar") \(movable[0].name) a \(folderName)"
            : "\(moving ? "Mover" : "Copiar") \(movable.count) elementos a \(folderName)"

        operationQueue.enqueue(
            title: title,
            kind: moving ? .move : .copy,
            totalUnits: movable.count
        ) {
            if moving {
                try await ExplorerFileEngine.move(
                    movable, sourceRoot: sourceRoot, to: destinationDirectory,
                    destinationRoot: destinationRoot, conflictPolicy: conflictPolicy
                )
            } else {
                try await ExplorerFileEngine.copy(
                    movable, sourceRoot: sourceRoot, to: destinationDirectory,
                    destinationRoot: destinationRoot, conflictPolicy: conflictPolicy
                )
            }
            await leftPane.refresh()
            await rightPane.refresh()
        }

        sourcePane.clearSelection()
        sourcePane.selectionMode = false
    }

    private func compress(
        _ items: [ExplorerFileItem],
        paneIndex: Int
    ) {
        guard !items.isEmpty else { return }

        let targetPane = pane(at: paneIndex)

        guard
            let currentURL = targetPane.currentURL,
            let root = targetPane.location?.rootURL
        else {
            return
        }

        Task {
            isOperating = true
            defer { isOperating = false }

            do {
                _ = try await ExplorerArchiveManager.createZIP(
                    from: items,
                    in: currentURL,
                    root: root
                )
                await targetPane.refresh()
            } catch {
                globalError = ExplorerErrorText.message(for: error)
            }
        }
    }

    private func performExtract() {
        guard case .extract(let item, let paneIndex) = pendingAction else {
            return
        }

        let targetPane = pane(at: paneIndex)

        guard
            let currentURL = targetPane.currentURL,
            let root = targetPane.location?.rootURL
        else {
            return
        }

        let password = archivePassword.isEmpty
            ? nil
            : archivePassword

        pendingAction = nil
        archivePassword = ""

        Task {
            isOperating = true
            defer { isOperating = false }

            var destination = currentURL.appendingPathComponent(
                item.url.deletingPathExtension().lastPathComponent,
                isDirectory: true
            )

            if FileManager.default.fileExists(
                atPath: destination.path
            ) {
                destination = ExplorerFileEngine.uniqueDestination(
                    for: destination,
                    in: currentURL
                )
            }

            do {
                try await ExplorerArchiveManager.extract(
                    archiveURL: item.url,
                    to: destination,
                    root: root,
                    password: password
                )

                await targetPane.refresh()
            } catch {
                globalError = ExplorerErrorText.message(for: error)
            }
        }
    }
}

struct ExplorerPaneView: View {
    @Environment(\.nikaidoAccent) private var nikaidoAccent
    @ObservedObject var pane: ExplorerPaneState

    let paneIndex: Int
    let isActive: Bool
    let showsActiveMarker: Bool
    @Binding var showSearch: Bool
    let onActivate: () -> Void
    let onOpenFile: (ExplorerFileItem) -> Void
    let onRename: (ExplorerFileItem) -> Void
    let onDelete: (ExplorerFileItem) -> Void
    let onCopyToOther: (ExplorerFileItem) -> Void
    let onMoveToOther: (ExplorerFileItem) -> Void
    let onShare: (ExplorerFileItem) -> Void
    let onExtract: (ExplorerFileItem) -> Void
    let onCompress: (ExplorerFileItem) -> Void
    let onFavorite: (ExplorerFileItem) -> Void
    let onSendToVault: (ExplorerFileItem) -> Void
    let onInfo: (ExplorerFileItem) -> Void
    let onEdit: (ExplorerFileItem) -> Void
    let onDropProviders: ([NSItemProvider]) -> Bool
    let onDropIntoFolder: ([NSItemProvider], ExplorerFileItem) -> Bool
    let onCustomDrop: (ExplorerDropRequest) -> Void
    @ObservedObject var dragState: ExplorerDragState
    let externalLocations: [ExplorerStorageLocation]
    let onOpenLocation: (ExplorerStorageLocation) -> Void
    let onGoHome: () -> Void

    @State private var targetedFolderID: String?

    @ObservedObject private var folderColors = NikaidoFolderColors.shared
    @Environment(\.nikaidoFolderColor) private var defaultFolderColor

    private func tint(for item: ExplorerFileItem) -> Color {
        guard item.isDirectory else { return Color.secondary }

        if
            let hex = folderColors.hex(for: item.url),
            let color = Color(nikaidoHex: hex)
        {
            return color
        }

        return defaultFolderColor
    }

    @State private var isDropTargeted = false
    @AppStorage("NikaidoExplorer.showMediaThumbnails")
    private var showMediaThumbnails = true

    var body: some View {
        VStack(spacing: 0) {
            if showSearch || !pane.search.isEmpty {
                paneHeader
            }

            if pane.isLoading && pane.items.isEmpty {
                Spacer()
                ProgressView("Leyendo…")
                Spacer()
            } else if pane.currentURL == nil {
                emptyLocation
            } else {
                fileContent
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onActivate()
        }
        .overlay(
            Rectangle()
                .stroke(
                    nikaidoAccent,
                    lineWidth: (isDropTargeted || dragState.highlightedPane == paneIndex) ? 3 : 0
                )
                .allowsHitTesting(false)
        )
        .explorerPaneProbe(dragState, pane: paneIndex)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(nikaidoAccent)
                .frame(height: 2)
                .opacity(isActive && showsActiveMarker ? 1 : 0)
                .allowsHitTesting(false)
        }
    }

    // Un solo encabezado para cada panel: nombre/ruta sin botones duplicados.
    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showSearch || !pane.search.isEmpty {
                NikaidoSearchField(
                    text: $pane.search,
                    placeholder: "Buscar en este panel"
                ) {
                    Task { await pane.refresh() }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var fileContent: some View {
        if pane.viewMode == .grid {
            fileGrid.background(ExplorerDragEdgeScroll(state: dragState))
        } else {
            fileList.background(ExplorerDragEdgeScroll(state: dragState))
        }
    }

    private var fileList: some View {
        List {
            if let error = pane.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if showsExternalLocations {
                Section("Carpetas añadidas") {
                    ForEach(externalLocations) { location in
                        ExplorerExternalLocationRow(
                            location: location,
                            isDropTarget: isExternalDropTarget(location)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onActivate()
                            onOpenLocation(location)
                        }
                        .explorerExternalProbe(dragState, location: location)
                    }
                }
            }

            if pane.items.isEmpty && pane.errorMessage == nil && !showsExternalLocations {
                emptyFolderRow
            }

            ForEach(pane.items) { item in
                ExplorerFileRow(
                    item: item,
                    tint: tint(for: item),
                    selected: pane.selectedIDs.contains(item.id),
                    selectionMode: pane.selectionMode,
                    showMediaThumbnails: showMediaThumbnails,
                    isDropTarget: isFolderDropTarget(item),
                    dragCallbacks: dragCallbacks(for: item)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    activate(item)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(item.name)
                .accessibilityValue(item.isDirectory ? "Carpeta" : item.formattedSize)
                .accessibilityHint(pane.selectionMode ? "Doble toque para seleccionar" : "Doble toque para abrir")
                .accessibilityAction(named: "Abrir o seleccionar") {
                    activate(item)
                }
                .contextMenu {
                    itemContextMenu(item)
                }
                .explorerFolderProbe(dragState, pane: paneIndex, item: item)
                .onDrop(
                    of: item.isDirectory ? [UTType.plainText.identifier] : [],
                    isTargeted: folderTargetBinding(for: item)
                ) { providers in
                    guard item.isDirectory else { return false }
                    return onDropIntoFolder(providers, item)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        onDelete(item)
                    } label: {
                        Label("Eliminar", systemImage: "trash")
                    }

                    Button {
                        onShare(item)
                    } label: {
                        Label("Compartir", systemImage: "square.and.arrow.up")
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if item.isDirectory {
                        Button {
                            onFavorite(item)
                        } label: {
                            Label("Favorito", systemImage: "star")
                        }
                        .tint(.yellow)
                    }

                    Button {
                        onSendToVault(item)
                    } label: {
                        Label("A la bóveda", systemImage: "lock.shield")
                    }
                    .tint(.indigo)
                }
            }
        }
        .onDrop(of: [UTType.plainText.identifier], isTargeted: $isDropTargeted) { providers in
            onDropProviders(providers)
        }
        .listStyle(.plain)
        .scrollDisabled(dragState.isDragging)
        .refreshable {
            await pane.refresh()
        }
    }

    private var fileGrid: some View {
        ScrollView {
            if let error = pane.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            if showsExternalLocations {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 100, maximum: 145),
                            spacing: 10
                        )
                    ],
                    spacing: 10
                ) {
                    ForEach(externalLocations) { location in
                        ExplorerExternalLocationCell(
                            location: location,
                            isDropTarget: isExternalDropTarget(location)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onActivate()
                            onOpenLocation(location)
                        }
                        .explorerExternalProbe(dragState, location: location)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }

            if pane.items.isEmpty && pane.errorMessage == nil && !showsExternalLocations {
                NikaidoEmptyState(
                    systemName: "tray",
                    title: "Esta carpeta está vacía",
                    message: "Toca el botón + para crear algo o arrastra archivos desde el otro panel."
                )
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 100, maximum: 145),
                            spacing: 10
                        )
                    ],
                    spacing: 10
                ) {
                    ForEach(pane.items) { item in
                        ExplorerFileGridCell(
                            item: item,
                            tint: tint(for: item),
                            selected: pane.selectedIDs.contains(item.id),
                            selectionMode: pane.selectionMode,
                            showMediaThumbnails: showMediaThumbnails,
                            isDropTarget: isFolderDropTarget(item),
                            dragCallbacks: dragCallbacks(for: item)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            activate(item)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(item.name)
                        .accessibilityValue(item.isDirectory ? "Carpeta" : item.formattedSize)
                        .accessibilityAction(named: "Abrir o seleccionar") {
                            activate(item)
                        }
                        .contextMenu {
                            itemContextMenu(item)
                        }
                        .explorerFolderProbe(dragState, pane: paneIndex, item: item)
                        .onDrop(
                            of: item.isDirectory ? [UTType.plainText.identifier] : [],
                            isTargeted: folderTargetBinding(for: item)
                        ) { providers in
                            guard item.isDirectory else { return false }
                            return onDropIntoFolder(providers, item)
                        }
                    }
                }
                .padding(10)
            }
        }
        .onDrop(of: [UTType.plainText.identifier], isTargeted: $isDropTargeted) { providers in
            onDropProviders(providers)
        }
        .scrollDisabled(dragState.isDragging)
        .refreshable {
            await pane.refresh()
        }
    }

    private func dragProvider(for item: ExplorerFileItem) -> NSItemProvider {
        let items: [ExplorerFileItem]
        if pane.selectedIDs.contains(item.id), !pane.selectedItems.isEmpty {
            items = pane.selectedItems
        } else {
            items = [item]
        }
        return ExplorerDragPayload(
            urls: items.map { $0.url.absoluteString },
            sourcePane: paneIndex
        ).itemProvider()
    }

    /// En la raíz del almacenamiento de Nikaido se muestran también las
    /// carpetas añadidas (iCloud / iPhone), cada una con su distintivo.
    private var showsExternalLocations: Bool {
        guard
            !externalLocations.isEmpty,
            pane.search.isEmpty,
            let location = pane.location,
            location.kind == .local,
            let current = pane.currentURL
        else {
            return false
        }

        return current.standardizedFileURL.path
            == location.rootURL.standardizedFileURL.path
    }

    private func isExternalDropTarget(_ location: ExplorerStorageLocation) -> Bool {
        dragState.highlightedFolderKey == ExplorerDragState.externalKey(location.id)
    }

    private func dragItems(for item: ExplorerFileItem) -> [ExplorerFileItem] {
        if pane.selectedIDs.contains(item.id), !pane.selectedItems.isEmpty {
            return pane.selectedItems
        }

        return [item]
    }

    private func dragCallbacks(for item: ExplorerFileItem) -> ExplorerDragCallbacks {
        ExplorerDragCallbacks(
            began: { point in
                onActivate()
                NikaidoTheme.haptic(.medium)
                dragState.begin(
                    items: dragItems(for: item),
                    sourcePane: paneIndex,
                    at: point
                )
            },
            moved: { point in
                dragState.move(to: point)
            },
            ended: { point, completed in
                if completed, let request = dragState.finish(at: point) {
                    onCustomDrop(request)
                } else {
                    dragState.cancel()
                }
            }
        )
    }

    private func isFolderDropTarget(_ item: ExplorerFileItem) -> Bool {
        guard item.isDirectory else { return false }

        return dragState.highlightedFolderKey
            == ExplorerDragState.folderKey(pane: paneIndex, id: item.id)
            || targetedFolderID == item.id
    }

    private func folderTargetBinding(for item: ExplorerFileItem) -> Binding<Bool> {
        Binding(
            get: { targetedFolderID == item.id },
            set: { isTargeted in
                if isTargeted {
                    targetedFolderID = item.id
                } else if targetedFolderID == item.id {
                    targetedFolderID = nil
                }
            }
        )
    }

    private var emptyFolderRow: some View {
        NikaidoEmptyState(
            systemName: "tray",
            title: "Esta carpeta está vacía",
            message: "Toca el botón + para crear algo o arrastra archivos desde el otro panel."
        )
        .listRowSeparator(.hidden)
    }

    private func activate(_ item: ExplorerFileItem) {
        onActivate()

        if pane.selectionMode {
            pane.toggleSelection(item)
        } else if item.isDirectory {
            pane.open(item)
        } else {
            onOpenFile(item)
        }
    }

    @ViewBuilder
    private func itemContextMenu(_ item: ExplorerFileItem) -> some View {
        if item.isDirectory {
            Button {
                pane.open(item)
            } label: {
                Label("Abrir", systemImage: "folder")
            }
        } else {
            Button {
                onOpenFile(item)
            } label: {
                Label(item.isAppPackage || item.pathExtension == "zip"
                      ? "Explorar contenido" : "Vista rápida", systemImage: "eye")
            }
        }

        if !item.isDirectory && !ExplorerTextEditorView.canEdit(item) {
            Button {
                onEdit(item)
            } label: {
                Label("Editar como texto", systemImage: "square.and.pencil")
            }
        }

        Button {
            onCopyToOther(item)
        } label: {
            Label(
                "Copiar al otro panel",
                systemImage: "doc.on.doc"
            )
        }

        Button {
            onMoveToOther(item)
        } label: {
            Label(
                "Mover al otro panel",
                systemImage: "arrow.right.square"
            )
        }

        Button {
            onRename(item)
        } label: {
            Label("Renombrar", systemImage: "pencil")
        }

        Button {
            onShare(item)
        } label: {
            Label(
                "Compartir",
                systemImage: "square.and.arrow.up"
            )
        }

        Button {
            onCompress(item)
        } label: {
            Label(
                "Comprimir en ZIP",
                systemImage: "archivebox"
            )
        }

        Button {
            onSendToVault(item)
        } label: {
            Label("Mover a la bóveda", systemImage: "lock.shield")
        }

        if item.isDirectory {
            Button {
                onFavorite(item)
            } label: {
                Label("Añadir a favoritos", systemImage: "star")
            }

            Menu {
                ForEach(NikaidoThemePalette.swatches) { swatch in
                    Button {
                        folderColors.set(swatch.hex, for: item.url)
                    } label: {
                        if folderColors.hex(for: item.url) == swatch.hex {
                            Label(swatch.name, systemImage: "checkmark")
                        } else {
                            Text(swatch.name)
                        }
                    }
                }

                Button("Predeterminado") {
                    folderColors.set(nil, for: item.url)
                }
            } label: {
                Label("Color de la carpeta", systemImage: "paintpalette")
            }
        }

        Button {
            onInfo(item)
        } label: {
            Label("Información", systemImage: "info.circle")
        }

        if item.isArchive {
            Button {
                onExtract(item)
            } label: {
                Label(
                    "Extraer…",
                    systemImage: "archivebox.fill"
                )
            }
        }

        Button(role: .destructive) {
            onDelete(item)
        } label: {
            Label("Eliminar", systemImage: "trash")
        }
    }

    private var emptyLocation: some View {
        VStack(spacing: 12) {
            Spacer()

            NikaidoEmptyState(
                systemName: "externaldrive.badge.plus",
                title: "Elige dónde trabajar",
                message: "Toca el ícono del disco, arriba, para conectar tu almacenamiento."
            )

            Spacer()
        }
    }
}

struct ExplorerMediaThumbnail: View {
    let item: ExplorerFileItem
    let tint: Color

    @State private var image: UIImage?
    @State private var isLoading = false

    init(item: ExplorerFileItem, tint: Color) {
        self.item = item
        self.tint = tint
    }

    /// La miniatura se dibuja sobre un contenedor flexible (`Color.clear`):
    /// el tamaño lo decide la celda, no la imagen, y lo que sobra se recorta.
    private var thumbnailContent: some View {
        ZStack {
            tint.opacity(0.12)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Image(systemName: item.systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(tint)
            }

            if isLoading && image == nil {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .padding(6)
                    .background(.black.opacity(0.42), in: Circle())
            }

            if item.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: image == nil ? 26 : 32))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
                    .opacity(isLoading && image == nil ? 0.45 : 0.95)
            }
        }
    }

    var body: some View {
        Color.clear
            .overlay {
                thumbnailContent
            }
            .clipped()
        .task(id: item.id) {
            image = nil

            guard item.hasMediaThumbnail || item.isAppPackage else { return }

            isLoading = true
            defer { isLoading = false }

            let thumbnail: UIImage?
            if item.isAppPackage {
                let url = item.url
                thumbnail = await Task.detached(priority: .utility) {
                    ExplorerPackageIconStore.shared.icon(for: url)
                }.value
            } else {
                thumbnail = await ExplorerMediaThumbnailGenerator.thumbnail(
                    for: item.url,
                    size: CGSize(width: 360, height: 360)
                )
            }

            guard !Task.isCancelled else { return }
            image = thumbnail
        }
    }
}

@MainActor
private enum ExplorerMediaThumbnailGenerator {
    static func thumbnail(for url: URL, size: CGSize) async -> UIImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: 2,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(
                for: request
            ) { representation, _ in
                continuation.resume(returning: representation?.uiImage)
            }
        }
    }
}

private struct ExplorerFileRow: View {
    @Environment(\.nikaidoAccent) private var nikaidoAccent
    let item: ExplorerFileItem
    let tint: Color
    let selected: Bool
    let selectionMode: Bool
    let showMediaThumbnails: Bool
    let isDropTarget: Bool
    let dragCallbacks: ExplorerDragCallbacks

    var body: some View {
        HStack(spacing: 12) {
            if selectionMode {
                Image(
                    systemName: selected
                    ? "checkmark.circle.fill"
                    : "circle"
                )
                .font(.title3)
                .foregroundStyle(
                    selected
                    ? nikaidoAccent
                    : Color.secondary.opacity(0.6)
                )
                .transition(.scale.combined(with: .opacity))
            }

            if (item.hasMediaThumbnail && showMediaThumbnails) || item.isAppPackage {
                ExplorerMediaThumbnail(item: item, tint: tint)
                    .frame(width: 44, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            } else {
                NikaidoIconBadge(
                    systemName: item.systemImage,
                    tint: tint,
                    size: 30
                )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if !item.formattedSize.isEmpty {
                        Text(item.formattedSize)
                    }

                    if !item.formattedSize.isEmpty, item.modifiedAt != nil {
                        Text("•")
                    }

                    if let modified = item.modifiedAt {
                        Text(
                            modified.formatted(
                                date: .abbreviated,
                                time: .omitted
                            )
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if item.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            // Asa para arrastrar a una carpeta o al otro panel: no choca con el
            // menú de mantener presionado ni con el toque de la fila.
            ExplorerDragHandle(callbacks: dragCallbacks)
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isDropTarget
                    ? nikaidoAccent.opacity(0.22)
                    : (selected ? nikaidoAccent.opacity(0.10) : Color.clear)
                )
                .padding(.horizontal, -6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(nikaidoAccent, lineWidth: isDropTarget ? 2 : 0)
                .padding(.horizontal, -6)
        )
        .animation(.easeInOut(duration: 0.15), value: selected)
        .animation(.easeInOut(duration: 0.15), value: selectionMode)
    }
}


private struct ExplorerFileGridCell: View {
    @Environment(\.nikaidoAccent) private var nikaidoAccent
    let item: ExplorerFileItem
    let tint: Color
    let selected: Bool
    let selectionMode: Bool
    let showMediaThumbnails: Bool
    let isDropTarget: Bool
    let dragCallbacks: ExplorerDragCallbacks

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .aspectRatio(1.1, contentMode: .fit)

                if (item.hasMediaThumbnail && showMediaThumbnails) || item.isAppPackage {
                    ExplorerMediaThumbnail(item: item, tint: tint)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                } else {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if selectionMode {
                    Image(
                        systemName: selected
                        ? "checkmark.circle.fill"
                        : "circle"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        selected
                        ? nikaidoAccent
                        : Color.secondary.opacity(0.7)
                    )
                    .background(Circle().fill(.background))
                    .padding(6)
                }
            }
            .overlay(alignment: .topLeading) {
                ExplorerDragHandle(callbacks: dragCallbacks)
                    .background(.thinMaterial, in: Circle())
                    .padding(4)
            }

            Text(item.name)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)

            if !item.formattedSize.isEmpty {
                Text(item.formattedSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    (selected || isDropTarget) ? nikaidoAccent : Color.clear,
                    lineWidth: 2
                )
        )
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}

struct ExplorerStorageLocationsView: View {
    @ObservedObject var locations: SecurityScopedFolderStore
    @ObservedObject var favorites: ExplorerFavoritesStore
    @ObservedObject var leftPane: ExplorerPaneState
    @ObservedObject var rightPane: ExplorerPaneState

    @Binding var activePane: Int

    let onAddLocation: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var active: ExplorerPaneState {
        activePane == 0 ? leftPane : rightPane
    }

    var body: some View {
        NavigationView {
            List {
                if !favorites.favorites.isEmpty {
                    Section("Favoritos") {
                        ForEach(favorites.favorites) { favorite in
                            Button {
                                guard let resolved = favorites.resolve(
                                    favorite,
                                    locations: locations.locations
                                ) else {
                                    return
                                }

                                active.openLocation(
                                    resolved.0,
                                    folderURL: resolved.1
                                )
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(favorite.name)

                                        if let resolved = favorites.resolve(
                                            favorite,
                                            locations: locations.locations
                                        ) {
                                            Text(resolved.0.name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("Ubicación no disponible")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .disabled(
                                favorites.resolve(
                                    favorite,
                                    locations: locations.locations
                                ) == nil
                            )
                            .swipeActions {
                                Button(role: .destructive) {
                                    favorites.remove(favorite)
                                } label: {
                                    Label("Quitar", systemImage: "star.slash")
                                }
                            }
                        }
                    }
                }

                Section("Dispositivos de almacenamiento") {
                    ForEach(locations.locations) { location in
                        Button {
                            active.openLocation(location)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: location.source.symbol)
                                    .frame(width: 24)

                                VStack(alignment: .leading) {
                                    Text(location.name)

                                    Text(
                                        location.kind == .local
                                        ? "Almacenamiento de Takopi Explorer"
                                        : location.isPersistentReference
                                            ? location.source.title
                                            : location.source.title + " · solo esta sesión"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if active.location?.id == location.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .swipeActions {
                            if location.kind == .authorized {
                                Button(role: .destructive) {
                                    removeLocation(location)
                                } label: {
                                    Label("Quitar", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                if !locations.unavailable.isEmpty {
                    Section("No disponibles") {
                        ForEach(locations.unavailable) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)

                                    Text(item.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    locations.removeUnavailable(item)
                                } label: {
                                    Label("Quitar", systemImage: "trash")
                                }
                            }
                        }

                        Button {
                            locations.retryUnavailable()
                        } label: {
                            Label(
                                "Reintentar acceso",
                                systemImage: "arrow.clockwise"
                            )
                        }
                    }
                }

                Section {
                    Button {
                        onAddLocation()
                    } label: {
                        Label(
                            "Añadir carpeta o almacenamiento…",
                            systemImage: "plus.circle.fill"
                        )
                    }
                }

                Section {
                    Text(
                        "Selecciona una carpeta desde Archivos para autorizarla. "
                        + "Takopi Explorer puede trabajar dentro de esa raíz y "
                        + "sus subcarpetas mientras iOS mantenga el permiso. No "
                        + "equivale a acceso root del sistema."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Almacenamiento")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func removeLocation(_ location: ExplorerStorageLocation) {
        favorites.removeFavorites(for: location.id)

        if leftPane.location?.id == location.id,
           let local = locations.localLocation
        {
            leftPane.openLocation(local)
        }

        if rightPane.location?.id == location.id,
           let local = locations.localLocation
        {
            rightPane.openLocation(local)
        }

        locations.remove(location)
    }
}

struct ExplorerSettingsView: View {
    @Binding var conflictPolicyRaw: String
    @Binding var confirmDelete: Bool
    let trash: ExplorerTrashManager

    @Environment(\.dismiss) private var dismiss
    @AppStorage("NikaidoExplorer.showMediaThumbnails")
    private var showMediaThumbnails = true

    var body: some View {
        NavigationView {
            Form {
                Section("Copiar y mover") {
                    Picker(
                        "Si ya existe",
                        selection: $conflictPolicyRaw
                    ) {
                        ForEach(ExplorerConflictPolicy.allCases) { policy in
                            Text(policy.title)
                                .tag(policy.rawValue)
                        }
                    }
                }

                Section("Seguridad") {
                    Toggle(
                        "Confirmar antes de eliminar",
                        isOn: $confirmDelete
                    )
                }

                NikaidoAppearanceSettingsSection()

                Section("Vista de archivos") {
                    Toggle(
                        "Mostrar portadas de fotos y videos",
                        isOn: $showMediaThumbnails
                    )

                    Text(
                        "Genera una miniatura para imágenes y videos en las vistas de lista y cuadrícula."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                NikaidoStorageSettingsSection(trash: trash)

                Section("Paneles") {
                    Text(
                        "El segundo panel se abre con el botón de panel dividido, "
                        + "arriba. Úsalo para copiar y mover entre dos carpetas, "
                        + "o arrastra un archivo por su asa al otro panel."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Raíz") {
                    Text(
                        "“Acceso directo a la raíz” significa la raíz de la "
                        + "ubicación que autorizaste. iOS no permite que una app "
                        + "normal navegue la raíz / del sistema ni los contenedores "
                        + "privados de otras apps."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Archivos comprimidos") {
                    LabeledContent("ZIP", value: "Extraer + crear")
                    LabeledContent("7z", value: "Extraer")
                    LabeledContent("RAR", value: "Extraer")
                }
            }
            .navigationTitle("Ajustes")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ExplorerExtractSheet: View {
    @Binding var password: String

    let isOperating: Bool
    let onCancel: () -> Void
    let onExtract: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Extraer archivo") {
                    Text(
                        "Se creará una carpeta con el nombre del archivo "
                        + "comprimido y se extraerá dentro."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Contraseña opcional") {
                    SecureField(
                        "Contraseña (RAR cifrado)",
                        text: $password
                    )
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Text(
                        "ZIP y 7z cifrados dependen de las capacidades de las "
                        + "librerías actuales. RAR admite contraseña."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if isOperating {
                    Section {
                        ProgressView("Extrayendo…")
                    }
                }
            }
            .navigationTitle("Extraer")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        onCancel()
                    }
                    .disabled(isOperating)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Extraer") {
                        onExtract()
                    }
                    .disabled(isOperating)
                }
            }
        }
    }
}

private struct ExplorerPreviewTarget: Identifiable {
    let id = UUID()
    let url: URL
}


/// Layout-only resizing: pane identities, selections and file operations stay intact.
private struct ExplorerResizableSplit<First: View, Second: View>: View {
    @Binding var fraction: CGFloat
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second
    @GestureState private var translation: CGSize = .zero
    @Environment(\.nikaidoAccent) private var accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let handleSize: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let horizontal = proxy.size.width >= 700
            let extent = horizontal ? proxy.size.width : proxy.size.height
            let available = max(0, extent - handleSize)
            let delta = horizontal ? translation.width : translation.height
            let base = clamped(fraction, available: available)
            let position = clamped(base + delta / max(available, 1), available: available)

            if horizontal {
                HStack(spacing: 0) {
                    first()
                        .transaction { $0.animation = nil }
                        .frame(width: available * position)
                        .clipped()
                    handle(horizontal: true, available: available, position: position)
                    second()
                        .transaction { $0.animation = nil }
                        .frame(width: available * (1 - position))
                        .clipped()
                }
            } else {
                VStack(spacing: 0) {
                    first()
                        .transaction { $0.animation = nil }
                        .frame(height: available * position)
                        .clipped()
                    handle(horizontal: false, available: available, position: position)
                    second()
                        .transaction { $0.animation = nil }
                        .frame(height: available * (1 - position))
                        .clipped()
                }
            }
        }
        .coordinateSpace(name: "explorerSplit")
    }

    private func clamped(_ value: CGFloat, available: CGFloat) -> CGFloat {
        // Keep both panels usable, including short layouts with the keyboard open.
        let minimum = min(0.5, max(0.2, 96 / max(available, 1)))
        return min(1 - minimum, max(minimum, value))
    }

    private func handle(horizontal: Bool, available: CGFloat, position: CGFloat) -> some View {
        Color.clear
            .frame(width: horizontal ? handleSize : nil, height: horizontal ? nil : handleSize)
            .overlay {
                // Only the small central control captures touches; its invisible
                // 44-point target remains comfortable without a thick separator.
                ZStack {
                    Color.clear
                    Capsule()
                        .fill(accent.opacity(0.65))
                        .frame(width: horizontal ? 1.5 : 48, height: horizontal ? 48 : 1.5)
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                }
                .frame(width: horizontal ? 44 : 64, height: horizontal ? 64 : 44)
                .contentShape(Rectangle())
                .gesture(resizeGesture(horizontal: horizontal, available: available))
                .onTapGesture(count: 2, perform: resetSize)
            }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tamaño de los paneles")
        .accessibilityValue("\(Int((position * 100).rounded())) por ciento para el panel \(horizontal ? "izquierdo" : "superior")")
        .accessibilityHint("Arrastra para ajustar. Toca dos veces para repartir el espacio por igual.")
        .accessibilityAdjustableAction { direction in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                switch direction {
                case .increment: fraction = clamped(fraction + 0.05, available: available)
                case .decrement: fraction = clamped(fraction - 0.05, available: available)
                @unknown default: break
                }
            }
        }
        .accessibilityAction(named: Text("Restablecer mitad y mitad")) { resetSize() }
    }

    private func resetSize() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            fraction = 0.5
        }
    }

    private func resizeGesture(horizontal: Bool, available: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("explorerSplit"))
            .updating($translation) { value, state, transaction in
                // Track the finger directly. Do not queue implicit list animations
                // or interpolate through stale sizes on every gesture sample.
                transaction.animation = nil
                state = value.translation
            }
            .onEnded { value in
                let delta = horizontal ? value.translation.width : value.translation.height
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    fraction = clamped(clamped(fraction, available: available) + delta / max(available, 1), available: available)
                }
            }
    }
}
