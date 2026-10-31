import Foundation
import Network
import CryptoKit

/// Transfers the existing encrypted Vault files directly over a local TCP stream.
/// No ZIP, plaintext, or second Vault-sized temporary file is created for backups.
/// Takopi PC Bridge listens on Windows; the iPhone only connects out to it.
enum TakopiPCBridge {
    enum BridgeError: LocalizedError {
        case invalidHost
        case invalidCode
        case disconnected
        case rejected(String)
        case invalidResponse
        case noSpace
        case changed

        var errorDescription: String? {
            switch self {
            case .invalidHost: return "Escribe la IP de tu PC (por ejemplo 192.168.1.10)."
            case .invalidCode: return "El código de la PC debe tener 32 caracteres hexadecimales."
            case .disconnected: return "Se perdió la conexión con la PC. No se confirmó la copia."
            case .rejected(let message): return "La PC rechazó la operación: " + message
            case .invalidResponse: return "La PC envió datos inválidos o incompatibles."
            case .noSpace: return "No hay espacio suficiente para restaurar la bóveda."
            case .changed: return "La bóveda cambió durante la transferencia. Repite la copia."
            }
        }
    }

    typealias Progress = @Sendable (Double, String) -> Void
    private static let port: UInt16 = 48933
    private static let bufferSize = 256 * 1024
    private static let maxManifest = 32 * 1024 * 1024
    private static let maxFiles = 100_000
    private static let maxBytes: Int64 = 500 * 1024 * 1024 * 1024
    private static let required = Set(["vault.json", "vault.backup.json",
                                       "index.ssv", "index.previous.ssv"])

    // Non-sensitive crash breadcrumb: if iOS kills the guest without throwing,
    // Takopi can show the last completed stage after relaunch.
    private static let phaseKey = "Takopi.PCBridge.backupPhase"
    private static let phaseTimeKey = "Takopi.PCBridge.backupPhaseTime"

    static var previousInterruptedStage: String? {
        guard let stage = UserDefaults.standard.string(forKey: phaseKey),
              let timestamp = UserDefaults.standard.object(forKey: phaseTimeKey) as? Date,
              Date().timeIntervalSince(timestamp) < 48 * 3600
        else { return nil }
        return stage
    }

    private static func notePhase(_ phase: String) {
        UserDefaults.standard.set(phase, forKey: phaseKey)
        UserDefaults.standard.set(Date(), forKey: phaseTimeKey)
    }

    private static func clearPhase() {
        UserDefaults.standard.removeObject(forKey: phaseKey)
        UserDefaults.standard.removeObject(forKey: phaseTimeKey)
    }

    private struct Ack: Codable {
        let ok: Bool
        let error: String?
    }

    /// Network framework delivers state callbacks on its own queue. This gate
    /// protects completion across callbacks and never resumes a continuation twice.
    private final class OpenGate: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private let continuation: CheckedContinuation<Void, Error>

        init(_ continuation: CheckedContinuation<Void, Error>) {
            self.continuation = continuation
        }

