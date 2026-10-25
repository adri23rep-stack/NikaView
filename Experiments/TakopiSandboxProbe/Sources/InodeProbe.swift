import Foundation
import Darwin
import UIKit

// Convierte un identificador de archivo a una ruta, sin abrir su contenido.
@_silgen_name("fsgetpath")
private func probe_fsgetpath(
    _ buffer: UnsafeMutablePointer<CChar>,
    _ bufferSize: Int,
    _ filesystemID: UnsafePointer<fsid_t>,
    _ inode: UInt64
) -> Int

enum InodeProbe {
    private static let maxSeconds = 4.0
    private static let maxExamplesPerGroup = 5

    private static func group(for path: String) -> String {
        if path.hasPrefix("/private/var/mobile/Library/") ||
           path.hasPrefix("/var/mobile/Library/") {
            return "Biblioteca móvil"
        }
        if path.contains("/Containers/Data/Application/") {
            return "Contenedores de apps"
        }
        if path.hasPrefix("/private/var/containers/") ||
           path.hasPrefix("/var/containers/") {
            return "Contenedores del sistema"
        }
        if path.hasPrefix("/System/") ||
           path.hasPrefix("/usr/") {
            return "Sistema"
        }
        return "Otras rutas"
    }

    static func run() -> String {
        let home = NSHomeDirectory()
        let isVirtual = home.contains("/Documents/Data/Application/")
        var volume = statfs()
        var homeMetadata = stat()

        var report: [String] = [
            "TAKOPI FSGETPATH PROBE 0.3",
            "iOS: \(UIDevice.current.systemVersion)",
            "Modo: solo nombres, sin lectura del contenido",
            "Entorno: \(isVirtual ? "posible LiveContainer" : "contenedor directo")",
            ""
        ]

        guard home.withCString({ statfs($0, &volume) }) == 0 else {
            return (report + ["statfs: error \(errno)"]).joined(separator: "\n")
        }
        guard home.withCString({ lstat($0, &homeMetadata) }) == 0 else {
            return (report + ["lstat: error \(errno)"]).joined(separator: "\n")
        }

        var fsid = volume.f_fsid
        let ownID = UInt64(homeMetadata.st_ino)

        func resolve(_ identifier: UInt64) -> (String?, Int32) {
            var buffer = [CChar](repeating: 0, count: 2048)
            errno = 0
            let length = withUnsafePointer(to: &fsid) { pointer in
                buffer.withUnsafeMutableBufferPointer { bytes in
                    probe_fsgetpath(bytes.baseAddress!, bytes.count, pointer, identifier)
                }
            }
            let errorCode = errno
            if length > 0 { return (String(cString: buffer), 0) }
            return (nil, errorCode)
        }

        let (ownPath, ownError) = resolve(ownID)
        guard let ownPath else {
            report.append("🔒 Control propio no resuelto: errno \(ownError)")
            report.append("No se realiza el barrido.")
            return report.joined(separator: "\n")
        }
        report.append("✅ Control positivo: ruta del contenedor propio recuperada")
        report.append("Inode propio: \(ownID)")

        let start = ProcessInfo.processInfo.systemUptime
        var visited = Set<UInt64>()
        var uniquePaths = Set<String>()
        var checked = 0
        var resolvedCount = 0
        var categories: [String: [String]] = [:]

        func inspect(_ identifier: UInt64) {
            guard visited.insert(identifier).inserted else { return }
            checked += 1
            let (path, _) = resolve(identifier)
            guard let path else { return }
            resolvedCount += 1
            guard uniquePaths.insert(path).inserted else { return }

            let category = group(for: path)
            if (categories[category]?.count ?? 0) < maxExamplesPerGroup {
                categories[category, default: []].append(path)
            }
        }

        for identifier in UInt64(1)...UInt64(25_000) {
            if checked % 128 == 0 &&
               ProcessInfo.processInfo.systemUptime - start >= maxSeconds { break }
            inspect(identifier)
        }

        if ProcessInfo.processInfo.systemUptime - start < maxSeconds {
            let first = ownID > 350 ? ownID - 350 : 1
            let end = ownID > UInt64.max - 350 ? UInt64.max : ownID + 350
            for identifier in first...end {
                if checked % 128 == 0 &&
                   ProcessInfo.processInfo.systemUptime - start >= maxSeconds { break }
                inspect(identifier)
            }
        }

        let duplicateCount = resolvedCount - uniquePaths.count
        report += [
            "",
            "Identificadores examinados: \(checked)",
            "Resoluciones exitosas: \(resolvedCount)",
            "Rutas ÚNICAS: \(uniquePaths.count)",
            "Rutas repetidas: \(duplicateCount)",
            "",
            "EJEMPLOS POR CATEGORÍA"
        ]

        for category in [
            "Biblioteca móvil",
            "Contenedores de apps",
            "Contenedores del sistema",
            "Sistema",
            "Otras rutas"
        ] {
            guard let examples = categories[category], !examples.isEmpty else { continue }
            report.append("\n\(category):")
            report.append(contentsOf: examples.map { " • \($0)" })
        }

        // Comparación explícita: detectar un nombre no concede permiso para listar.
        report += ["", "PRUEBA DE PERMISOS (no lee archivos)"]
        for path in [
            ownPath,
            "/private/var/mobile/Library/Safari",
            "/private/var/mobile/Library/AddressBook",
            "/private/var/mobile/Containers/Data/Application"
        ] {
            do {
                let entries = try FileManager.default.contentsOfDirectory(atPath: path)
                report.append("\(path): LISTABLE (\(entries.count) elementos, nombres no incluidos)")
            } catch {
                let problem = error as NSError
                report.append("\(path): BLOQUEADO (\(problem.domain) \(problem.code))")
            }
        }

        report += [
            "",
            "Ver nombres no significa poder leer archivos.",
            "Máximo 4 segundos. No se modifican ni transmiten datos.",
            "Un barrido dentro de LiveContainer NO prueba el comportamiento de una app instalada directamente."
        ]
        return report.joined(separator: "\n")
    }
}
