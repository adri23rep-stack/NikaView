import Foundation

struct GhostEntry: Identifiable, Hashable {
    let path: String
    let level: Int
    let hasChildren: Bool
    let observed: Bool
    var id: String { path }
    var name: String { path == "/" ? "/" : String(path.split(separator: "/").last ?? "") }
}

struct GhostPathParser {
    let seen: Set<String>
    let children: [String: [String]]

    init(paths: [String]) {
        self.init(report: paths.map { "GHOST_PATH|" + $0 }.joined(separator: "\n"))
    }

    init(report: String) {
        var observed = Set<String>()
        var readingExamples = false
        let plainList = !report.contains("TAKOPI FSGETPATH") && !report.contains("EJEMPLOS POR CATEGORÍA")
        for line in report.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "EJEMPLOS POR CATEGORÍA" { readingExamples = true; continue }
            if trimmed.hasPrefix("PRUEBA DE PERMISOS") { readingExamples = false }
            if trimmed.hasPrefix("GHOST_PATH|") {
                let candidate = String(trimmed.dropFirst("GHOST_PATH|".count))
                if candidate.hasPrefix("/") { observed.insert(candidate) }
            } else if readingExamples && trimmed.hasPrefix("• /") {
                observed.insert(String(trimmed.dropFirst(2)))
            } else if plainList && trimmed.hasPrefix("/") && !trimmed.contains(" | ") {
                observed.insert(trimmed)
            }
        }
        var mapping: [String: Set<String>] = ["/": []]
        for item in observed {
            var parent = "/"
            for component in item.split(separator: "/", omittingEmptySubsequences: true) {
                let next = parent == "/" ? "/" + component : parent + "/" + component
                mapping[parent, default: []].insert(next)
                if mapping[next] == nil { mapping[next] = [] }
                parent = next
            }
        }
        self.seen = observed
        self.children = mapping.mapValues { $0.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    }

    func visible(expanded: Set<String>, limit: Int = 1500) -> [GhostEntry] {
        var result: [GhostEntry] = []
        func add(_ path: String, level: Int) {
            guard result.count < limit else { return }
            result.append(GhostEntry(path: path, level: level,
                                     hasChildren: !(children[path]?.isEmpty ?? true),
                                     observed: seen.contains(path)))
            if expanded.contains(path) {
                for next in children[path] ?? [] where result.count < limit {
                    add(next, level: level + 1)
                }
            }
        }
        add("/", level: 0)
        return result
    }

    func search(_ keyword: String, limit: Int = 1500) -> [GhostEntry] {
        let term = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return seen.filter { $0.localizedCaseInsensitiveContains(term) }
            .sorted().prefix(limit).map { GhostEntry(path: $0, level: 0,
                                                   hasChildren: !(children[$0]?.isEmpty ?? true),
                                                   observed: true) }
    }
}
