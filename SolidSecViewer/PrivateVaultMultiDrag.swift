import SwiftUI
import UIKit

/// Gesto de arrastre local al Vault. Solo viajan UUID del índice cifrado:
/// ningún blob ni archivo descifrado sale de la sesión.
struct PrivateVaultDrop {
    let ids: Set<UUID>
    let folderID: UUID?
}

@MainActor
final class PrivateVaultDragState: ObservableObject {
    @Published private(set) var isDragging = false
    @Published private(set) var count = 0
    @Published private(set) var highlightedKey: String?
    @Published var pointer: CGPoint = .zero

    private struct Target {
        weak var view: UIView?
        let folderID: UUID?
    }
    private var targets: [String: Target] = [:]
    private var selected: Set<UUID> = []
    private var originFolderID: UUID?

    func register(_ key: String, folderID: UUID?, view: UIView?) {
        if let view {
            targets[key] = Target(view: view, folderID: folderID)
        } else {
            targets.removeValue(forKey: key)
        }
    }

    func begin(ids: Set<UUID>, originFolderID: UUID?, at point: CGPoint) {
        guard !ids.isEmpty else { return }
        selected = ids
        self.originFolderID = originFolderID
        count = ids.count
        isDragging = true
        pointer = point
        refreshTarget(point)
    }

    func move(to point: CGPoint) {
        guard isDragging else { return }
        pointer = point
        refreshTarget(point)
    }

    func finish(at point: CGPoint) -> PrivateVaultDrop? {
        guard isDragging else { return nil }
        let destination = destination(at: point)
        let result: PrivateVaultDrop?
        if let destination, destination != originFolderID {
            result = PrivateVaultDrop(ids: selected, folderID: destination)
        } else {
            result = nil
        }
        reset()
        return result
    }

    func cancel() { reset() }

    private func reset() {
        selected.removeAll()
        isDragging = false
        count = 0
        highlightedKey = nil
    }

    private func refreshTarget(_ point: CGPoint) {
        let key = target(at: point)?.key
        if highlightedKey != key {
            highlightedKey = key
            if key != nil { NikaidoTheme.haptic(.light) }
        }
    }

    private func target(at point: CGPoint) -> (key: String, folderID: UUID?)? {
        // No depender del orden de los diccionarios; la zona "padre" se
        // consulta antes de las tarjetas, y ambas preceden al fondo.
        let keys = targets.keys.sorted { lhs, rhs in
            let rank: (String) -> Int = { s in
                if s.hasPrefix("parent|") { return 0 }
                if s.hasPrefix("folder|") { return 1 }
                return 2
            }
            return rank(lhs) == rank(rhs) ? lhs < rhs : rank(lhs) < rank(rhs)
        }
        for key in keys {
            guard let t = targets[key], let view = t.view, view.window != nil else { continue }
            if view.convert(view.bounds, to: nil).contains(point) {
                return (key, t.folderID)
            }
        }
        return nil
    }

    private func destination(at point: CGPoint) -> UUID?? {
        guard let target = target(at: point) else { return nil }
        // Outer Optional = existe destino, inner Optional = raíz del Vault.
        return .some(target.folderID)
    }
}

extension View {
    @ViewBuilder
    func vaultMoveFolderProbe(_ state: PrivateVaultDragState,
                             entry: PrivateVaultEntry) -> some View {
        if entry.kind == .folder && !entry.isSecCollectionFolder {
            vaultMoveProbe(state, key: "folder|\(entry.id.uuidString)", folderID: entry.id)
        } else {
            self
        }
    }

    func vaultMoveProbe(_ state: PrivateVaultDragState,
                       key: String, folderID: UUID?) -> some View {
        background(
            ExplorerFrameProbe(key: key) { key, view in
                state.register(key, folderID: folderID, view: view)
            }
        )
    }
}

struct PrivateVaultDragPreview: View {
    @ObservedObject var drag: PrivateVaultDragState
    @Environment(\.nikaidoAccent) private var accent

    var body: some View {
        GeometryReader { proxy in
            if drag.isDragging {
                let origin = proxy.frame(in: .global).origin
                HStack(spacing: 7) {
                    Image(systemName: "lock.doc")
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(drag.count == 1 ? "1 elemento cifrado" :
                            "\(drag.count) elementos cifrados")
                            .font(.caption.weight(.semibold))
                        Text(drag.highlightedKey == nil ?
                            "Arrastra a una carpeta" : "Suelta para mover")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.5), lineWidth: 1.5))
                .position(x: drag.pointer.x - origin.x,
                          y: drag.pointer.y - origin.y - 46)
            }
        }
        .allowsHitTesting(false)
    }
}

struct PrivateVaultBatchDestinationPicker: View {
    @EnvironmentObject private var vault: PrivateVaultSession
    @Environment(\.dismiss) private var dismiss
    let movingIDs: Set<UUID>
    let onMove: (UUID?) -> Void

    private var folders: [PrivateVaultEntry] {
        vault.entries
            .filter { $0.kind == .folder && !$0.isSecCollectionFolder &&
                !movingIDs.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Destino") {
                    Button {
                        onMove(nil)
                        dismiss()
                    } label: {
                        Label("Raíz de Takopi Vault", systemImage: "house.fill")
                    }
                    ForEach(folders) { folder in
                        Button {
                            onMove(folder.id)
                            dismiss()
                        } label: {
                            Label(folder.name, systemImage: "folder.fill")
                                .lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("Mover seleccionados")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}
