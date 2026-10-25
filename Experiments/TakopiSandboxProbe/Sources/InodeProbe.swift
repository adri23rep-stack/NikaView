import Foundation
import Darwin
import UIKit

// API de macOS/iOS que intenta convertir un identificador de archivo a una ruta.
// No abre el archivo ni solicita privilegios adicionales.
@_silgen_name("fsgetpath")
private func probe_fsgetpath(
    _ buffer: UnsafeMutablePointer<CChar>,
    _ bufferSize: Int,
    _ filesystemID: UnsafePointer<fsid_t>,
    _ inode: UInt64
) -> Int

enum InodeProbe {
    private static let maxSeconds = 4.0
    private static let maxExamples = 12

    static func run() -> String {
        let home = NSHomeDirectory()
        var volume = statfs()
        var homeMetadata = stat()
        var report: [String] = [
            "TAKOPI FSGETPATH PROBE",
            "iOS: \(UIDevice.current.systemVersion)",
            "Modo: solo nombres; sin acceso al contenido",
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
        report.append("Control: inode del contenedor propio = \(ownID)")

        func resolve(_ identifier: UInt64) -> (String?, Int32) {
            var path = [CChar](repeating: 0, count: 2048)
            let length = withUnsafePointer(to: &fsid) { fsidPointer in
                path.withUnsafeMutableBufferPointer { bytes in
                    probe_fsgetpath(bytes.baseAddress!, bytes.count, fsidPointer, identifier)
                }
            }
            let errorCode = errno
            if length > 0 { return (String(cString: path), 0) }
            return (nil, errorCode)
        }

        let (ownPath, ownError) = resolve(ownID)
        if let ownPath {
            report.append("✅ Control positivo: \(ownPath)")
        } else {
            report.append("🔒 Control fallido: errno \(ownError)")
            report.append("No se continúa porque la propia API no resuelve nuestro contenedor.")
            return report.joined(separator: "\n")
        }

        let start = ProcessInfo.processInfo.systemUptime
        var visited = Set<UInt64>()
        var found: [String] = []
        var checked = 0
        var resolvedCount = 0

        func inspect(_ identifier: UInt64) {
            guard visited.insert(identifier).inserted else { return }
            let (resolved, _) = resolve(identifier)
            checked += 1
            guard let resolved else { return }
            resolvedCount += 1
            if found.count < maxExamples,
               resolved.hasPrefix("/private/var/") || resolved.hasPrefix("/var/") {
                found.append(resolved)
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

        report += [
            "",
            "Identificadores examinados: \(checked)",
            "Rutas resueltas: \(resolvedCount)",
            "Ejemplos (hasta \(maxExamples)):",
        ]
        if found.isEmpty { report.append("(ninguna ruta adicional detectada)") }
        report.append(contentsOf: found)
        report += [
            "",
            "AVISO: recuperar un nombre no significa poder leer su contenido.",
            "La enumeración está limitada a 4 segundos.",
            "No se leen, modifican ni envían archivos."
        ]
        return report.joined(separator: "\n")
    }
}