        func finish(_ result: Result<Void, Error>) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            lock.unlock()
            continuation.resume(with: result)
        }
    }

    private final class Socket {
        private let connection: NWConnection

        init(host: String) throws {
            let clean = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean.count <= 255,
                  !clean.contains("/"), !clean.contains(":"),
                  !clean.contains(" "), !clean.contains("?"),
                  let endpoint = NWEndpoint.Port(rawValue: TakopiPCBridge.port)
            else { throw BridgeError.invalidHost }
            connection = NWConnection(host: NWEndpoint.Host(clean),
                                      port: endpoint, using: .tcp)
        }

        func open() async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let gate = OpenGate(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        gate.finish(.success(()))
                    case .failed(let error):
                        gate.finish(.failure(error))
                    case .cancelled:
                        gate.finish(.failure(BridgeError.disconnected))
                    default: break
                    }
                }
                connection.start(queue: DispatchQueue(label: "takopi.pc.bridge.network"))
            }
        }

        func close() { connection.cancel() }

        func send(_ data: Data) async throws {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                })
            }
        }

        func read(_ size: Int) async throws -> Data {
            guard size >= 0 else { throw BridgeError.invalidResponse }
            var result = Data()
            while result.count < size {
                try Task.checkCancellation()
                let remaining = min(size - result.count, TakopiPCBridge.bufferSize)
                let chunk: Data = try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Data, Error>) in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) {
                        content, _, isComplete, error in
                        if let error { continuation.resume(throwing: error) }
                        else if let content, !content.isEmpty {
                            continuation.resume(returning: content)
                        } else if isComplete {
                            continuation.resume(throwing: BridgeError.disconnected)
                        } else {
                            continuation.resume(throwing: BridgeError.invalidResponse)
                        }
                    }
                }
                result.append(chunk)
            }
            return result
        }

        func sendFrame<T: Encodable>(_ value: T) async throws {
            let data = try JSONEncoder().encode(value)
            guard data.count <= TakopiPCBridge.maxManifest else {
                throw BridgeError.invalidResponse
            }
            var length = UInt32(data.count).bigEndian
            try await send(Data(bytes: &length, count: 4))
            try await send(data)
        }

        func readFrame<T: Decodable>(_ type: T.Type) async throws -> T {
            let lengthData = try await read(4)
            let size = lengthData.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard size > 0, size <= TakopiPCBridge.maxManifest else {
                throw BridgeError.invalidResponse
            }
            return try JSONDecoder().decode(type, from: await read(Int(size)))
        }

        func expectOK() async throws {
            let ack = try await readFrame(Ack.self)
            guard ack.ok else {
                throw BridgeError.rejected(ack.error ?? "Sin detalles")
            }
        }
    }

    private static func connect(host: String, code: String, operation: UInt8) async throws -> Socket {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count == 32, trimmed.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) else { throw BridgeError.invalidCode }
        var token = Data()
        let digits = Array(trimmed.utf8)
        for index in stride(from: 0, to: 32, by: 2) {
            let pair = String(decoding: digits[index..<(index + 2)], as: UTF8.self)
            guard let byte = UInt8(pair, radix: 16) else { throw BridgeError.invalidCode }
            token.append(byte)
        }
        let socket = try Socket(host: host)
        try await socket.open()
        var hello = Data("TKPC0001".utf8)
        hello.append(token)
        hello.append(operation)
        try await socket.send(hello)
        try await socket.expectOK()
        return socket
    }

    private static func validate(_ manifest: TakopiVaultBackup.Manifest) throws -> Int64 {
        guard manifest.format == "takopi-encrypted-vault", manifest.version == 1,
              manifest.files.count >= 4, manifest.files.count <= maxFiles
        else { throw BridgeError.invalidResponse }
        var unique = Set<String>()
        var total: Int64 = 0
        for item in manifest.files {
            guard TakopiVaultBackup.allowedPath(item.path),
                  unique.insert(item.path).inserted, item.size >= 0,
                  item.sha256.count == 64,
                  item.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
            else { throw BridgeError.invalidResponse }
            let next = total.addingReportingOverflow(item.size)
            guard !next.overflow, next.partialValue <= maxBytes else {
                throw BridgeError.invalidResponse
            }
            total = next.partialValue
        }
        guard required.isSubset(of: unique) else { throw BridgeError.invalidResponse }
        return total
    }

    static func backup(host: String, code: String, root: URL,
                       progress: @escaping Progress) async throws {
        // Hash originals BEFORE sending; the receiver independently hashes all
        // transferred bytes and will not publish a backup until they match.
        notePhase("Leyendo y verificando la bóveda")
        defer { clearPhase() }
        progress(0, "Revisando archivos cifrados…")
        let manifest = try TakopiVaultBackup.snapshot(from: root) { bytes in
            progress(0, "Verificando bóveda: \(bytes / (1024 * 1024)) MB revisados…")
        }
        let total = try validate(manifest)
        notePhase("Conectando con Windows")
        progress(0, "Conectando con la PC…")
        let socket = try await connect(host: host, code: code, operation: 66) // B
        defer { socket.close() }
        try await socket.sendFrame(manifest)
        try await socket.expectOK()

        notePhase("Transmitiendo archivos cifrados a Windows")
        var sent: Int64 = 0
        var lastReported: Int64 = 0
        for record in manifest.files {
            try Task.checkCancellation()
            let url = root.appendingPathComponent(record.path)
            let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true,
                  properties.fileSize.map(Int64.init) == record.size else {
                throw BridgeError.changed
            }
            let handle = try FileHandle(forReadingFrom: url)
            do {
                var remaining = record.size
                while remaining > 0 {
                    try Task.checkCancellation()
                    let data = try autoreleasepool {
                        try handle.read(upToCount: Int(min(Int64(bufferSize), remaining))) ?? Data()
                    }
                    guard !data.isEmpty else { throw BridgeError.changed }
                    try await socket.send(data)
                    remaining -= Int64(data.count)
                    sent += Int64(data.count)
                    if sent - lastReported >= 8 * 1024 * 1024 || remaining == 0 {
                        lastReported = sent
                        progress(total == 0 ? 1 : Double(sent) / Double(total), record.path)
                    }
                }
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            try await socket.expectOK()
        }

        notePhase("Validando el respaldo recibido")
        // The index/config must still describe the exact snapshot copied.
        for name in ["index.ssv", "vault.json"] {
            guard let item = manifest.files.first(where: { $0.path == name }),
                  try TakopiVaultBackup.digest(root.appendingPathComponent(name)) == item.sha256
            else { throw BridgeError.changed }
        }
        try await socket.sendFrame(["done": true])
        try await socket.expectOK()
        progress(1, "Copia completa y verificada en la PC")
    }

    /// Downloads directly into a separate restore stage, never a ZIP or a plaintext cache.
    /// The caller checks the Vault password and atomically publishes this stage.
    static func receiveRestore(host: String, code: String, liveVault: URL,
                               progress: @escaping Progress) async throws -> URL {
        let socket = try await connect(host: host, code: code, operation: 82) // R
        defer { socket.close() }
        let manifest = try await socket.readFrame(TakopiVaultBackup.Manifest.self)
        let total = try validate(manifest)
        let fm = FileManager.default
        let parent = liveVault.deletingLastPathComponent()
        // A newly installed Takopi may not have created Application Support yet.
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        if let space = try? parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, space > 0, total > space {
            throw BridgeError.noSpace
        }
        let stage = parent.appendingPathComponent(".TakopiVault-restore-pc-" +
                                UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        var success = false
        defer { if !success { try? fm.removeItem(at: stage) } }
        try await socket.sendFrame(Ack(ok: true, error: nil))
        var received: Int64 = 0
        var lastReported: Int64 = 0

        for record in manifest.files {
            try Task.checkCancellation()
            let destination = stage.appendingPathComponent(record.path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            guard fm.createFile(atPath: destination.path, contents: nil) else {
                throw BridgeError.invalidResponse
            }
            try PrivateVaultSession.applyProtection(to: destination)
            let handle = try FileHandle(forWritingTo: destination)
            var hash = SHA256()
            do {
                var remaining = record.size
                while remaining > 0 {
                    try Task.checkCancellation()
                    let part = try await socket.read(Int(min(Int64(bufferSize), remaining)))
                    try handle.write(contentsOf: part)
                    hash.update(data: part)
                    remaining -= Int64(part.count)
                    received += Int64(part.count)
                    if received - lastReported >= 8 * 1024 * 1024 || remaining == 0 {
                        lastReported = received
                        progress(total == 0 ? 1 : Double(received) / Double(total), record.path)
                    }
                }
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest == record.sha256 else {
                throw BridgeError.rejected("SHA-256 incorrecto en " + record.path)
            }
            try await socket.sendFrame(Ack(ok: true, error: nil))
        }
        let final = try await socket.readFrame(Ack.self)
        guard final.ok else { throw BridgeError.rejected(final.error ?? "Restauración incompleta") }
        try PrivateVaultSession.applyProtection(to: stage)
        success = true
        return stage
    }
}
