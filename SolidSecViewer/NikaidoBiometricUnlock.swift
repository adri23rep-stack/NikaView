import Foundation
@preconcurrency import LocalAuthentication
import Security

/// Cómo quiere el usuario desbloquear Takopi Vault.
/// - Primera vez: siempre contraseña.
/// - Después de entrar, la app pregunta una sola vez: Face ID o contraseña.
enum NikaidoUnlockMethod: String {
    case faceID
    case password
}

enum NikaidoBiometricLoadResult {
    case success(String)
    case cancelled
    case fallback
    case invalidated
    case failed(String)
}

enum NikaidoBiometricEnableResult {
    case enabled
    case unavailable
    case cancelled
    case storeFailed(OSStatus)

    var message: String {
        switch self {
        case .enabled:
            return ""
        case .unavailable:
            return "Face ID no está disponible para esta app. Revisa que Face ID esté activado en los Ajustes del iPhone y que la app tenga permiso. Seguirás usando tu contraseña."
        case .cancelled:
            return "Cancelaste Face ID. Seguirás usando tu contraseña."
        case .storeFailed(let status):
            let hint: String

            if status == errSecMissingEntitlement {
                hint = " El Llavero no está disponible para esta app en este entorno."
            } else if status == errSecParam {
                hint = " Confirma que el iPhone tenga un código de acceso activado."
            } else {
                hint = ""
            }

            return "iOS no permitió guardar la contraseña de forma segura (código \(status)).\(hint) Seguirás usando tu contraseña."
        }
    }
}

enum NikaidoUnlockPreference {
    private static let methodKey = "NikaidoVault.unlockMethod.v1"
    private static let service = "com.teamnikaido.solidsecviewer.vault-unlock"
    static let defaultAccount = "vault-password"
    private static let declinedKey = "NikaidoVault.faceIDOfferDeclined.v1"

    /// Si el usuario ya rechazó guardar la contraseña para Face ID, no se le
    /// vuelve a insistir cada vez que escribe su contraseña.
    static var faceIDOfferDeclined: Bool {
        get { UserDefaults.standard.bool(forKey: declinedKey) }
        set { UserDefaults.standard.set(newValue, forKey: declinedKey) }
    }

    static var method: NikaidoUnlockMethod? {
        get {
            UserDefaults.standard
                .string(forKey: methodKey)
                .flatMap(NikaidoUnlockMethod.init(rawValue:))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: methodKey)
            } else {
                UserDefaults.standard.removeObject(forKey: methodKey)
            }
        }
    }

    static var biometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
    }

    /// Confirma Face ID una vez y guarda la contraseña en el Keychain, cifrada
    /// por iOS y protegida por la biometría de este iPhone (solo en este
    /// dispositivo, no se sincroniza a iCloud). Nunca se guarda en texto plano
    /// fuera del Keychain.
    static func enableBiometric(
        password: String,
        account: String = defaultAccount
    ) async -> NikaidoBiometricEnableResult {
        guard biometricsAvailable else { return .unavailable }

        let confirmation: NikaidoBiometricEnableResult? = await withCheckedContinuation { continuation in
            let context = LAContext()
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Activar Face ID para Takopi Vault"
            ) { success, error in
                if success {
                    continuation.resume(returning: nil)
                    return
                }

                let code = (error as? LAError)?.code

                switch code {
                case .userCancel, .systemCancel, .appCancel, .userFallback:
                    continuation.resume(returning: .cancelled)
                default:
                    continuation.resume(returning: .unavailable)
                }
            }
        }

        if let confirmation { return confirmation }

        let status = await Task.detached(priority: .userInitiated) {
            storePassword(password, account: account)
        }.value

        return status == errSecSuccess ? .enabled : .storeFailed(status)
    }

    static func disableBiometric() {
        deleteStoredPassword()
        method = nil
    }

    /// Pide Face ID y, solo si tiene éxito, lee la contraseña guardada en el
    /// Keychain con ese mismo contexto ya autenticado (sin pedir otra vez).
    static func loadPassword(
        reason: String,
        account: String = defaultAccount
    ) async -> NikaidoBiometricLoadResult {
        let context = LAContext()
        context.localizedFallbackTitle = "Usar contraseña"

        let evaluation: NikaidoBiometricLoadResult? = await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, error in
                if success {
                    continuation.resume(returning: nil)
                    return
                }

                let code = (error as? LAError)?.code

                switch code {
                case .userCancel, .systemCancel, .appCancel:
                    continuation.resume(returning: .cancelled)
                case .userFallback:
                    continuation.resume(returning: .fallback)
                default:
                    continuation.resume(
                        returning: .failed("Face ID no pudo verificarte. Usa tu contraseña.")
                    )
                }
            }
        }

        if let evaluation { return evaluation }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                    kSecUseAuthenticationContext as String: context
                ]

                var item: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &item)

                switch status {
                case errSecSuccess:
                    if
                        let data = item as? Data,
                        let text = String(data: data, encoding: .utf8),
                        !text.isEmpty
                    {
                        continuation.resume(returning: .success(text))
                    } else {
                        continuation.resume(returning: .invalidated)
                    }
                case errSecUserCanceled:
                    continuation.resume(returning: .cancelled)
                case errSecItemNotFound:
                    continuation.resume(returning: .invalidated)
                default:
                    continuation.resume(
                        returning: .failed("Face ID no respondió (código \(status)). Usa tu contraseña.")
                    )
                }
            }
        }
    }

    private static func storePassword(_ password: String, account: String) -> OSStatus {
        deleteStoredPassword(account: account)

        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &accessError
        ) else {
            return errSecParam
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: Data(password.utf8)
        ]

        return SecItemAdd(query as CFDictionary, nil)
    }

    static func deleteStoredPassword(account: String = defaultAccount) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}


