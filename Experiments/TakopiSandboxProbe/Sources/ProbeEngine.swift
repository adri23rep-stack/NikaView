import Foundation
import Darwin
import UIKit

enum ProbeEngine {
    static func run() -> String {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let paths = [
            "/",
            "/Developer",
            "/System",
            "/private/var",
            "/Applications",
            "/Library",
            "/private/var/mobile/Containers/Data/Application",
            "/var/containers/Shared/SystemGroup",
            home,
            fm.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? home + "/Documents",
            fm.urls(for: .libraryDirectory, in: .userDomainMask).first?.path ?? home + "/Library"
        ]

        var result: [String] = [
            "TAKOPI SANDBOX PROBE",
            "iOS \(UIDevice.current.systemVersion)",
            "Equipo: \(UIDevice.current.model)",
            "Modo: SOLO LECTURA",
            "Sin exploits ni permisos especiales",
            ""
        ]

        for path in paths {
            var metadata = stat()
            let rc = path.withCString { lstat($0, &metadata) }
            if rc == 0 {
                let kind = (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) ? "directorio" : "otro"
                result.append("📍 \(path) [detectado: \(kind)]")
            } else {
                let code = errno
                result.append("📍 \(path) [lstat: error \(code)]")
            }

            do {
                let names = try fm.contentsOfDirectory(atPath: path)
                result.append("  ✅ listado permitido: \(names.count) entradas")
                for name in names.prefix(25) {
                    result.append("   • \(name)")
                }
                if names.count > 25 { result.append("  … \(names.count - 25) más") }
            } catch {
                let err = error as NSError
                result.append("  🔒 sin listado: \(err.domain) (\(err.code))")
            }
            result.append("")
        }

        result += [
            "INTERPRETACIÓN",
            "Detectar una ruta NO significa poder abrirla.",
            "Una carpeta vacía tampoco implica un fallo.",
            "Las restricciones del sandbox continúan activas.",
            "No se recopila ni envía información automáticamente."
        ]

        return result.joined(separator: "\n")
    }
}
