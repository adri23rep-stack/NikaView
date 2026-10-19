import Foundation
import Combine

@MainActor
final class ExplorerPaneState: ObservableObject, Identifiable {
    let id = UUID()

    @Published private(set) var location: ExplorerStorageLocation?
    @Published private(set) var currentURL: URL?
    @Published private(set) var items: [ExplorerFileItem] = []
    @Published var selectedIDs: Set<String> = []
    @Published var selectionMode = false
    @Published var showHidden = false
    @Published var sortMode: ExplorerSortMode = .name
    @Published var viewMode: ExplorerViewMode = .list
    @Published var ascending = true
    @Published var search = ""
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var refreshGeneration: UInt64 = 0

    var selectedItems: [ExplorerFileItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    var title: String {
        guard let currentURL, let location else {
            return "Sin ubicación"
        }

        if currentURL.standardizedFileURL ==
            location.rootURL.standardizedFileURL
        {
            return location.name
        }

        return currentURL.lastPathComponent
    }

    var relativePath: String {
        guard let currentURL, let location else {
            return ""
        }

        let root = location.rootURL.standardizedFileURL.path
        let current = currentURL.standardizedFileURL.path

        if root == current {
            return "/"
        }

        let prefix = root.hasSuffix("/") ? root : root + "/"

        guard current.hasPrefix(prefix) else {
            return "/"
        }

        return "/" + current.dropFirst(prefix.count)
    }

    var canGoUp: Bool {
        guard let currentURL, let location else {
            return false
        }

        return currentURL.standardizedFileURL !=
            location.rootURL.standardizedFileURL
    }

    func openLocation(_ location: ExplorerStorageLocation) {
        openLocation(location, folderURL: location.rootURL)
    }

    // MARK: - Historial (atrás / adelante)

    @Published private(set) var backStack: [URL] = []
    @Published private(set) var forwardStack: [URL] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    private func recordNavigation(from previous: URL?) {
        if let previous {
            backStack.append(previous)

            if backStack.count > 50 {
                backStack.removeFirst()
            }
        }

        forwardStack.removeAll()
    }

    func goBack() {
        guard let target = backStack.popLast() else { return }

        if let currentURL {
            forwardStack.append(currentURL)
        }

        currentURL = target
        selectedIDs.removeAll()

        Task {
            await refresh()
        }
    }

    func goForward() {
        guard let target = forwardStack.popLast() else { return }

        if let currentURL {
            backStack.append(currentURL)
        }

        currentURL = target
        selectedIDs.removeAll()

        Task {
            await refresh()
        }
    }

    func openLocation(
        _ location: ExplorerStorageLocation,
        folderURL: URL
    ) {
        do {
            try ExplorerFileEngine.ensureInsideRoot(
                folderURL,
                root: location.rootURL
            )

            if self.location?.id == location.id {
                recordNavigation(from: currentURL)
            } else {
                backStack.removeAll()
                forwardStack.removeAll()
            }

            self.location = location
            currentURL = folderURL.standardizedFileURL
            NikaidoRecents.record(locationID: location.id, folder: folderURL)
            selectedIDs.removeAll()
            selectionMode = false

            Task {
                await refresh()
            }
        } catch {
            errorMessage = ExplorerErrorText.message(for: error)
        }
    }

    func open(_ item: ExplorerFileItem) {
        guard item.isDirectory else { return }
        guard let location else { return }

        do {
            try ExplorerFileEngine.ensureInsideRoot(
                item.url,
                root: location.rootURL
            )
            recordNavigation(from: currentURL)
            currentURL = item.url
            NikaidoRecents.record(locationID: location.id, folder: item.url)
            selectedIDs.removeAll()

            Task {
                await refresh()
            }
        } catch {
            errorMessage = ExplorerErrorText.message(for: error)
        }
    }

    func goUp() {
        guard
            canGoUp,
            let currentURL,
            let location
        else {
            return
        }

        let parent = currentURL.deletingLastPathComponent()

        do {
            try ExplorerFileEngine.ensureInsideRoot(
                parent,
                root: location.rootURL
            )

            recordNavigation(from: self.currentURL)
            self.currentURL = parent
            selectedIDs.removeAll()

            Task {
                await refresh()
            }
        } catch {
            goRoot()
        }
    }

    func goRoot() {
        guard let location else { return }

        recordNavigation(from: currentURL)
        currentURL = location.rootURL
        selectedIDs.removeAll()

        Task {
            await refresh()
        }
    }

    func toggleSelection(_ item: ExplorerFileItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func selectAll() {
        selectedIDs = Set(items.map(\.id))
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func refresh() async {
        guard let location, let currentURL else {
            items = []
            return
        }

        refreshGeneration &+= 1
        let generation = refreshGeneration

        isLoading = true
        errorMessage = nil

        do {
            let loaded = try await ExplorerFileEngine.list(
                directory: currentURL,
                root: location.rootURL,
                showHidden: showHidden,
                sort: sortMode,
                ascending: ascending,
                search: search
            )

            guard generation == refreshGeneration else {
                return
            }

            items = loaded
            selectedIDs = selectedIDs.intersection(
                Set(loaded.map(\.id))
            )
        } catch {
            if generation == refreshGeneration {
                errorMessage = ExplorerErrorText.message(for: error)
                items = []
            }
        }

        if generation == refreshGeneration {
            isLoading = false
        }
    }
}
