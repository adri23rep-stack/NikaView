import Foundation
import ZIPFoundation

/// Read-only inspection. Does not load/execute a binary or extract archive data.
enum NikaidoBinaryInspector {
    nonisolated static func report(url: URL, mappedData data: Data) -> String? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "ipa", "apk", "zip": return inspectZIP(url)
        case "deb": return inspectDeb(data)
        case "dylib", "so", "a", "framework", "app": return inspectMachO(data)
        default: return inspectMachO(data)
        }
    }

    nonisolated private static func inspectZIP(_ url: URL) -> String {
        do {
            let archive = try ZIPFoundation.Archive(url: url, accessMode: .read)
            var sample: [String] = []
            var total = 0
            var frameworks = 0
            var app: String?
            for entry in archive {
                total += 1
                if entry.path.contains(".framework/") { frameworks += 1 }
                if app == nil && entry.path.hasPrefix("Payload/") && entry.path.contains(".app/") {
                    let components = entry.path.split(separator: "/")
                    if components.count >= 2 { app = String(components[1]) }
                }
                if sample.count < 40 {
                    sample.append("• \(String(entry.path.prefix(125))) (\(entry.uncompressedSize) B)")
                }
                guard total <= 25_000 else { break }
            }
            return "Entradas de ZIP: \(total)\nAplicación: \(app ?? "No encontrada")\nArchivos en frameworks: \(frameworks)\n\nMuestra (40):\n" + sample.joined(separator: "\n")
        } catch {
            return "No se pudo abrir el ZIP en modo lectura: \(error.localizedDescription)"
        }
    }

    nonisolated private static func inspectDeb(_ data: Data) -> String {
        guard data.starts(with: Array("!<arch>\n".utf8)) else {
            return "Cabecera ar/DEB no reconocida."
        }
        var index = 8
        var entries: [String] = []
        for _ in 0..<60 {
            guard index <= data.count - 60 else { break }
            let hdr = Array(data[index..<(index+60)])
            let name = String(decoding: hdr[0..<16], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let sizeText = String(decoding: hdr[48..<58], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard hdr[58] == 0x60, hdr[59] == 0x0A,
                  let size = Int(sizeText), size >= 0,
                  size <= data.count - (index + 60) else { break }
            entries.append("• \(name) (\(size) B)")
            index += 60 + size + (size % 2)
        }
        return "DEB/ar: \(entries.count) miembros identificados (máx. 60)\n" + entries.joined(separator: "\n")
    }

    nonisolated private static func read32(_ data: Data, _ index: Int, big: Bool) -> UInt32? {
        guard index >= 0, index <= data.count - 4 else { return nil }
        var result: UInt32 = 0
        if big {
            for i in 0..<4 { result = (result << 8) | UInt32(data[data.startIndex + index + i]) }
        } else {
            for i in (0..<4).reversed() { result = (result << 8) | UInt32(data[data.startIndex + index + i]) }
        }
        return result
    }

    nonisolated private static func architecture(_ cpu: UInt32) -> String {
        switch cpu {
        case 0x0100000c: return "ARM64"
        case 0x01000007: return "x86_64"
        case 0x0000000c: return "ARMv7"
        case 0x00000007: return "x86"
        default: return String(format: "CPU 0x%08X", cpu)
        }
    }

    nonisolated private static func inspectMachO(_ data: Data) -> String? {
        let magic = Array(data.prefix(4))
        var big = false
        let is64: Bool
        switch magic {
        case [0xcf, 0xfa, 0xed, 0xfe]: is64 = true
        case [0xce, 0xfa, 0xed, 0xfe]: is64 = false
        case [0xfe, 0xed, 0xfa, 0xcf]: is64 = true; big = true
        case [0xfe, 0xed, 0xfa, 0xce]: is64 = false; big = true
        case [0xca, 0xfe, 0xba, 0xbe], [0xbe, 0xba, 0xfe, 0xca]:
            let fatBig = magic == [0xca, 0xfe, 0xba, 0xbe]
            guard let count = read32(data, 4, big: fatBig) else { return nil }
            var arch: [String] = []
            for n in 0..<min(Int(count), 24) {
                guard let cpu = read32(data, 8 + n*20, big: fatBig) else { break }
                arch.append(architecture(cpu))
            }
            return "Mach-O universal (Fat): \(count) arquitecturas\n" + arch.joined(separator: " · ")
        default: return nil
        }

        guard let cpu = read32(data, 4, big: big),
              let commandCount = read32(data, 16, big: big),
              let commandsSize = read32(data, 20, big: big) else { return nil }
        let headerSize = is64 ? 32 : 28
        guard commandCount <= 512,
              Int(commandsSize) <= 4_000_000,
              headerSize <= data.count - Int(commandsSize) else {
            return "Mach-O: comandos fuera de los límites permitidos."
        }
        var lines = ["Mach-O \(is64 ? "64-bit" : "32-bit") · \(architecture(cpu))",
                     "Comandos: \(commandCount)"]
        var cursor = headerSize
        var deps: [String] = []
        var signature = false
        var encrypted = false
        for _ in 0..<Int(commandCount) {
            guard let command = read32(data, cursor, big: big),
                  let length = read32(data, cursor+4, big: big),
                  length >= 8, Int(length) <= data.count - cursor else { break }
            let stripped = command & 0x7FFF_FFFF
            if stripped == 0x0c || stripped == 0x18 || stripped == 0x1f || stripped == 0x23 {
                if let offset = read32(data, cursor+8, big: big),
                   offset >= 8, Int(offset) < Int(length) {
                    let from = cursor + Int(offset)
                    let end = min(cursor + Int(length), from + 260)
                    let name = data[from..<end].prefix(while: { $0 != 0 })
                    deps.append(String(decoding: name, as: UTF8.self))
                }
            }
            if stripped == 0x1d { signature = true }
            if stripped == 0x21 || stripped == 0x2c {
                let offset = stripped == 0x2c ? 16 : 16
                if let cryptID = read32(data, cursor + offset, big: big), cryptID > 0 {
                    encrypted = true
                }
            }
            cursor += Int(length)
        }
        lines.append("Firma incluida: \(signature ? "sí (sin verificar)" : "no encontrada")")
        lines.append("Marcador de cifrado Mach-O: \(encrypted ? "sí" : "no")")
        if !deps.isEmpty {
            lines.append("Dependencias de biblioteca:\n" + deps.prefix(40).map { "• " + $0 }.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }
}
