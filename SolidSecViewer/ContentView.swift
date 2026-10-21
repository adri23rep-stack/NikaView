import SwiftUI
import UIKit

private enum AppMode {
    case home
    case explorer
    case privateVault
    case secReader
}

struct ContentView: View {
    @EnvironmentObject private var vault: VaultSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var privateVault = PrivateVaultSession()
    @StateObject private var locations = SecurityScopedFolderStore()

    @State private var mode: AppMode = .home
    @State private var launchRequest: ExplorerLaunchRequest?
    @State private var showFolderPicker = false
    @State private var showZipPicker = false
    @State private var password = ""
    @State private var zipExtractionRoot: URL?
    @State private var zipDetectedPath: String?
    @State private var zipImportError: String?
    @State private var isImportingZip = false
    @State private var selectedZipSourceURL: URL?
    @State private var showScreenshotWarning = false
    @State private var zipOperationID = UUID()
    @State private var selectedItem: VaultItem?
    @State private var pendingIncomingURL: URL?
    @State private var showIncomingChooser = false
    @State private var incomingNotice: String?
    @State private var incomingImportBusy = false
    @State private var showHidden = false
    @State private var search = ""

    /// Anima vistas públicas. Cerrar la bóveda no retiene cuadros con datos privados.
    private func navigate(_ target: AppMode, animated: Bool = true) {
        if animated && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled {
            withAnimation(.easeInOut(duration: 0.24)) {
                mode = target
            }
        } else {
            mode = target
        }
    }