// MARK: - Autenticación al abrir archivos de la bóveda

enum NikaidoFileAuthResult {
    case success
    case cancelled
    case needsPassword
}

/// Segunda barrera al abrir contenido de la bóveda: Face ID o, si no está
/// disponible, la contraseña de la bóveda. Nada se descifra para mostrarse
/// hasta que esta verificación tenga éxito.
enum NikaidoFileAuth {
    private static let requireKey = "NikaidoVault.requireFileAuth.v1"
    private static let graceKey = "NikaidoVault.fileAuthGraceSeconds.v1"
    private static var lastSuccess: Date?

    static var isRequired: Bool {
        UserDefaults.standard.object(forKey: requireKey) as? Bool ?? true
    }

    static var graceSeconds: Int {
        UserDefaults.standard.integer(forKey: graceKey)
    }

    static var isWithinGrace: Bool {
        guard graceSeconds > 0, let lastSuccess else { return false }
        return Date().timeIntervalSince(lastSuccess) < Double(graceSeconds)
    }

    static func markAuthenticated() {
        lastSuccess = Date()
    }

    static func reset() {
        lastSuccess = nil
    }

    static func authenticate(reason: String) async -> NikaidoFileAuthResult {
        guard
            NikaidoUnlockPreference.method == .faceID,
            NikaidoUnlockPreference.biometricsAvailable
        else {
            return .needsPassword
        }

        let context = LAContext()
        context.localizedFallbackTitle = "Usar contraseña"

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, error in
                if success {
                    continuation.resume(returning: .success)
                    return
                }

                let code = (error as? LAError)?.code

                switch code {
                case .userCancel, .systemCancel, .appCancel:
                    continuation.resume(returning: .cancelled)
                default:
                    continuation.resume(returning: .needsPassword)
                }
            }
        }
    }
}


// MARK: - Face ID por colección .sec

/// Qué colecciones .sec de la bóveda ya tienen su contraseña guardada para
/// usar Face ID. La contraseña vive solo en el Llavero (cifrada por iOS).
enum NikaidoSecFaceID {
    private static let storeKey = "NikaidoVault.secFaceIDFolders.v1"

    static func account(for id: UUID) -> String {
        "sec-\(id.uuidString)"
    }

    static func isEnabled(_ id: UUID) -> Bool {
        stored().contains(id.uuidString)
    }

    static func enable(_ id: UUID) {
        var all = stored()
        all.insert(id.uuidString)
        UserDefaults.standard.set(Array(all), forKey: storeKey)
    }

    static func disable(_ id: UUID) {
        var all = stored()
        all.remove(id.uuidString)
        UserDefaults.standard.set(Array(all), forKey: storeKey)
        NikaidoUnlockPreference.deleteStoredPassword(account: account(for: id))
    }

    private static func stored() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: storeKey) ?? [])
    }
}

