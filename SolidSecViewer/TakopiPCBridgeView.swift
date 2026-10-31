import SwiftUI

/// Visible progress for the separate Windows companion. Password stays on iPhone
/// during restores; original encrypted Vault blobs travel directly to the PC.
struct TakopiPCBridgeView: View {
    enum Operation: Identifiable {
        case backup, restore
        var id: Self { self }
    }
    @EnvironmentObject private var vault: PrivateVaultSession
    @Environment(\.dismiss) private var dismiss
    let operation: Operation

    @State private var host = ""
    @State private var code = ""
    @State private var password = ""
    @State private var busy = false
    @State private var completed = false
    @State private var fraction = 0.0
    @State private var current = ""
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(operation == .backup
                         ? "Envía los archivos cifrados directamente a Windows, sin crear un ZIP ni duplicar la bóveda en tu iPhone."
                         : "Recibe los archivos cifrados desde Windows. Takopi revisará la contraseña y su integridad antes de reemplazar tu bóveda.")
                        .font(.footnote)
                }
                Section("Takopi PC Bridge en Windows") {
                    TextField("IP de la PC, por ejemplo 192.168.1.10", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Código de 32 caracteres de la PC", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if operation == .restore {
                        SecureField("Contraseña original de Takopi Vault", text: $password)
                            .textContentType(.password)
                    }
                }
                Section {
                    if busy || completed {
                        ProgressView(value: fraction)
                        Text(current).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        begin()
                    } label: {
                        Label(operation == .backup ? "Iniciar respaldo a PC"
                              : "Restaurar desde PC",
                              systemImage: operation == .backup ? "desktopcomputer.and.arrow.down"
                              : "arrow.down.doc")
                    }
                    .disabled(busy || completed || host.isEmpty || code.isEmpty ||
                              (operation == .restore && password.isEmpty))
                } footer: {
                    Text("Usa la misma red Wi-Fi privada. Mantén Takopi abierto y el iPhone desbloqueado. No expongas el puerto 48933 a internet. En la restauración necesitarás espacio para los archivos recibidos.")
                }
            }
            .navigationTitle(operation == .backup ? "Respaldo directo a PC" : "Restaurar desde PC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }.disabled(busy)
                }
            }
            .alert("Takopi PC Bridge", isPresented: Binding(
                get: { notice != nil },
                set: { if !$0 { notice = nil } }
            )) {
                Button("Entendido") { notice = nil }
            } message: {
                Text(notice ?? "")
            }
        }
    }

    private func begin() {
        busy = true
        fraction = 0
        current = "Conectando con la PC…"
        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairingCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = password
        password = ""

        let callback: TakopiPCBridge.Progress = { value, file in
            DispatchQueue.main.async {
                self.fraction = value
                self.current = file
            }
        }

        Task {
            defer { busy = false }
            do {
                if operation == .backup {
                    try await vault.exportEncryptedPCBackup(
                        host: address, code: pairingCode, progress: callback
                    )
                    notice = "Copia enviada y verificada. Usa «Verificar copia» en Windows antes de borrar nada."
                } else {
                    try await vault.importEncryptedPCBackup(
                        host: address, code: pairingCode,
                        password: secret, progress: callback
                    )
                    notice = "Bóveda restaurada. Desbloquéala con tu contraseña. Face ID debe configurarse otra vez."
                }
                fraction = 1
                completed = true
            } catch {
                notice = error.localizedDescription
                current = "Transferencia no completada"
            }
        }
    }
}
