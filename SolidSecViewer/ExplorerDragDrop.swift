import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Tipo propio de Takopi Explorer. Ya no se usa para arrastrar porque un
    /// tipo personalizado no se registra cuando la app corre dentro de
    /// LiveContainer; se conserva declarado en Info.plist por compatibilidad.
    static let nikaidoExplorerItems = UTType(exportedAs: "com.teamnikaido.explorer-items")
}

struct ExplorerDragPayload: Codable {
    let urls: [String]
    let sourcePane: Int

    private static let marker = "nikaido-explorer-items"
    private static let lock = NSLock()
    private static var currentToken: String?
    private static var currentPayload: ExplorerDragPayload?

    /// El arrastre viaja como texto simple (tipo del sistema) con un código de
    /// un solo uso. Los datos reales se guardan en memoria, así funciona igual
    /// con o sin tipos personalizados registrados.
    func itemProvider() -> NSItemProvider {
        let token = UUID().uuidString

        Self.lock.lock()
        Self.currentToken = token
        Self.currentPayload = self
        Self.lock.unlock()

        return NSItemProvider(
            object: (Self.marker + ":" + token) as NSString
        )
    }

    static func load(from providers: [NSItemProvider]) async throws -> ExplorerDragPayload {
        guard let provider = providers.first(where: {
            $0.canLoadObject(ofClass: NSString.self)
        }) else {
            throw ExplorerOperationError.operationFailed("El elemento arrastrado no pertenece a Takopi Explorer.")
        }

        let text: String = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let value = object as? NSString else {
                    continuation.resume(
                        throwing: ExplorerOperationError.operationFailed("No se pudo leer el arrastre.")
                    )
                    return
                }

                continuation.resume(returning: value as String)
            }
        }

        let prefix = marker + ":"

        guard text.hasPrefix(prefix) else {
            throw ExplorerOperationError.operationFailed("El elemento arrastrado no pertenece a Takopi Explorer.")
        }

        let token = String(text.dropFirst(prefix.count))

        // NSLock.lock()/unlock() are unavailable directly from an async
        // context under the Swift 6 concurrency checks used by Xcode 16.4.
        // Keep the critical section synchronous and scoped instead.
        let payload = lock.withLock {
            (currentToken == token) ? currentPayload : nil
        }

        guard let payload else {
            throw ExplorerOperationError.operationFailed("El arrastre ya no es válido. Inténtalo de nuevo.")
        }

        return payload
    }
}

