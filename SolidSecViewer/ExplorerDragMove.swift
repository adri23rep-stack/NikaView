import SwiftUI
import UIKit

// MARK: - Arrastrar y soltar propio
//
// El arrastre del sistema (onDrag/onDrop) depende de tipos y de la sesión de
// UIKit y no es fiable cuando la app corre en entornos como LiveContainer.
// Este sistema usa un gesto propio sobre el asa de cada fila: mantén
// presionada el asa, arrastra y suelta sobre una carpeta o sobre el otro panel.

enum ExplorerDropTarget {
    case folder(ExplorerFileItem, pane: Int)
    case pane(Int)
    case location(ExplorerStorageLocation)
}

struct ExplorerDropRequest {
    let items: [ExplorerFileItem]
    let sourcePane: Int
    let target: ExplorerDropTarget
}

struct ExplorerDragCallbacks {
    let began: (CGPoint) -> Void
    let moved: (CGPoint) -> Void
    let ended: (CGPoint, Bool) -> Void
}

/// La posición del dedo vive aparte: así solo se redibuja la "sombra" mientras
/// se arrastra, no las listas completas.
@MainActor
final class ExplorerDragPointer: ObservableObject {
    @Published var location: CGPoint = .zero
}

@MainActor
final class ExplorerDragState: ObservableObject {
    @Published private(set) var isDragging = false
    @Published private(set) var items: [ExplorerFileItem] = []
    @Published private(set) var highlightedFolderKey: String?
    @Published private(set) var highlightedPane: Int?

    let pointer = ExplorerDragPointer()
    private(set) var sourcePane = 0

    private struct Probe {
        weak var view: UIView?
        let pane: Int
        let item: ExplorerFileItem?
    }

    private struct ExternalProbe {
        weak var view: UIView?
        let location: ExplorerStorageLocation
    }

    private var folderProbes: [String: Probe] = [:]
    private var paneProbes: [Int: Probe] = [:]
    private var externalProbes: [String: ExternalProbe] = [:]

    static func folderKey(pane: Int, id: String) -> String {
        "\(pane)|\(id)"
    }

    static func externalKey(_ id: UUID) -> String {
        "ext|\(id.uuidString)"
    }

    func registerExternal(
        key: String,
        location: ExplorerStorageLocation,
        view: UIView?
    ) {
        if let view {
            externalProbes[key] = ExternalProbe(view: view, location: location)
        } else {
            externalProbes.removeValue(forKey: key)
        }
    }

    // MARK: Registro de zonas (se lee la posición real al soltar)

    func registerFolder(
        key: String,
        pane: Int,
        item: ExplorerFileItem,
        view: UIView?
    ) {
        if let view {
            folderProbes[key] = Probe(view: view, pane: pane, item: item)
        } else {
            folderProbes.removeValue(forKey: key)
        }
    }

    func registerPane(_ index: Int, view: UIView?) {
        if let view {
            paneProbes[index] = Probe(view: view, pane: index, item: nil)
        } else {
            paneProbes.removeValue(forKey: index)
        }
    }

    // MARK: Ciclo del arrastre

    func begin(items: [ExplorerFileItem], sourcePane: Int, at point: CGPoint) {
        self.items = items
        self.sourcePane = sourcePane
        pointer.location = point
        isDragging = true
        updateHighlight(at: point)
    }

    func move(to point: CGPoint) {
        guard isDragging else { return }

        pointer.location = point
        updateHighlight(at: point)
    }

    func finish(at point: CGPoint) -> ExplorerDropRequest? {
        guard isDragging else { return nil }

        let destination = target(at: point)
        let request = destination.map {
            ExplorerDropRequest(
                items: items,
                sourcePane: sourcePane,
                target: $0
            )
        }

        reset()
        return request
    }

    func cancel() {
        reset()
    }

    private func reset() {
        isDragging = false
        items = []

        if highlightedFolderKey != nil {
            highlightedFolderKey = nil
        }

        if highlightedPane != nil {
            highlightedPane = nil
        }
    }

