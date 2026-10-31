import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AVKit

private actor PrivateVaultEntryThumbnailGate {
    static let images = PrivateVaultEntryThumbnailGate(limit: 3)
    static let videos = PrivateVaultEntryThumbnailGate(limit: 1)

    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        permits = max(1, limit)
    }

    func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            permits += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

struct PrivateVaultView: View {
    @EnvironmentObject private var vault: PrivateVaultSession

    let onHome: () -> Void

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var currentFolderID: UUID?
    @State private var selectionMode = false
    @State private var selectedVaultIDs: Set<UUID> = []
    @StateObject private var vaultDrag = PrivateVaultDragState()
    @State private var pendingVaultDrag: PrivateVaultDrop?
    @State private var showBatchMovePicker = false
    @State private var showBatchDeleteConfirmation = false
    @State private var showImporter = false
    @State private var showBackupImportPicker = false
    @State private var showBackupExportPicker = false
    @State private var showZIPBackupConfirmation = false
    @State private var pcBridgeOperation: TakopiPCBridgeView.Operation?
    @State private var backupExportURL: URL?
    @State private var pendingBackupImportURL: URL?
    @State private var showBackupRestorePrompt = false
    @State private var backupRestorePassword = ""
    @State private var backupBusy = false
    @State private var backupNotice: String?
    @State private var showPhotoPicker = false
    @State private var offerDeletePhotos = false
    @StateObject private var photoImport = NikaidoPhotoImportCoordinator()
    @State private var showLANReceiver = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var selectedEntry: PrivateVaultEntry?
    @State private var selectedSecZip: PrivateVaultEntry?
    @State private var selectedSecFolder: PrivateVaultEntry?
    @State private var entryToDelete: PrivateVaultEntry?
    @State private var entryToRename: PrivateVaultEntry?
    @State private var entryToMove: PrivateVaultEntry?
    @State private var renameText = ""
    @State private var showDiagnostics = false
    @State private var showDiscardPendingConfirmation = false
    @State private var vaultSearch = ""
    @State private var exportURL: URL?
    @State private var showExporter = false
    @State private var isPreparingExport = false
    @State private var exportError: String?
    @State private var explorerNotice: String?
    @Environment(\.nikaidoAccent) private var nikaidoAccent
    @State private var unlockMethod: NikaidoUnlockMethod? = NikaidoUnlockPreference.method
    @State private var pendingMethodPassword: String?
    @State private var showUnlockMethodChoice = false
    @State private var isBiometricBusy = false
    @State private var biometricAutoAttempted = false
    @State private var methodNotice: String?
    @AppStorage("NikaidoVault.requireFileAuth.v1") private var requireFileAuth = true
    @State private var pendingProtectedAction: (() -> Void)?
    @State private var showFilePasswordPrompt = false
    @State private var filePasswordText = ""
    @State private var filePasswordError: String?
    @State private var isVerifyingFilePassword = false
    @State private var thumbnailsRevealed = false
    @State private var postOfferAction: (() -> Void)?
    @State private var showPasswordPanel = false

    private var visibleChildren: [PrivateVaultEntry] {
        let children = vault.children(of: currentFolderID)

        guard !vaultSearch.isEmpty else { return children }

        return children.filter { entry in
            entry.name.localizedCaseInsensitiveContains(vaultSearch)
        }
    }