    private var visibleItems: [VaultItem] {
        vault.items.filter { item in
            (showHidden || !item.name.hasPrefix(".")) &&
            (search.isEmpty || item.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .home:
                    HomeView(
                        locations: locations,
                        onOpenExplorer: { kind in
                            launchRequest = ExplorerLaunchRequest(kind: kind)
                            navigate(.explorer)
                        },
                        onOpenVault: {
                            navigate(.privateVault)
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))

                case .explorer:
                    ExplorerView(
                        locations: locations,
                        launchRequest: launchRequest,
                        onOpenHome: {
                            launchRequest = nil
                            navigate(.home, animated: false)
                        },
                        onOpenVault: {
                            launchRequest = nil
                            navigate(.privateVault)
                        },
                        onOpenSecReader: {
                            launchRequest = nil
                            navigate(.secReader)
                        }
                    )
                    .environmentObject(privateVault)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))

                case .privateVault:
                    PrivateVaultView {
                        privateVault.lock()
                        navigate(.home, animated: false)
                    }
                    .environmentObject(privateVault)
                    .transition(.opacity)

                case .secReader:
                    secReaderScreen
                        .transition(.opacity)
                }
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker { url in
                cleanupZipExtraction(clearVault: false)
                zipDetectedPath = nil
                zipImportError = nil
                vault.setFolder(url)
            }
        }
        .sheet(isPresented: $showZipPicker) {
            ZipFilePicker { url in
                Task {
                    await importSecZip(url)
                }
            }
        }
        .sheet(item: $selectedItem) { item in
            MediaViewer(item: item)
                .environmentObject(vault)
        }
        .onOpenURL { url in
            // LaunchServices can open a document in a signed standalone app.
            // A LiveContainer guest may not be registered as a system share target.
            guard url.isFileURL else { return }
            pendingIncomingURL = url
            showIncomingChooser = true
        }
        .confirmationDialog(
            "Importar documento a NikaView",
            isPresented: $showIncomingChooser,
            titleVisibility: .visible
        ) {
            Button("Guardar en NikaView Files") {
                importIncomingDocument(intoVault: false)
            }
            if privateVault.isUnlocked {
                Button("Guardar cifrado en la bóveda") {
                    importIncomingDocument(intoVault: true)
                }
            }
            Button("Cancelar", role: .cancel) { pendingIncomingURL = nil }
        } message: {
            Text(privateVault.isUnlocked
                 ? "Elige dónde guardar una copia. Nunca se eliminará el archivo compartido."
                 : "Para guardar directamente en la bóveda, ábrela primero. Este documento puede importarse a Archivos sin desbloquearla.")
        }
        .alert("Importación de archivos", isPresented: Binding(
            get: { incomingNotice != nil },
            set: { if !$0 { incomingNotice = nil } }
        )) {
            Button("Entendido", role: .cancel) { incomingNotice = nil }
        } message: {
            Text(incomingNotice ?? "")
        }
        .onAppear {
            if PrivacyShield.isScreenCaptureActive() {
                PrivacyShield.show(
                    message: "Grabación o duplicación de pantalla detectada"
                )
                lockForPrivacy()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIScene.willDeactivateNotification
        )) { _ in
            // Scene-level deactivation may precede the app-level notification
            // when iOS starts preparing the switcher snapshot.
            PrivacyShield.show()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willResignActiveNotification
        )) { _ in
            // Cover immediately so app-switcher snapshots / transient system UI
            // never expose the vault. Do NOT destroy the session here: system
            // permission prompts (notably Local Network on first LAN use) can make
            // the app temporarily inactive without actually backgrounding it.
            PrivacyShield.show()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.protectedDataWillBecomeUnavailableNotification
        )) { _ in
            // The phone is locking. Do not keep plaintext, video decoders or
            // network receive keys alive when protected storage becomes unavailable.
            PrivacyShield.show()
            lockForPrivacy()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didEnterBackgroundNotification
        )) { _ in
            PrivacyShield.show()

            if !LANTransferActivity.shared.isActive {
                lockForPrivacy()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .nikaidoLinkGraceExpired
        )) { _ in
            PrivacyShield.show()
            lockForPrivacy()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification
        )) { _ in
            if PrivacyShield.isScreenCaptureActive() {
                PrivacyShield.show(
                    message: "Grabación o duplicación de pantalla detectada"
                )
                lockForPrivacy()
            } else {
                PrivacyShield.hide()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIScreen.capturedDidChangeNotification
        )) { notification in
            let captured = (notification.object as? UIScreen)?.isCaptured
                ?? PrivacyShield.isScreenCaptureActive()

            if captured {
                PrivacyShield.show(
                    message: "Grabación o duplicación de pantalla detectada"
                )
                lockForPrivacy()
            } else if UIApplication.shared.applicationState == .active {
                PrivacyShield.hide()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.userDidTakeScreenshotNotification
        )) { _ in
            // Public iOS APIs notify AFTER a screenshot was taken; we cannot
            // retroactively prevent it. Lock immediately so subsequent content
            // is protected.
            PrivacyShield.show(message: "Captura detectada")
            lockForPrivacy()

            // Screenshot notifications arrive AFTER iOS has already saved the
            // image. We cannot stop that screenshot with a public API.
            // Never wait an arbitrary 600 ms before updating the locked UI.
            DispatchQueue.main.async {
                guard UIApplication.shared.applicationState == .active,
                      !PrivacyShield.isScreenCaptureActive() else { return }
                PrivacyShield.hide()
                showScreenshotWarning = true
            }
        }
        .alert("Captura detectada", isPresented: $showScreenshotWarning) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text(
                "iOS avisa a la app después de hacer una captura. "
                + "Nikaido Explorer bloqueó las bóvedas inmediatamente, pero no puede "
                + "borrar una captura que el sistema ya guardó."
            )
        }
    }

    @MainActor
    private func importIncomingDocument(intoVault: Bool) {
        guard !incomingImportBusy, let source = pendingIncomingURL else { return }
        pendingIncomingURL = nil
        incomingImportBusy = true
        Task { @MainActor in
            defer { incomingImportBusy = false }
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do {
                if intoVault {
                    guard privateVault.isUnlocked else {
                        incomingNotice = "Desbloquea la bóveda y vuelve a compartir el documento."
                        return
                    }
                    privateVault.errorMessage = nil
                    await privateVault.importFiles(urls: [source], parentID: nil)
                    guard privateVault.errorMessage == nil else {
                        throw NSError(domain: "NikaView.Import", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: privateVault.errorMessage ?? "No se pudo cifrar"]) 
                    }
                    incomingNotice = "Archivo importado y cifrado en la bóveda."
                } else {
                    guard let location = locations.localLocation else {
                        incomingNotice = "No hay almacenamiento local disponible."
                        return
                    }
                    try await ExplorerFileEngine.importFile(
                        from: source,
                        into: location.rootURL,
                        root: location.rootURL
                    )
                    incomingNotice = "Documento copiado a NikaView Files."
                }
            } catch {
                incomingNotice = "No se pudo importar: \(error.localizedDescription)"
            }
        }
    }

    private func lockForPrivacy() {
        // A real privacy lock must also terminate LAN because the receiver owns
        // working key material while it encrypts incoming files.
        NotificationCenter.default.post(
            name: .nikaidoForceStopLink,
            object: nil
        )
        LANTransferActivity.shared.end()

        vault.lock()
        privateVault.lock()
        selectedItem = nil
        password = ""

        // ZIP extraction contains only the already-encrypted .sec blobs, but
        // remove the temporary copy when the app backgrounds to avoid wasting
        // storage and to keep the external source ephemeral.
        cleanupZipExtraction(clearVault: true)
    }

    private func importSecZip(_ url: URL) async {
        cleanupZipExtraction(clearVault: true)
        let operation = UUID()
        zipOperationID = operation

        zipImportError = nil
        zipDetectedPath = nil
        selectedZipSourceURL = url
        isImportingZip = true

        do {
            let result = try await SecZipImporter.importArchive(at: url)

            guard zipOperationID == operation, !Task.isCancelled else {
                try? FileManager.default.removeItem(at: result.extractionRootURL)
                return
            }

            zipExtractionRoot = result.extractionRootURL
            zipDetectedPath = result.detectedPath
            vault.setFolder(result.secFolderURL)
        } catch {
            if zipOperationID == operation {
                zipImportError = error.localizedDescription
                selectedZipSourceURL = nil
            }
        }

        if zipOperationID == operation {
            isImportingZip = false
        }
    }

    private func cleanupZipExtraction(clearVault: Bool) {
        zipOperationID = UUID()
        isImportingZip = false

        if clearVault {
            vault.clearFolder()
        }

        if let root = zipExtractionRoot {
            try? FileManager.default.removeItem(at: root)
            zipExtractionRoot = nil
        }

        zipDetectedPath = nil
        selectedZipSourceURL = nil

        if clearVault {
            zipImportError = nil
        }
    }

    private var home: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "lock.square.stack.fill")
                .font(.system(size: 68))
                .foregroundStyle(.secondary)

            Text("Nikaido Explorer")
                .font(.largeTitle.bold())

            Text("Privacidad, multimedia y Nikaido Vault")
                .foregroundStyle(.secondary)

            Button {
                navigate(.privateVault)
            } label: {
                HStack {
                    Image(systemName: "externaldrive.badge.lock")
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nikaido Vault")
                            .font(.headline)

                        Text("Espacio propio cifrado dentro de la app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                }
                .padding(8)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

            Button {
                navigate(.secReader)
            } label: {
                HStack {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Abrir colección .sec")
                            .font(.headline)

                        Text("Modo compatible de solo lectura")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                }
                .padding(8)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)

            Spacer()

            Text("Sin nube • red local solo bajo demanda • bloqueo al salir")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom)
        }
        .navigationTitle("Inicio")
    }

    @ViewBuilder
    private var secReaderScreen: some View {
        if vault.isUnlocked {
            externalGallery
                .navigationTitle("Carpeta .sec")
        } else {
            externalUnlock
                .navigationTitle("Colección .sec")
        }
    }

    private var externalUnlock: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    cleanupZipExtraction(clearVault: true)
                    navigate(.explorer)
                } label: {
                    Label("Explorer", systemImage: "chevron.left")
                }

                Spacer()
            }
            .padding(.horizontal)

            Spacer()

            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 58))
                .foregroundStyle(.secondary)

            Text("Abrir colección .sec")
                .font(.title2.bold())

            Text(
                vault.folderURL?.lastPathComponent
                ?? "Selecciona un ZIP que contenga tu carpeta .sec"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .padding(.horizontal)

            Button {
                showZipPicker = true
            } label: {
                Label("Abrir ZIP con carpeta .sec", systemImage: "doc.zipper")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isImportingZip)

            if isImportingZip {
                ProgressView("Buscando y extrayendo .sec…")
            }

            if let detected = zipDetectedPath {
                Label(
                    "Encontrada automáticamente: \(detected)",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

                if selectedZipSourceURL != nil {
                    Text(
                        "Para guardar colecciones grandes en Nikaido Vault sin duplicar "
                        + "12–24 GB temporales, usa Nikaido Vault → Wi‑Fi → Recibir .sec "
                        + "desde PC. Nikaido Link guarda solo los archivos .sec cifrados."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                }
            }

            if let zipImportError {
                Text(zipImportError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                showFolderPicker = true
            } label: {
                Label("O intentar elegir carpeta directamente", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            Text(
                "El ZIP puede contener otras carpetas: Nikaido Explorer busca automáticamente "
                + "la mejor carpeta .sec y extrae únicamente ese subárbol. "
                + "La selección directa de carpetas se conserva como alternativa."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)

            SecureField("Contraseña", text: $password)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 28)

            Button("Desbloquear") {
                Task {
                    await vault.unlock(password: password)

                    if vault.isUnlocked {
                        password = ""
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vault.folderURL == nil || password.isEmpty || vault.isBusy)

            if vault.isBusy {
                ProgressView("Descifrando nombres…")
            }

            if let error = vault.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
    }

    private var externalGallery: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    cleanupZipExtraction(clearVault: true)
                    selectedItem = nil
                    navigate(.explorer)
                } label: {
                    Image(systemName: "house")
                }
                .buttonStyle(.bordered)

                TextField("Buscar", text: $search)
                    .textFieldStyle(.roundedBorder)

                Toggle("Mostrar .ocultos", isOn: $showHidden)
                    .labelsHidden()

                Button {
                    vault.lock()
                    selectedItem = nil
                } label: {
                    Image(systemName: "lock.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Bloquear")
            }
            .padding(.horizontal)

            if visibleItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)

                    Text("Sin archivos visibles")
                        .font(.headline)

                    Text("Puede que solo haya archivos ocultos con punto al inicio.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 110), spacing: 6)],
                        spacing: 6
                    ) {
                        ForEach(visibleItems) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                VaultThumbnail(item: item)
                                    .environmentObject(vault)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }
}