    private func updateHighlight(at point: CGPoint) {
        var folderKey: String?
        var pane: Int?

        switch target(at: point) {
        case .folder(let item, let paneIndex)?:
            folderKey = Self.folderKey(pane: paneIndex, id: item.id)
        case .pane(let index)?:
            pane = index
        case .location(let location)?:
            folderKey = Self.externalKey(location.id)
        case nil:
            break
        }

        if highlightedFolderKey != folderKey {
            highlightedFolderKey = folderKey
        }

        if highlightedPane != pane {
            highlightedPane = pane
        }
    }

    /// Carpeta bajo el dedo (si la hay) o, si no, el panel bajo el dedo.
    private func target(at point: CGPoint) -> ExplorerDropTarget? {
        let draggedIDs = Set(items.map(\.id))

        for entry in externalProbes.values {
            guard let view = entry.view, view.window != nil else { continue }

            if view.convert(view.bounds, to: nil).contains(point) {
                return .location(entry.location)
            }
        }

        for entry in folderProbes.values {
            guard
                let item = entry.item,
                let view = entry.view,
                view.window != nil
            else {
                continue
            }

            // Una carpeta no se puede soltar sobre sí misma.
            if entry.pane == sourcePane && draggedIDs.contains(item.id) {
                continue
            }

            if view.convert(view.bounds, to: nil).contains(point) {
                return .folder(item, pane: entry.pane)
            }
        }

        for (index, entry) in paneProbes {
            guard let view = entry.view, view.window != nil else { continue }

            if view.convert(view.bounds, to: nil).contains(point) {
                return .pane(index)
            }
        }

        return nil
    }
}

// MARK: - Sondas de posición

final class ExplorerFrameProbeView: UIView {
    var key: String?
    var register: (@MainActor (String, UIView?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard let key else { return }

        register?(key, window == nil ? nil : self)
    }
}

struct ExplorerFrameProbe: UIViewRepresentable {
    let key: String
    let register: @MainActor (String, UIView?) -> Void

    func makeUIView(context: Context) -> ExplorerFrameProbeView {
        let view = ExplorerFrameProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.key = key
        view.register = register
        return view
    }

    func updateUIView(_ view: ExplorerFrameProbeView, context: Context) {
        if view.key != key {
            if let old = view.key {
                register(old, nil)
            }

            view.key = key
        }

        view.register = register

        if view.window != nil {
            register(key, view)
        }
    }

    static func dismantleUIView(
        _ view: ExplorerFrameProbeView,
        coordinator: Void
    ) {
        if let key = view.key {
            view.register?(key, nil)
        }
    }
}

extension View {
    /// Marca una fila de carpeta como destino posible de un arrastre.
    @ViewBuilder
    func explorerFolderProbe(
        _ state: ExplorerDragState,
        pane: Int,
        item: ExplorerFileItem
    ) -> some View {
        if item.isDirectory {
            background(
                ExplorerFrameProbe(
                    key: ExplorerDragState.folderKey(pane: pane, id: item.id)
                ) { key, view in
                    state.registerFolder(
                        key: key,
                        pane: pane,
                        item: item,
                        view: view
                    )
                }
            )
        } else {
            self
        }
    }

    /// Marca una carpeta añadida (iCloud / iPhone) como destino de un arrastre.
    func explorerExternalProbe(
        _ state: ExplorerDragState,
        location: ExplorerStorageLocation
    ) -> some View {
        background(
            ExplorerFrameProbe(
                key: ExplorerDragState.externalKey(location.id)
            ) { key, view in
                state.registerExternal(
                    key: key,
                    location: location,
                    view: view
                )
            }
        )
    }

    /// Marca todo un panel como destino posible de un arrastre.
    func explorerPaneProbe(
        _ state: ExplorerDragState,
        pane: Int
    ) -> some View {
        background(
            ExplorerFrameProbe(key: "pane-\(pane)") { _, view in
                state.registerPane(pane, view: view)
            }
        )
    }
}

// MARK: - Asa de arrastre

struct ExplorerDragHandle: View {
    let callbacks: ExplorerDragCallbacks

