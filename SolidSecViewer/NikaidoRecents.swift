import Foundation

struct NikaidoRecentFolder: Codable, Identifiable {
    let id: UUID
    let locationID: UUID
    let path: String
    let label: String
}

enum NikaidoRecents {
    private static let key = "NikaView.recentFolders.v1"

    static func record(locationID: UUID, folder: URL) {
        let name = folder.lastPathComponent
        let item = NikaidoRecentFolder(id: UUID(), locationID: locationID,
                                      path: folder.standardizedFileURL.path, label: name)
        var saved = all.filter { !($0.locationID == locationID && $0.path == item.path) }
        saved.insert(item, at: 0)
        persist(Array(saved.prefix(12)))
    }

    static var all: [NikaidoRecentFolder] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([NikaidoRecentFolder].self, from: data)
        else { return [] }
        return items
    }

    private static func persist(_ items: [NikaidoRecentFolder]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
