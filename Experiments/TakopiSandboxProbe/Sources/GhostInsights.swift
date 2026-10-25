import Foundation

/// Resumen sin incluir nombres privados de archivos o identificadores de apps.
struct GhostInsights {
    struct Bucket: Identifiable, Hashable {
        let name: String
        let count: Int
        var id: String { name }
    }

    let total: Int
    let areas: [Bucket]
    let suffixes: [Bucket]
    let unknownKind: Int

    static func area(for path: String) -> String {
        if path.hasPrefix("/private/var/mobile/Containers/Data/PluginKitPlugin/") {
            return "Extensiones de aplicaciones"
        }
        if path.hasPrefix("/private/var/mobile/Containers/Data/Application/") {
            return "Aplicaciones"
        }
        if path.hasPrefix("/private/var/mobile/Containers/Shared/AppGroup/") {
            return "Grupos compartidos"
        }
        if path.hasPrefix("/private/var/mobile/Containers/Data/InternalDaemon/") {
            return "Servicios internos"
        }
        if path.hasPrefix("/private/var/mobile/Library/") {
            return "Biblioteca de iOS"
        }
        return "Otras rutas"
    }

    init(paths: [String]) {
        let unique = Set(paths.filter { $0.hasPrefix("/") })
        total = unique.count
        var groupCounts: [String: Int] = [:]
        var extensionCounts: [String: Int] = [:]
        var unspecified = 0
        for path in unique {
            groupCounts[Self.area(for: path), default: 0] += 1
            let last = String(path.split(separator: "/").last ?? "")
            let suffix = (last as NSString).pathExtension.lowercased()
            if suffix.isEmpty {
                unspecified += 1
            } else {
                extensionCounts["." + suffix, default: 0] += 1
            }
        }
        areas = groupCounts.map { Bucket(name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
        suffixes = extensionCounts.map { Bucket(name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
        unknownKind = unspecified
    }

    func filtered(_ paths: Set<String>, area: String) -> [String] {
        let items = area == "Todas" ? paths : paths.filter { Self.area(for: $0) == area }
        return items.sorted()
    }

    var summary: String {
        let lines: [String] = [
            "TAKOPI GHOST - RESUMEN ANONIMO",
            "Solo se analizaron nombres de rutas; no se leyo ningun archivo.",
            "Rutas unicas: \(total)",
            "No clasificados por extension: \(unknownKind)",
            "",
            "AREAS"
        ] + areas.map { "\($0.name): \($0.count)" } +
        ["", "EXTENSIONES MAS FRECUENTES"] +
        suffixes.prefix(15).map { "\($0.name): \($0.count)" }
        return lines.joined(separator: "\n")
    }
}