    @State private var began = false

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 34, height: 40)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .accessibilityLabel("Arrastrar a una carpeta o al otro panel")
    }

    private var dragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(
                before: DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .global
                )
            )
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }

                if !began {
                    began = true
                    callbacks.began(drag.location)
                }

                callbacks.moved(drag.location)
            }
            .onEnded { value in
                let wasDragging = began
                began = false

                if case .second(true, let drag?) = value {
                    callbacks.ended(drag.location, true)
                } else if wasDragging {
                    callbacks.ended(.zero, false)
                }
            }
    }
}

// MARK: - "Sombra" que sigue al dedo

struct ExplorerDragGhostLayer: View {
    @ObservedObject var dragState: ExplorerDragState
    @ObservedObject var pointer: ExplorerDragPointer

    @Environment(\.nikaidoAccent) private var nikaidoAccent

    var body: some View {
        GeometryReader { proxy in
            if dragState.isDragging, let first = dragState.items.first {
                let origin = proxy.frame(in: .global).origin

                chip(first)
                    .position(
                        x: pointer.location.x - origin.x,
                        y: pointer.location.y - origin.y - 48
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private func chip(_ first: ExplorerFileItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: first.systemImage)
                .foregroundStyle(nikaidoAccent)

            Text(
                dragState.items.count == 1
                ? first.name
                : "\(dragState.items.count) elementos"
            )
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(nikaidoAccent.opacity(0.6), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .frame(maxWidth: 260)
    }
}


// MARK: - Carpetas añadidas en el inicio (con su distintivo)

extension ExplorerStorageSource {
    var badgeColor: Color {
        switch self {
        case .iCloud: return Color(red: 0.25, green: 0.55, blue: 0.95)
        case .iPhone: return Color(white: 0.35)
        case .provider: return Color(red: 0.95, green: 0.62, blue: 0.15)
        case .app: return Color(red: 0.38, green: 0.36, blue: 0.96)
        case .unknown: return Color.gray
        }
    }
}

/// Carpeta con un distintivo: nube si es de iCloud, manzana si es del iPhone.
struct ExplorerLocationBadgeIcon: View {
    let source: ExplorerStorageSource
    let folderColor: Color
    var size: CGFloat = 30

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "folder.fill")
                .font(.system(size: size * 0.72))
                .foregroundStyle(folderColor)
                .frame(width: size + 6, height: size)

            Image(systemName: source.symbol)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.white)
                .padding(size * 0.1)
                .background(source.badgeColor, in: Circle())
                .overlay(
                    Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
                )
                .offset(x: size * 0.12, y: size * 0.1)
        }
        .frame(width: size + 12, height: size + 6)
    }
}

struct ExplorerExternalLocationRow: View {
    let location: ExplorerStorageLocation
    let isDropTarget: Bool

    @Environment(\.nikaidoAccent) private var nikaidoAccent
    @Environment(\.nikaidoFolderColor) private var folderColor

    var body: some View {
        HStack(spacing: 12) {
            ExplorerLocationBadgeIcon(
                source: location.source,
                folderColor: folderColor,
                size: 30
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(location.source.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDropTarget ? nikaidoAccent.opacity(0.22) : Color.clear)
                .padding(.horizontal, -6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(nikaidoAccent, lineWidth: isDropTarget ? 2 : 0)
                .padding(.horizontal, -6)
        )
    }
}

struct ExplorerExternalLocationCell: View {
    let location: ExplorerStorageLocation
    let isDropTarget: Bool

    @Environment(\.nikaidoAccent) private var nikaidoAccent
    @Environment(\.nikaidoFolderColor) private var folderColor

    var body: some View {
        VStack(spacing: 8) {
            Color.clear
                .aspectRatio(1.1, contentMode: .fit)
                .overlay {
                    ZStack {
                        folderColor.opacity(0.12)

                        ExplorerLocationBadgeIcon(
                            source: location.source,
                            folderColor: folderColor,
                            size: 46
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(location.name)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)

            Text(location.source.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isDropTarget ? nikaidoAccent : Color.clear,
                    lineWidth: 2
                )
        )
    }
}