    var body: some View {
        Group {
            if vault.isUnlocked {
                browser
            } else {
                unlockScreen
            }
        }
        .sheet(isPresented: $showImporter) {
            MultiFilePicker { urls in
                Task {
                    await vault.importFiles(
                        urls: urls,
                        parentID: currentFolderID
                    )
                }
            }
        }
        .confirmationDialog(
            "Exportación cifrada de Takopi Vault",
            isPresented: $showZIPBackupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Enviar directo a Windows (recomendado)") {
                pcBridgeOperation = .backup
            }
            Button("Crear ZIP dentro del iPhone") {
                exportVaultBackup()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("El ZIP de Archivos/iCloud necesita espacio temporal extra y puede requerir hasta dos copias. Para respaldar una bóveda grande en la PC sin duplicarla aquí, usa la transferencia directa.")
        }
        .sheet(item: $pcBridgeOperation) { operation in
            TakopiPCBridgeView(operation: operation).environmentObject(vault)
        }
        .sheet(isPresented: $showBackupImportPicker, onDismiss: {
            if pendingBackupImportURL != nil { showBackupRestorePrompt = true }
        }) {
            TakopiVaultBackupImportPicker(
                onPick: { url in
                    pendingBackupImportURL = url
                    showBackupImportPicker = false
                },
                onCancel: { showBackupImportPicker = false }
            )
        }
        .sheet(isPresented: $showBackupExportPicker, onDismiss: {
            TakopiVaultBackup.removeTemporaryBackup(backupExportURL)
            backupExportURL = nil
        }) {
            if let backupExportURL {
                TakopiVaultBackupExportPicker(archiveURL: backupExportURL) {
                    showBackupExportPicker = false
                }
            }
        }
        .alert(
            "Importar respaldo cifrado",
            isPresented: $showBackupRestorePrompt
        ) {
            SecureField("Contraseña del respaldo", text: $backupRestorePassword)
                .textContentType(.password)
            Button(
                vault.hasVault ? "Reemplazar bóveda actual" : "Restaurar bóveda",
                role: vault.hasVault ? .destructive : nil
            ) {
                restoreVaultBackup()
            }
            Button("Cancelar", role: .cancel) {
                releaseImportedBackup()
            }
        } message: {
            Text(vault.hasVault
                ? "La copia sustituirá TODA la bóveda actual. Valida primero su contraseña e integridad; después se guardará la bóveda nueva. No borres tu respaldo original."
                : "Se verificará la contraseña e integridad antes de restaurar la bóveda y sus archivos cifrados.")
        }
        .alert("Respaldo de Takopi Vault", isPresented: Binding(
            get: { backupNotice != nil },
            set: { if !$0 { backupNotice = nil } }
        )) {
            Button("Entendido", role: .cancel) { backupNotice = nil }
        } message: {
            Text(backupNotice ?? "")
        }
        .sheet(isPresented: $showPhotoPicker) {
            NikaidoPhotoPicker { picked, warning in
                photoImport.importPicked(
                    picked, vault: vault, parentID: currentFolderID,
                    requestDelete: offerDeletePhotos, pickerError: warning
                )
            }
        }
        .confirmationDialog(
            "¿Eliminar originales del carrete?",
            isPresented: $photoImport.deleteConfirmation
        ) {
            Button("Eliminar originales de Fotos", role: .destructive) {
                photoImport.deleteVerifiedOriginals()
            }
            Button("Conservar originales", role: .cancel) {}
        } message: {
            Text("La copia cifrada ya está en la bóveda. iOS pedirá confirmar el borrado de Fotos; los originales se pueden recuperar desde Eliminado recientemente.")
        }
        .alert("Importación del carrete", isPresented: Binding(
            get: { photoImport.notice != nil },
            set: { if !$0 { photoImport.notice = nil } }
        )) {
            Button("Entendido") { photoImport.notice = nil }
        } message: {
            Text(photoImport.notice ?? "")
        }
        .sheet(isPresented: $showLANReceiver) {
            LANReceiveView(
                vault: vault,
                parentID: currentFolderID
            )
        }
        .sheet(item: $selectedEntry) { entry in
            PrivateVaultMediaViewer(entry: entry)
                .environmentObject(vault)
        }
        .sheet(item: $selectedSecZip) { entry in
            StoredSecZipViewer(entry: entry)
                .environmentObject(vault)
        }
        .sheet(item: $selectedSecFolder) { folder in
            StoredSecFolderViewer(
                privateVault: vault,
                folder: folder
            )
        }
        .sheet(isPresented: $showDiagnostics) {
            NikaidoVaultDiagnosticsView()
                .environmentObject(vault)
        }
        .sheet(item: $entryToMove) { entry in
            NikaidoMoveDestinationView(entry: entry)
                .environmentObject(vault)
        }
        .sheet(isPresented: $showBatchMovePicker) {
            PrivateVaultBatchDestinationPicker(movingIDs: selectedVaultIDs) { folderID in
                moveSelectedVaultEntries(selectedVaultIDs, to: folderID)
            }
            .environmentObject(vault)
        }
        .confirmationDialog(
            "Mover archivos cifrados",
            isPresented: Binding(
                get: { pendingVaultDrag != nil },
                set: { if !$0 { pendingVaultDrag = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Mover a carpeta") {
                if let pendingVaultDrag {
                    moveSelectedVaultEntries(pendingVaultDrag.ids, to: pendingVaultDrag.folderID)
                }
                pendingVaultDrag = nil
            }
            Button("Cancelar", role: .cancel) { pendingVaultDrag = nil }
        } message: {
            Text("Se moverán dentro de Takopi Vault sin descifrar los archivos.")
        }
        .confirmationDialog("Eliminar seleccionados",
            isPresented: $showBatchDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Eliminar \(selectedVaultIDs.count) elementos", role: .destructive) {
                let items = vault.entries.filter { selectedVaultIDs.contains($0.id) }
                for entry in items { vault.delete(entry) }
                selectedVaultIDs.removeAll()
                selectionMode = false
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Las carpetas seleccionadas también eliminarán su contenido.")
        }
        .sheet(isPresented: $showExporter, onDismiss: {
            vault.releaseTemporaryPlaintext(exportURL)
            exportURL = nil
        }) {
            if let exportURL {
                NikaidoVaultExportPicker(url: exportURL) {
                    showExporter = false
                }
            }
        }
        .onReceive(vault.$isUnlocked) { unlocked in
            if !unlocked {
                selectedVaultIDs.removeAll()
                selectionMode = false
                pendingVaultDrag = nil
                vaultDrag.cancel()
                thumbnailsRevealed = false
                pendingProtectedAction = nil
                showFilePasswordPrompt = false
                filePasswordText = ""
                NikaidoFileAuth.reset()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didEnterBackgroundNotification
        )) { _ in
            selectedVaultIDs.removeAll()
            selectionMode = false
            pendingVaultDrag = nil
            vaultDrag.cancel()
            selectedEntry = nil
            selectedSecZip = nil
            selectedSecFolder = nil
            password = ""
            confirmPassword = ""
            backupRestorePassword = ""
            newFolderName = ""
            showImporter = false
            showNewFolder = false
            pendingMethodPassword = nil
            showUnlockMethodChoice = false
            pendingProtectedAction = nil
            postOfferAction = nil
            showFilePasswordPrompt = false
            filePasswordText = ""
            thumbnailsRevealed = false
            NikaidoFileAuth.reset()
            biometricAutoAttempted = false

            // If a plaintext export temp exists, release it before clearing the
            // URL. This also covers the short Nikaido Link background-grace
            // path where the vault itself may intentionally remain unlocked.
            vault.releaseTemporaryPlaintext(exportURL)
            showExporter = false
            exportURL = nil
            isPreparingExport = false

            if !LANTransferActivity.shared.isActive {
                showLANReceiver = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .nikaidoLinkGraceExpired
        )) { _ in
            showLANReceiver = false
        }
        .alert(
            "¿Cómo quieres desbloquear Takopi Vault?",
            isPresented: $showUnlockMethodChoice
        ) {
            Button("Face ID") {
                chooseFaceID()
            }

            Button("Contraseña") {
                choosePassword()
            }
        } message: {
            Text("Con Face ID, Takopi guarda tu contraseña cifrada y oculta en el Llavero de este iPhone, protegida por Face ID, y la usa por ti. Puedes cambiarlo desde el menú de la bóveda.")
        }
        .alert(
            "Takopi Vault",
            isPresented: Binding(
                get: { methodNotice != nil },
                set: { if !$0 { methodNotice = nil } }
            )
        ) {
            Button("Entendido", role: .cancel) {
                methodNotice = nil
            }
        } message: {
            Text(methodNotice ?? "")
        }
        .alert(
            "Confirma tu identidad",
            isPresented: $showFilePasswordPrompt
        ) {
            SecureField("Contraseña de Takopi Vault", text: $filePasswordText)

            Button("Abrir") {
                submitFilePassword()
            }

            Button("Cancelar", role: .cancel) {
                pendingProtectedAction = nil
                filePasswordText = ""
                filePasswordError = nil
            }
        } message: {
            Text(
                filePasswordError
                ?? "Escribe la contraseña de Takopi Vault para abrir este archivo."
            )
        }
        .alert(
            "Guardado en Takopi Explorer",
            isPresented: Binding(
                get: { explorerNotice != nil },
                set: { if !$0 { explorerNotice = nil } }
            )
        ) {
            Button("Entendido", role: .cancel) {
                explorerNotice = nil
            }
        } message: {
            Text(explorerNotice ?? "")
        }
        .alert("Nueva carpeta", isPresented: $showNewFolder) {
            TextField("Nombre", text: $newFolderName)

            Button("Cancelar", role: .cancel) {
                newFolderName = ""
            }

            Button("Crear") {
                vault.createFolder(
                    name: newFolderName,
                    parentID: currentFolderID
                )
                newFolderName = ""
            }
        }
        .alert(
            "Renombrar",
            isPresented: Binding(
                get: { entryToRename != nil },
                set: { if !$0 { entryToRename = nil } }
            ),
            presenting: entryToRename
        ) { entry in
            TextField("Nombre", text: $renameText)

            Button("Cancelar", role: .cancel) {
                renameText = ""
                entryToRename = nil
            }

            Button("Guardar") {
                vault.rename(entry, to: renameText)
                renameText = ""
                entryToRename = nil
            }
        }
        .alert(
            "Eliminar transferencias pendientes",
            isPresented: $showDiscardPendingConfirmation
        ) {
            Button("Cancelar", role: .cancel) {}

            Button("Eliminar pendientes", role: .destructive) {
                vault.discardAllPendingTransfers()
            }
        } message: {
            Text(
                "Se borrará únicamente el progreso incompleto de Nikaido Link. "
                + "Las colecciones ya guardadas no se tocarán."
            )
        }
        .alert(
            "No se pudo exportar",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("Entendido", role: .cancel) {
                exportError = nil
            }
        } message: {
            Text(exportError ?? "Error desconocido")
        }
        .alert(
            "Eliminar",
            isPresented: Binding(
                get: { entryToDelete != nil },
                set: { if !$0 { entryToDelete = nil } }
            ),
            presenting: entryToDelete
        ) { entry in
            Button("Cancelar", role: .cancel) {
                entryToDelete = nil
            }

            Button("Eliminar", role: .destructive) {
                vault.delete(entry)
                entryToDelete = nil
            }
        } message: { entry in
            Text(
                entry.kind == .folder
                ? "Se eliminará la carpeta y todo lo que contiene."
                : "Se eliminará \(entry.name) de la bóveda."
            )
        }
    }

    /// La contraseña se muestra si no hay Face ID, si se está creando la
    /// bóveda o si el usuario eligió explícitamente la opción de contraseña.
    private var passwordPanelVisible: Bool {
        !vault.hasVault || unlockMethod != .faceID || showPasswordPanel
    }

    private func unlockOptionCard(
        symbol: String,
        title: String,
        subtitle: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                NikaidoFeatureMark(
                    systemName: symbol,
                    tint: isEnabled ? nikaidoAccent : .secondary,
                    size: 46
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .opacity(isEnabled ? 1 : 0.6)
        }
        .buttonStyle(NikaidoPressCardStyle())
        .disabled(!isEnabled)
    }

    private var unlockOptions: some View {
        VStack(spacing: 10) {
            unlockOptionCard(
                symbol: "faceid",
                title: "Face ID",
                subtitle: unlockMethod == .faceID
                    ? "Entra con tu rostro"
                    : "Se activa después de entrar una vez con tu contraseña",
                isEnabled: unlockMethod == .faceID && !isBiometricBusy && !vault.isBusy
            ) {
                attemptBiometricUnlock()
            }

            unlockOptionCard(
                symbol: "key.fill",
                title: "Contraseña",
                subtitle: "Escribe la contraseña de tu bóveda",
                isEnabled: !vault.isBusy
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showPasswordPanel.toggle()
                }
            }
        }
    }

    private var passwordPanel: some View {
        VStack(spacing: 12) {
            SecureField("Contraseña", text: $password)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .nikaidoField()

            if !vault.hasVault {
                SecureField("Repite la contraseña", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .nikaidoField()
            }

            Button(vault.hasVault ? "Desbloquear" : "Crear Takopi Vault") {
                submitUnlockPassword()
            }
            .buttonStyle(NikaidoPrimaryButtonStyle())
            .padding(.horizontal, -28)
            .disabled(
                password.isEmpty ||
                (!vault.hasVault && confirmPassword.isEmpty) ||
                vault.isBusy
            )
        }
    }

    private func submitUnlockPassword() {
        Task {
            let typedPassword = password

            if vault.hasVault {
                await vault.unlock(password: typedPassword)

                if vault.isUnlocked {
                    password = ""
                    showPasswordPanel = false
                    offerUnlockMethodIfNeeded(with: typedPassword)
                }
            } else {
                guard password == confirmPassword else {
                    vault.errorMessage = "Las contraseñas no coinciden."
                    return
                }

                await vault.create(password: typedPassword)

                if vault.isUnlocked {
                    password = ""
                    confirmPassword = ""
                    offerUnlockMethodIfNeeded(with: typedPassword)
                }
            }
        }
    }

    private var unlockScreen: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Button {
                        onHome()
                    } label: {
                        Label("Inicio", systemImage: "chevron.left")
                    }

                    Spacer()
                }

                NikaidoVaultMark(tint: nikaidoAccent, size: 92)
                    .shadow(
                        color: nikaidoAccent.opacity(0.35),
                        radius: 14,
                        y: 8
                    )
                    .padding(.top, 8)

                Text(vault.hasVault ? "Takopi Vault" : "Crear Takopi Vault")
                    .font(.title2.bold())

                Text(
                    vault.hasVault
                    ? "Elige cómo quieres entrar. Tus archivos siguen cifrados dentro de la app."
                    : "Crea un espacio cifrado independiente de Archivos y de las carpetas .sec."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

                if vault.hasVault {
                    unlockOptions
                }

                Button {
                    showBackupImportPicker = true
                } label: {
                    Label("Restaurar copia cifrada desde Archivos",
                          systemImage: "externaldrive.badge.plus")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .disabled(backupBusy)

                Button {
                    pcBridgeOperation = .restore
                } label: {
                    Label("Restaurar Vault desde Windows", systemImage: "desktopcomputer")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .disabled(backupBusy || vault.isBusy)

                if passwordPanelVisible {
                    passwordPanel
                }

                if vault.isBusy || isBiometricBusy {
                    ProgressView()
                }

                if let error = vault.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }

                Text("AES-256-GCM • archivos por bloques • sin nube")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [
                    nikaidoAccent.opacity(0.22),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
    }

    private func canOfferFaceID() -> Bool {
        guard
            unlockMethod != .faceID,
            NikaidoUnlockPreference.biometricsAvailable
        else {
            return false
        }

        return !(unlockMethod == .password && NikaidoUnlockPreference.faceIDOfferDeclined)
    }

    private func offerUnlockMethodIfNeeded(with typedPassword: String) {
        guard unlockMethod != .faceID else { return }

        guard NikaidoUnlockPreference.biometricsAvailable else {
            if unlockMethod == nil {
                NikaidoUnlockPreference.method = .password
                unlockMethod = .password
            }
            return
        }

        guard canOfferFaceID() else { return }

        pendingMethodPassword = typedPassword
        showUnlockMethodChoice = true
    }

    private func finishOffer() {
        let action = postOfferAction
        postOfferAction = nil
        action?()
    }

    private func chooseFaceID() {
        guard let typedPassword = pendingMethodPassword else {
            finishOffer()
            return
        }

        pendingMethodPassword = nil

        Task { @MainActor in
            let result = await NikaidoUnlockPreference.enableBiometric(
                password: typedPassword
            )

            if case .enabled = result {
                NikaidoUnlockPreference.method = .faceID
                NikaidoUnlockPreference.faceIDOfferDeclined = false
                unlockMethod = .faceID
                biometricAutoAttempted = true
            } else {
                NikaidoUnlockPreference.method = .password
                unlockMethod = .password

                if case .storeFailed = result {
                    NikaidoUnlockPreference.faceIDOfferDeclined = true
                }

                methodNotice = result.message
            }

            finishOffer()
        }
    }

    private func choosePassword() {
        pendingMethodPassword = nil
        NikaidoUnlockPreference.disableBiometric()
        NikaidoUnlockPreference.method = .password
        NikaidoUnlockPreference.faceIDOfferDeclined = true
        unlockMethod = .password
        finishOffer()
    }

    private func attemptBiometricUnlock() {
        guard
            unlockMethod == .faceID,
            vault.hasVault,
            !vault.isUnlocked,
            !isBiometricBusy,
            !vault.isBusy
        else {
            return
        }

        isBiometricBusy = true
        biometricAutoAttempted = true

        Task {
            let result = await NikaidoUnlockPreference.loadPassword(
                reason: "Desbloquear Takopi Vault"
            )

            switch result {
            case .success(let storedPassword):
                await vault.unlock(password: storedPassword)
            case .cancelled, .fallback:
                break
            case .invalidated:
                NikaidoUnlockPreference.disableBiometric()
                unlockMethod = nil
                methodNotice = "Face ID cambió o ya no está disponible. Escribe tu contraseña y te pregunto de nuevo cómo desbloquear."
            case .failed(let message):
                methodNotice = message
            }

            isBiometricBusy = false
        }
    }

    private var browser: some View {
        VStack(spacing: 0) {
            browserHeader
            Divider()

            if selectionMode {
                vaultSelectionToolbar
                Divider()
            }

            if visibleChildren.isEmpty {
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)

                    Text(vaultSearch.isEmpty ? "Carpeta vacía" : "Sin resultados")
                        .font(.headline)

                    Text(
                        vaultSearch.isEmpty
                        ? "Importa archivos o crea una carpeta."
                        : "No hay elementos que coincidan con la búsqueda."
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 120), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        ForEach(visibleChildren) { entry in
                            entryCard(entry)
                        }
                    }
                    .padding(10)
                }
                .vaultMoveProbe(vaultDrag, key: "background|vault", folderID: currentFolderID)
            }

            if vault.isBusy || isPreparingExport || photoImport.isImporting {
                ProgressView(
                    isPreparingExport
                    ? "Preparando exportación cifrada…"
                    : "Cifrando o importando…"
                )
                .padding()
            }

            if let error = vault.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }
        }
        .overlay {
            PrivateVaultDragPreview(drag: vaultDrag, pointer: vaultDrag.pointer)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            browserActions
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
        }
        .searchable(
            text: $vaultSearch,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Buscar en Takopi Vault"
        )
    }

    private var browserHeader: some View {
        VStack(spacing: 10) {
            // Keep the folder title OUTSIDE the actions so it never wraps
            // one word into several lines on a narrow iPhone.
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(vault.folderName(currentFolderID))
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.8)

                    Text("\(visibleChildren.count) elementos")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 3)
                Button(selectionMode ? "Listo" : "Seleccionar") {
                    selectionMode.toggle()
                    if !selectionMode { selectedVaultIDs.removeAll() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(nikaidoAccent)
                .accessibilityLabel(selectionMode ? "Terminar selección" : "Seleccionar archivos de la bóveda")
            }
            .vaultMoveProbe(
                vaultDrag,
                key: "parent|vault",
                folderID: currentFolderID == nil ? nil : vault.parent(of: currentFolderID)
            )


            if vault.pendingTransferCount > 0 {
                Text("\(vault.pendingTransferCount) transferencia(s) de Nikaido Link pueden reanudarse.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var vaultSelectionToolbar: some View {
        HStack(spacing: 7) {
            TakopiSelectionCount(count: selectedVaultIDs.count)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                let allIDs = Set(visibleChildren.map(\.id))
                if !allIDs.isEmpty && allIDs.isSubset(of: selectedVaultIDs) {
                    selectedVaultIDs.subtract(allIDs)
                } else {
                    selectedVaultIDs.formUnion(allIDs)
                }
                NikaidoTheme.haptic(.light)
            } label: {
                TakopiSelectionActionIcon(
                    systemName: !visibleChildren.isEmpty &&
                        visibleChildren.allSatisfy { selectedVaultIDs.contains($0.id) }
                        ? "checkmark.circle.fill" : "checkmark.circle"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                !visibleChildren.isEmpty &&
                    visibleChildren.allSatisfy { selectedVaultIDs.contains($0.id) }
                    ? "Deseleccionar todos" : "Seleccionar todos"
            )

            Button {
                showBatchMovePicker = true
            } label: {
                TakopiSelectionActionIcon(systemName: "folder.fill", prominent: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mover seleccionados")
            .disabled(selectedVaultIDs.isEmpty)

            Menu {
                if selectedVaultIDs.count == 1,
                   let only = vault.entries.first(where: { selectedVaultIDs.contains($0.id) }) {
                    Button {
                        renameText = only.name
                        entryToRename = only
                    } label: {
                        Label("Renombrar", systemImage: "pencil")
                    }
                }

                Button {
                    showBatchMovePicker = true
                } label: {
                    Label("Mover a carpeta", systemImage: "folder.badge.plus")
                }

                Button(role: .destructive) {
                    showBatchDeleteConfirmation = true
                } label: {
                    Label("Eliminar", systemImage: "trash")
                }
            } label: {
                TakopiSelectionActionIcon(systemName: "ellipsis")
            }
            .accessibilityLabel("Más acciones para seleccionados")
            .disabled(selectedVaultIDs.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func moveSelectedVaultEntries(_ ids: Set<UUID>, to folderID: UUID?) {
        do {
            try vault.moveEntries(ids, to: folderID)
            selectedVaultIDs.subtract(ids)
            if selectedVaultIDs.isEmpty { selectionMode = false }
            NikaidoTheme.haptic(.light)
        } catch {
            explorerNotice = error.localizedDescription
        }
    }

    private func vaultDragCallbacks(for entry: PrivateVaultEntry) -> ExplorerDragCallbacks {
        ExplorerDragCallbacks(
            began: { point in
                let ids: Set<UUID> = selectedVaultIDs.contains(entry.id)
                    ? selectedVaultIDs : [entry.id]
                vaultDrag.begin(ids: ids, originFolderID: currentFolderID, at: point)
                NikaidoTheme.haptic(.medium)
            },
            moved: { point in vaultDrag.move(to: point) },
            ended: { point, completed in
                if completed {
                    pendingVaultDrag = vaultDrag.finish(at: point)
                } else {
                    vaultDrag.cancel()
                }
            }
        )
    }

    // Floating Liquid Glass actions stay reachable at the bottom of the vault.
    /// The backup contains only ciphertext; the user chooses local or iCloud.
    private func exportVaultBackup() {
        guard !backupBusy else { return }
        backupBusy = true
        Task {
            defer { backupBusy = false }
            do {
                backupExportURL = try await vault.exportEncryptedBackup()
                showBackupExportPicker = true
            } catch {
                backupNotice = error.localizedDescription
            }
        }
    }

    private func releaseImportedBackup() {
        if let url = pendingBackupImportURL {
            try? FileManager.default.removeItem(at: url)
        }
        pendingBackupImportURL = nil
        backupRestorePassword = ""
    }

    private func restoreVaultBackup() {
        guard let url = pendingBackupImportURL, !backupBusy else { return }
        let secret = backupRestorePassword
        backupRestorePassword = ""
        backupBusy = true
        Task {
            defer {
                backupBusy = false
                releaseImportedBackup()
            }
            do {
                try await vault.importEncryptedBackup(from: url, password: secret)
                unlockMethod = .password
                currentFolderID = nil
                backupNotice = "Se restauró la bóveda cifrada. Desbloquéala con la contraseña del respaldo. Face ID debe configurarse otra vez en este dispositivo."
            } catch {
                backupNotice = "No se importó la copia: " + error.localizedDescription
            }
        }
    }

    private var browserActions: some View {
        HStack(spacing: 2) {
            Button {
                vaultSearch = ""
                if currentFolderID == nil {
                    vault.lock()
                    onHome()
                } else {
                    currentFolderID = vault.parent(of: currentFolderID)
                    selectedVaultIDs.removeAll()
                }
            } label: {
                Image(systemName: currentFolderID == nil ? "house" : "chevron.left")
            }
            .buttonStyle(NikaidoGlassActionStyle())
            .accessibilityLabel(currentFolderID == nil ? "Cerrar bóveda" : "Volver a la carpeta anterior")

            Button {
                showNewFolder = true
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(NikaidoGlassActionStyle())
            .accessibilityLabel("Crear carpeta cifrada")

            Button {
                showLANReceiver = true
            } label: {
                Image(systemName: "wifi")
            }
            .buttonStyle(NikaidoGlassActionStyle())
            .accessibilityLabel("Recibir desde PC")

            Menu {
                Button {
                    offerDeletePhotos = false
                    showPhotoPicker = true
                } label: {
                    Label("Importar fotos y videos", systemImage: "photo.on.rectangle")
                }
                Button {
                    offerDeletePhotos = true
                    showPhotoPicker = true
                } label: {
                    Label("Importar y ofrecer borrar originales", systemImage: "photo.badge.plus")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Importar desde Archivos", systemImage: "folder")
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .disabled(photoImport.isImporting)
            .buttonStyle(NikaidoGlassActionStyle())
            .accessibilityLabel("Importar a la bóveda")
            .accessibilityHint("Elige entre archivos, fotos y videos del carrete")

            Menu {
                Section("Respaldo cifrado") {
                    Button {
                        pcBridgeOperation = .backup
                    } label: {
                        Label("Respaldo directo a Windows (sin ZIP)", systemImage: "desktopcomputer")
                    }
                    .disabled(backupBusy || vault.isBusy)
                    Button {
                        pcBridgeOperation = .restore
                    } label: {
                        Label("Restaurar desde Windows", systemImage: "externaldrive.badge.plus")
                    }
                    .disabled(backupBusy || vault.isBusy)
                    Button {
                        showZIPBackupConfirmation = true
                    } label: {
                        Label("Exportar ZIP a Archivos (requiere espacio)", systemImage: "externaldrive.badge.plus")
                    }
                    .disabled(backupBusy || vault.isBusy)
                    Button {
                        showBackupImportPicker = true
                    } label: {
                        Label("Importar copia completa cifrada", systemImage: "square.and.arrow.down")
                    }
                    .disabled(backupBusy || vault.isBusy)
                }

                Button {
                    vault.refreshOperationalStatus()
                    showDiagnostics = true
                } label: {
                    Label(
                        "Diagnóstico de Takopi Vault",
                        systemImage: "stethoscope"
                    )
                }

                Toggle(
                    isOn: Binding(
                        get: { requireFileAuth },
                        set: { newValue in
                            if newValue {
                                requireFileAuth = true
                            } else {
                                protectedOpen("Desactivar la protección de archivos") {
                                    requireFileAuth = false
                                }
                            }
                        }
                    )
                ) {
                    Label(
                        "Pedir identidad al abrir archivos",
                        systemImage: "lock.shield"
                    )
                }

                if requireFileAuth {
                    Button {
                        toggleThumbnailReveal()
                    } label: {
                        Label(
                            thumbnailsRevealed
                            ? "Ocultar miniaturas"
                            : "Mostrar miniaturas",
                            systemImage: thumbnailsRevealed
                            ? "eye.slash"
                            : "eye"
                        )
                    }
                }

                Button {
                    NikaidoUnlockPreference.disableBiometric()
                    NikaidoUnlockPreference.faceIDOfferDeclined = false
                    unlockMethod = nil
                    methodNotice = "La próxima vez que desbloquees con tu contraseña te voy a preguntar otra vez: Face ID o contraseña."
                } label: {
                    Label(
                        "Cambiar método de desbloqueo",
                        systemImage: "faceid"
                    )
                }

                if vault.pendingTransferCount > 0 {
                    Button(role: .destructive) {
                        showDiscardPendingConfirmation = true
                    } label: {
                        Label(
                            "Eliminar transferencias pendientes",
                            systemImage: "clock.badge.xmark"
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(NikaidoGlassActionStyle())
            .accessibilityLabel("Opciones de la bóveda")

            Button {
                vault.lock()
                currentFolderID = nil
            } label: {
                Image(systemName: "lock.fill")
            }
            .buttonStyle(NikaidoGlassActionStyle())
            .accessibilityLabel("Bloquear bóveda")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .modifier(NikaidoGlassCapsule())
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func entryCard(_ entry: PrivateVaultEntry) -> some View {
        Button {
            if selectionMode {
                if selectedVaultIDs.contains(entry.id) {
                    selectedVaultIDs.remove(entry.id)
                } else {
                    selectedVaultIDs.insert(entry.id)
                }
            } else if entry.isSecCollectionFolder {
                // The .sec viewer prompts for its own password or Face ID.
                selectedSecFolder = entry
            } else if entry.kind == .folder {
                vaultSearch = ""
                currentFolderID = entry.id
                selectedVaultIDs.removeAll()
            } else if entry.isImage || entry.isVideo {
                protectedOpen("Abrir \(entry.name)") {
                    selectedEntry = entry
                }
            } else if entry.fileExtension == "zip" {
                protectedOpen("Abrir \(entry.name)") {
                    selectedSecZip = entry
                }
            }
        } label: {
            VStack(spacing: 8) {
                if entry.isImage || entry.isVideo {
                    PrivateVaultEntryThumbnail(
                        vault: vault,
                        entry: entry,
                        revealed: thumbnailsRevealed || !requireFileAuth
                    )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(nikaidoAccent.opacity(0.07))

                        NikaidoFeatureMark(
                            systemName: icon(for: entry),
                            tint: entry.kind == .folder ? .orange : nikaidoAccent,
                            size: 64
                        )
                    }
                    .aspectRatio(1.25, contentMode: .fit)
                }

                Text(entry.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if entry.kind == .file {
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: entry.originalSize,
                            countStyle: .file
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(6)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if selectionMode {
                Image(systemName: selectedVaultIDs.contains(entry.id)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selectedVaultIDs.contains(entry.id)
                                     ? nikaidoAccent : Color.secondary)
                    .background(Circle().fill(.regularMaterial))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            // El asa permanece visible aun con varios elementos seleccionados.
            ExplorerDragHandle(callbacks: vaultDragCallbacks(for: entry))
                .background(.thinMaterial, in: Capsule())
                .padding(4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(nikaidoAccent, lineWidth:
                    vaultDrag.highlightedKey == "folder|\(entry.id.uuidString)" ? 2 : 0)
                .allowsHitTesting(false)
        )
        .vaultMoveFolderProbe(vaultDrag, entry: entry)
        .contextMenu {
            if entry.isSecCollectionFolder {
                Button {
                    // Same direct route as tapping the collection.
                    selectedSecFolder = entry
                } label: {
                    Label(
                        "Abrir galería .sec",
                        systemImage: "lock.square.stack.fill"
                    )
                }
            }

            if entry.kind == .file && entry.fileExtension == "zip" {
                Button {
                    protectedOpen("Abrir \(entry.name)") {
                        selectedSecZip = entry
                    }
                } label: {
                    Label("Abrir ZIP .sec", systemImage: "doc.zipper")
                }
            }

            if entry.kind == .file {
                Button {
                    protectedOpen("Exportar \(entry.name)") {
                        Task {
                            await prepareExport(entry)
                        }
                    }
                } label: {
                    Label(
                        "Exportar copia descifrada…",
                        systemImage: "square.and.arrow.up"
                    )
                }
            }

            if entry.kind == .file {
                Button {
                    protectedOpen("Guardar \(entry.name) sin cifrar") {
                        Task {
                            await saveToExplorer(entry)
                        }
                    }
                } label: {
                    Label(
                        "Guardar en Takopi Explorer",
                        systemImage: "square.and.arrow.down.on.square"
                    )
                }
            }

            Button {
                renameText = entry.name
                entryToRename = entry
            } label: {
                Label("Renombrar", systemImage: "pencil")
            }

            Button {
                entryToMove = entry
            } label: {
                Label(
                    "Mover…",
                    systemImage: "folder.badge.plus"
                )
            }

            Button(role: .destructive) {
                entryToDelete = entry
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }

    @MainActor
    private func prepareExport(_ entry: PrivateVaultEntry) async {
        guard !isPreparingExport else { return }

        isPreparingExport = true
        exportError = nil

        do {
            let url = try await vault.makeTemporaryDecryptedCopy(of: entry)

            guard vault.isUnlocked, !Task.isCancelled else {
                vault.releaseTemporaryPlaintext(url)
                isPreparingExport = false
                return
            }

            exportURL = url
            showExporter = true
        } catch {
            exportError = error.localizedDescription
        }

        isPreparingExport = false
    }

    /// Ejecuta `action` solo después de verificar la identidad del usuario con
    /// Face ID o, como alternativa, la contraseña de la bóveda. Cancelar o
    /// fallar nunca ejecuta la acción.
    private func protectedOpen(
        _ reason: String,
        _ action: @escaping () -> Void
    ) {
        guard requireFileAuth, !NikaidoFileAuth.isWithinGrace else {
            action()
            return
        }

        Task { @MainActor in
            // Sin Face ID guardado: se pide la contraseña de la bóveda.
            guard unlockMethod == .faceID else {
                promptForFilePassword(action, message: nil)
                return
            }

            // Con Face ID: Face ID libera la contraseña guardada en el
            // Llavero y se comprueba contra la clave real de la bóveda.
            let loaded = await NikaidoUnlockPreference.loadPassword(reason: reason)

            switch loaded {
            case .success(let storedPassword):
                if await vault.verifyPassword(storedPassword) {
                    NikaidoFileAuth.markAuthenticated()
                    action()
                } else {
                    NikaidoUnlockPreference.disableBiometric()
                    unlockMethod = nil
                    promptForFilePassword(
                        action,
                        message: "La contraseña guardada para Face ID ya no coincide. Escríbela otra vez."
                    )
                }
            case .cancelled:
                break
            case .fallback:
                promptForFilePassword(action, message: nil)
            case .invalidated:
                NikaidoUnlockPreference.disableBiometric()
                unlockMethod = nil
                promptForFilePassword(
                    action,
                    message: "Face ID cambió o ya no está disponible. Escribe tu contraseña."
                )
            case .failed(let message):
                promptForFilePassword(action, message: message)
            }
        }
    }

    private func promptForFilePassword(
        _ action: @escaping () -> Void,
        message: String?
    ) {
        pendingProtectedAction = action
        filePasswordText = ""
        filePasswordError = message
        showFilePasswordPrompt = true
    }

    private func submitFilePassword() {
        let typed = filePasswordText

        guard !typed.isEmpty, !isVerifyingFilePassword else { return }

        isVerifyingFilePassword = true

        Task { @MainActor in
            let verified = await vault.verifyPassword(typed)

            isVerifyingFilePassword = false
            filePasswordText = ""

            if verified {
                NikaidoFileAuth.markAuthenticated()
                filePasswordError = nil

                let action = pendingProtectedAction
                pendingProtectedAction = nil

                if canOfferFaceID() {
                    // Se ofrece guardar la contraseña para usar Face ID y,
                    // al decidir, se abre el archivo.
                    postOfferAction = action
                    pendingMethodPassword = typed
                    showUnlockMethodChoice = true
                } else {
                    action?()
                }
            } else {
                filePasswordError = "Contraseña incorrecta. Inténtalo de nuevo."
                showFilePasswordPrompt = true
            }
        }
    }

    private func toggleThumbnailReveal() {
        if thumbnailsRevealed {
            thumbnailsRevealed = false
            return
        }

        protectedOpen("Mostrar miniaturas de Takopi Vault") {
            thumbnailsRevealed = true
        }
    }

    /// Descifra una copia y la guarda en la carpeta local de Takopi Explorer.
    @MainActor
    private func saveToExplorer(_ entry: PrivateVaultEntry) async {
        guard !isPreparingExport else { return }

        isPreparingExport = true
        defer { isPreparingExport = false }

        do {
            let temporary = try await vault.makeTemporaryDecryptedCopy(of: entry)
            defer { vault.releaseTemporaryPlaintext(temporary) }

            guard
                let documents = FileManager.default.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                ).first
            else {
                throw PrivateVaultError.notAFile
            }

            let folder = documents.appendingPathComponent(
                "Desde la bóveda",
                isDirectory: true
            )

            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )

            let stem = (entry.name as NSString).deletingPathExtension
            let ext = (entry.name as NSString).pathExtension

            var target = folder.appendingPathComponent(entry.name)
            var counter = 2

            while FileManager.default.fileExists(atPath: target.path) {
                let candidate = ext.isEmpty
                    ? "\(stem) \(counter)"
                    : "\(stem) \(counter).\(ext)"
                target = folder.appendingPathComponent(candidate)
                counter += 1
            }

            try FileManager.default.copyItem(at: temporary, to: target)

            explorerNotice = "Quedó en “Desde la bóveda” como \(target.lastPathComponent). Esta copia ya no está cifrada."
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func icon(for entry: PrivateVaultEntry) -> String {
        if entry.isSecCollectionFolder {
            return "lock.square.stack.fill"
        }

        if entry.kind == .folder {
            return "folder.fill"
        }

        if entry.isImage {
            return "photo.fill"
        }

        if entry.isVideo {
            return "film.fill"
        }

        switch entry.fileExtension {
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "7z", "rar":
            return "archivebox.fill"
        case "mp3", "m4a", "wav", "flac", "aac":
            return "waveform"
        default:
            return "doc.fill"
        }
    }
}



struct PrivateVaultEntryThumbnail: View {
    @ObservedObject var vault: PrivateVaultSession
    let entry: PrivateVaultEntry
    let revealed: Bool

    @State private var image: UIImage?
    @State private var isLoading = false

    private var placeholderSymbol: String {
        if !revealed { return "lock.fill" }
        return entry.isVideo ? "film.fill" : "photo.fill"
    }

    /// Contenido dibujado encima de un contenedor de tamaño fijo. Así la
    /// imagen (que se escala para llenar) nunca modifica el tamaño de la celda
    /// ni invade a las vecinas, sea vertical, horizontal o cuadrada.
    private var thumbnailContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            }

            if isLoading && image == nil {
                ProgressView()
                    .tint(.white)
                    .padding(8)
                    .background(.black.opacity(0.40))
                    .clipShape(Circle())
            }

            if entry.isVideo && revealed {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: image == nil ? 30 : 36))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
                    .opacity(isLoading && image == nil ? 0.45 : 0.95)
            }
        }
    }

    var body: some View {
        Color.clear
            .aspectRatio(1.25, contentMode: .fit)
            .overlay {
                thumbnailContent
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        .task(id: "\(entry.id.uuidString)-\(revealed)") {
            guard revealed else {
                image = nil
                return
            }

            isLoading = true
            defer { isLoading = false }

            if
                let cached = await vault.cachedThumbnailData(for: entry),
                let decoded = UIImage(data: cached)
            {
                image = decoded
                return
            }

            if entry.isImage {
                await PrivateVaultEntryThumbnailGate.images.acquire()

                if Task.isCancelled {
                    await PrivateVaultEntryThumbnailGate.images.release()
                    return
                }

                do {
                    let data = try await vault.decryptFileDataAsync(
                        entry,
                        maxPlaintextBytes: 64 * 1024 * 1024
                    )

                    if
                        !Task.isCancelled,
                        let thumbnail = ImageDownsampler.thumbnail(from: data)
                    {
                        image = thumbnail

                        if let jpeg = thumbnail.jpegData(
                            compressionQuality: 0.82
                        ) {
                            await vault.storeCachedThumbnailData(
                                jpeg,
                                for: entry
                            )
                        }
                    }
                } catch {
                    image = nil
                }

                await PrivateVaultEntryThumbnailGate.images.release()
                return
            }

            guard entry.isVideo else { return }

            await PrivateVaultEntryThumbnailGate.videos.acquire()

            if Task.isCancelled {
                await PrivateVaultEntryThumbnailGate.videos.release()
                return
            }

            do {
                let descriptor = try await vault.prepareRandomAccess(
                    for: entry
                )
                let jpeg = try await PrivateVaultVideoThumbnailGenerator
                    .generateJPEG(
                        descriptor: descriptor,
                        filename: entry.name
                    )

                if !Task.isCancelled, let decoded = UIImage(data: jpeg) {
                    image = decoded
                    await vault.storeCachedThumbnailData(
                        jpeg,
                        for: entry
                    )
                }
            } catch {
                image = nil
            }

            await PrivateVaultEntryThumbnailGate.videos.release()
        }
    }
}

struct NikaidoMoveDestinationView: View {
    @EnvironmentObject private var vault: PrivateVaultSession
    @Environment(\.dismiss) private var dismiss

    let entry: PrivateVaultEntry

    var body: some View {
        NavigationView {
            List {
                Section("Destino") {
                    Button {
                        vault.move(entry, to: nil)
                        dismiss()
                    } label: {
                        Label(
                            "Raíz de Takopi Vault",
                            systemImage: "externaldrive.fill"
                        )
                    }
                    .disabled(entry.parentID == nil)

                    ForEach(vault.moveDestinations(excluding: entry)) { folder in
                        Button {
                            vault.move(entry, to: folder.id)
                            dismiss()
                        } label: {
                            HStack {
                                Label(
                                    folder.name,
                                    systemImage: folder.isSecCollectionFolder
                                    ? "lock.square.stack.fill"
                                    : "folder.fill"
                                )

                                Spacer()

                                if entry.parentID == folder.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(entry.parentID == folder.id)
                    }
                }

                Section {
                    Text(
                        "Mover solo actualiza el índice cifrado. Los blobs .ssvb "
                        + "no se recifran ni se copian."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Mover \(entry.name)")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct NikaidoVaultDiagnosticsView: View {
    @EnvironmentObject private var vault: PrivateVaultSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if let report = vault.healthReport {
                    Section("Estado") {
                        Label(
                            report.isHealthy
                            ? "Metadata y blobs principales coherentes"
                            : "Revisión recomendada",
                            systemImage: report.isHealthy
                            ? "checkmark.shield.fill"
                            : "exclamationmark.triangle.fill"
                        )

                        LabeledContent(
                            "Archivos indexados",
                            value: "\(report.indexedFiles)"
                        )
                        LabeledContent(
                            "Carpetas indexadas",
                            value: "\(report.indexedFolders)"
                        )
                        LabeledContent(
                            "Blobs faltantes",
                            value: "\(report.missingBlobs)"
                        )
                        LabeledContent(
                            "Blobs huérfanos",
                            value: "\(report.orphanBlobs)"
                        )
                        LabeledContent(
                            "Transferencias reanudables",
                            value: "\(report.pendingTransfers)"
                        )
                        LabeledContent(
                            "Datos cifrados",
                            value: ByteCountFormatter.string(
                                fromByteCount: report.encryptedBytes,
                                countStyle: .file
                            )
                        )
                    }

                    Section("Copias de metadata") {
                        statusRow(
                            "vault.json",
                            present: report.primaryConfigPresent
                        )
                        statusRow(
                            "vault.backup.json",
                            present: report.backupConfigPresent
                        )
                        statusRow(
                            "index.ssv",
                            present: report.primaryIndexPresent
                        )
                        statusRow(
                            "index.previous.ssv",
                            present: report.backupIndexPresent
                        )
                    }
                } else {
                    ProgressView()
                }

                Section {
                    Text(
                        "El diagnóstico muestra conteos y estado estructural. "
                        + "No exporta contraseñas ni contenido descifrado."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Takopi Vault")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Actualizar") {
                        vault.refreshOperationalStatus()
                        vault.refreshHealthReport()
                    }
                }
            }
            .onAppear {
                vault.refreshOperationalStatus()
                vault.refreshHealthReport()
            }
        }
    }

    @ViewBuilder
    private func statusRow(
        _ name: String,
        present: Bool
    ) -> some View {
        HStack {
            Text(name)
            Spacer()
            Image(
                systemName: present
                ? "checkmark.circle.fill"
                : "xmark.circle.fill"
            )
            .foregroundStyle(present ? .green : .red)
        }
    }
}

struct NikaidoVaultExportPicker: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(
        context: Context
    ) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forExporting: [url],
            asCopy: true
        )
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onFinish()
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            onFinish()
        }
    }
}

struct MultiFilePicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item],
            asCopy: false
        )
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onPick(urls)
        }
    }
}

struct PrivateVaultMediaViewer: View {
    @EnvironmentObject private var vault: PrivateVaultSession
    @Environment(\.dismiss) private var dismiss

    let entry: PrivateVaultEntry

    @State private var image: UIImage?
    @State private var playback: PrivateVaultVideoPlayback?
    @State private var errorText: String?
    @State private var isPreparingVideo = false
    @State private var viewerIsActive = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Group {
                if let image {
                    ZoomableImage(image: image)
                } else if let playback {
                    NikaidoSecureVideoView(player: playback.player, videoID: entry.id)
                        .ignoresSafeArea()
                } else if let errorText {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.yellow)

                        Text(errorText)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if entry.isVideo && isPreparingVideo {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)

                        Text("Preparando video cifrado…")
                            .foregroundStyle(.white)

                        Text(
                            "La primera apertura puede verificar el archivo una "
                            + "sola vez para habilitar acceso por rangos."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }

            Button {
                viewerIsActive = false
                if let playback {
                    NikaidoVideoResumeStore.capture(playback.player, id: entry.id)
                }
                vault.stopVideoPlayback(playback)
                playback = nil
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .padding()
        }
        .task(id: entry.id) {
            viewerIsActive = true
            vault.stopVideoPlayback(playback)
            playback = nil

            do {
                if entry.isImage {
                    let data = try await vault.decryptFileDataAsync(entry)

                    guard let decoded = UIImage(data: data) else {
                        errorText = "iOS no pudo decodificar esta imagen."
                        return
                    }

                    image = decoded
                    return
                }

                if entry.isVideo {
                    isPreparingVideo = true
                    defer { isPreparingVideo = false }

                    let prepared = try await vault.makeVideoPlayback(
                        for: entry
                    )

                    // Si el visor se cerró (o se cambió de video) mientras se
                    // preparaba, no se reproduce: se libera de inmediato para
                    // que ningún audio se quede sonando en segundo plano.
                    guard viewerIsActive, !Task.isCancelled else {
                        vault.stopVideoPlayback(prepared)
                        return
                    }

                    playback = prepared
                    prepared.play()
                    return
                }

                errorText = "Este tipo de archivo aún no tiene visor."
            } catch {
                errorText = error.localizedDescription
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .nikaidoVaultDidLock
        )) { _ in
            viewerIsActive = false
            vault.stopVideoPlayback(playback)
            playback = nil
            dismiss()
        }
        .onDisappear {
            viewerIsActive = false
            vault.stopVideoPlayback(playback)
            playback = nil
        }
    }
}

