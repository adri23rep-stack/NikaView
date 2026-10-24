import SwiftUI
import UniformTypeIdentifiers

/// Panel pequeño diseñado para convivir con Takopi Files en la división
/// redimensionable. Usa LA MISMA sesión cifrada que la bóveda completa.
struct ExplorerVaultSplitPane: View {
    @EnvironmentObject private var vault: PrivateVaultSession
    @Environment(\.nikaidoAccent) private var accent
    @Binding var currentFolderID: UUID?
    @ObservedObject var dragState: ExplorerDragState

    let onOpenFullVault: () -> Void
    let onSwitchToFiles: () -> Void
    let onFilesDropped: ([NSItemProvider]) -> Bool
    let onFilesDroppedToFolder: ([NSItemProvider], UUID) -> Bool

    @State private var password = ""
    @State private var isDropTargeted = false
    @State private var targetedFolderID: UUID?

    private var children: [PrivateVaultEntry] {
        guard vault.isUnlocked else { return [] }
        return vault.children(of: currentFolderID)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: vault.isUnlocked ? "lock.open.fill" : "lock.fill")
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Takopi Vault")
                        .font(.subheadline.weight(.semibold))
                    Text(vault.isUnlocked ? vault.folderName(currentFolderID) : "Bloqueada")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                Menu {
                    Button {
                        onOpenFullVault()
                    } label: {
                        Label("Abrir bóveda completa", systemImage: "arrow.up.right.square")
                    }
                    Button {
                        onSwitchToFiles()
                    } label: {
                        Label("Mostrar Takopi Files", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Opciones de panel de bóveda")
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            Divider()

            if !vault.isUnlocked {
                lockedContent
            } else {
                unlockedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .explorerPaneProbe(dragState, pane: 1)
        .onDrop(of: [UTType.plainText.identifier], isTargeted: $isDropTargeted) { providers in
            guard vault.isUnlocked else { return false }
            return onFilesDropped(providers)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(accent, lineWidth: dragState.highlightedPane == 1 || isDropTargeted ? 3 : 0)
                .allowsHitTesting(false)
        }
        .onReceive(vault.$isUnlocked) { unlocked in
            if !unlocked {
                currentFolderID = nil
                password = ""
            }
        }
    }

    private var lockedContent: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 5)
            Image(systemName: "lock.shield")
                .font(.system(size: 28))
                .foregroundStyle(accent)
            if vault.hasVault {
                Text("Desbloquea para importar archivos cifrados")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                SecureField("Contraseña de la bóveda", text: $password)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 14)
                Button {
                    let typed = password
                    password = ""
                    Task { await vault.unlock(password: typed) }
                } label: {
                    Label("Desbloquear", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .padding(.horizontal, 14)
                .disabled(password.isEmpty || vault.isBusy)
            } else {
                Text("Primero crea tu bóveda privada.")
                    .font(.caption)
                Button("Crear Takopi Vault") { onOpenFullVault() }
                    .buttonStyle(.borderedProminent)
            }
            if let error = vault.errorMessage {
                Text(error).font(.caption2).foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 5)
        }
        .padding(.vertical, 10)
    }

    private var unlockedContent: some View {
        VStack(spacing: 0) {
            HStack {
                if currentFolderID != nil {
                    Button {
                        currentFolderID = vault.parent(of: currentFolderID)
                    } label: {
                        Label("Atrás", systemImage: "chevron.left")
                    }
                    .font(.caption)
                }
                Spacer()
                Text("\(children.count) elementos")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)

            ScrollView {
                LazyVStack(spacing: 4) {
                    if children.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("Carpeta vacía")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                    }
                    ForEach(children) { entry in
                        Button {
                            if entry.kind == .folder {
                                currentFolderID = entry.id
                            } else {
                                onOpenFullVault()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: entry.kind == .folder
                                      ? "folder.fill" : "doc.fill")
                                    .foregroundStyle(accent)
                                Text(entry.name)
                                    .lineLimit(1)
                                    .font(.subheadline)
                                Spacer(minLength: 2)
                                if entry.kind == .folder {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 42)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(accent.opacity(
                                    dragState.highlightedFolderKey == ExplorerDragState.vaultFolderKey(entry.id)
                                    || targetedFolderID == entry.id ? 0.20 : 0
                                ))
                        )
                        .explorerVaultFolderProbe(dragState, entry: entry)
                        .onDrop(
                            of: entry.kind == .folder && !entry.isSecCollectionFolder
                                ? [UTType.plainText.identifier] : [],
                            isTargeted: Binding(
                                get: { targetedFolderID == entry.id },
                                set: { targetedFolderID = $0 ? entry.id : nil }
                            )
                        ) { providers in
                            guard vault.isUnlocked, entry.kind == .folder,
                                  !entry.isSecCollectionFolder else { return false }
                            return onFilesDroppedToFolder(providers, entry.id)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .background(ExplorerDragEdgeScroll(state: dragState))
            .scrollDisabled(dragState.isDragging)

            HStack(spacing: 6) {
                Image(systemName: "arrow.down.doc")
                Text(dragState.isDragging && dragState.highlightedPane == 1
                     ? "Suelta para cifrar" : "Arrastra aquí archivos de Takopi Files")
                    .lineLimit(2)
            }
            .font(.caption2)
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .background(accent.opacity(0.08))
            if vault.isBusy {
                ProgressView("Cifrando…").font(.caption).padding(.vertical, 4)
            }
            if let error = vault.errorMessage {
                Text(error).font(.caption2).foregroundStyle(.red)
                    .padding(.horizontal, 10).lineLimit(3)
            }
        }
    }
}
