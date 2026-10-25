import Foundation

/// Compara únicamente nombres de rutas obtenidos en capturas separadas.
/// Una ruta ausente NO demuestra que el archivo haya sido eliminado.
struct GhostSnapshotDiff {
    struct Count: Hashable, Identifiable {
        let area: String
        let current: Int
        let previous: Int
        let appeared: Int
        let notObserved: Int
        var id: String { area }
    }

    let appeared: [String]
    let noLongerObserved: [String]
    let shared: Int
    let previousTotal: Int
    let currentTotal: Int
    let counts: [Count]

    init(previous: Set<String>, current: Set<String>) {
        let old = Set(previous.filter { $0.hasPrefix("/") })
        let now = Set(current.filter { $0.hasPrefix("/") })

        appeared = now.subtracting(old).sorted()
        noLongerObserved = old.subtracting(now).sorted()
        shared = old.intersection(now).count
        previousTotal = old.count
        currentTotal = now.count

        let areas = Set(old.union(now).map(GhostInsights.area(for:))).sorted()
        counts = areas.map { area in
            Count(
                area: area,
                current: now.filter { GhostInsights.area(for: $0) == area }.count,
                previous: old.filter { GhostInsights.area(for: $0) == area }.count,
                appeared: appeared.filter { GhostInsights.area(for: $0) == area }.count,
                notObserved: noLongerObserved.filter { GhostInsights.area(for: $0) == area }.count
            )
        }.sorted { $0.current > $1.current }
    }

    var safeSummary: String {
        let lines = [
            "TAKOPI GHOST 0.7 - COMPARACION ANONIMA",
            "Solo compara nombres. No indica archivos realmente creados o eliminados.",
            "Rutas captura anterior: \(previousTotal)",
            "Rutas captura actual: \(currentTotal)",
            "Sin cambios: \(shared)",
            "Presentes solo en la actual: \(appeared.count)",
            "No observadas en la actual: \(noLongerObserved.count)",
            "",
            "CAMBIOS POR AREA"
        ] + counts.map { "\($0.area): +\($0.appeared), no observadas \($0.notObserved)" }
        return lines.joined(separator: "\n")
    }

    func matching(_ paths: [String], query: String, limit: Int = 250) -> [String] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = term.isEmpty ? paths : paths.filter { $0.localizedCaseInsensitiveContains(term) }
        return Array(filtered.prefix(limit))
    }
}
