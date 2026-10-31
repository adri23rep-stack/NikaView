import SwiftUI
import VisionKit

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
    @State private var showQRScanner = false
    @State private var interruptedStage: String?

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
                    Button {
                        guard Bundle.main.object(
                            forInfoDictionaryKey: "NSCameraUsageDescription"
                        ) != nil else {
                            notice = "Este contenedor de iOS no declaró permiso de cámara. Introduce la IP y el código manualmente o actualiza LiveContainer."
                            return
                        }
                        guard DataScannerViewController.isSupported,
                              DataScannerViewController.isAvailable else {
                            notice = "El lector QR no está disponible. Puedes introducir la IP y el código manualmente."
                            return
                        }
                        showQRScanner = true
                    } label: {
                        Label("Escanear QR de Windows", systemImage: "qrcode.viewfinder")
                    }
                    .disabled(busy)

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
                if let interruptedStage {
                    Section("Diagnóstico del respaldo anterior") {
                        Text("Última etapa registrada: \(interruptedStage)")
                            .font(.footnote)
                        Text("Si Takopi se cerró inesperadamente, este dato ayuda a encontrar el punto del fallo. No se borró la bóveda por iniciar el respaldo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            .sheet(isPresented: $showQRScanner) {
                NavigationStack {
                    TakopiPCPairingScanner { payload in
                        showQRScanner = false
                        do {
                            let pair = try TakopiPCPairing.parse(payload, operation: operation)
                            host = pair.host
                            code = pair.code
                        } catch {
                            notice = error.localizedDescription
                        }
                    }
                    .navigationTitle("Escanear QR de tu PC")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Cancelar") { showQRScanner = false }
                        }
                    }
                }
            }
            .onAppear {
                interruptedStage = TakopiPCBridge.previousInterruptedStage
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
        interruptedStage = nil
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


/// QR-only pairing: the code includes the Windows LAN address and one-time token.
/// Scanning NEVER starts a transfer; the user confirms with the existing button.
private enum TakopiPCPairing {
    struct Pair {
        let host: String
        let code: String
    }

    enum PairError: LocalizedError {
        case invalid
        case wrongMode
        var errorDescription: String? {
            switch self {
            case .invalid: return "Este QR no pertenece a Takopi PC Bridge o está incompleto."
            case .wrongMode: return "El QR pertenece a otra operación (respaldo o restauración). Inicia la misma operación en Windows."
            }
        }
    }

    static func parse(_ payload: String,
                      operation: TakopiPCBridgeView.Operation) throws -> Pair {
        guard let url = URLComponents(string: payload),
              url.scheme == "takopi-pc", url.host == "pair",
              url.path.isEmpty, url.fragment == nil,
              let items = url.queryItems, items.count == 5
        else { throw PairError.invalid }
        var fields: [String: String] = [:]
        for item in items {
            guard fields[item.name] == nil, let value = item.value else {
                throw PairError.invalid
            }
            fields[item.name] = value
        }
        guard Set(fields.keys) == Set(["v", "host", "port", "code", "mode"]),
              fields["v"] == "1", fields["port"] == "48933",
              let host = fields["host"], host.count <= 15,
              let code = fields["code"], code.utf8.count == 32,
              code.utf8.allSatisfy({
                  (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
              })
        else { throw PairError.invalid }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, octets.allSatisfy({
            !$0.isEmpty && $0.count <= 3 &&
            $0.allSatisfy({ $0 >= "0" && $0 <= "9" }) &&
            UInt8($0) != nil
        }) else { throw PairError.invalid }
        let expectedMode = operation == .backup ? "B" : "R"
        guard fields["mode"] == expectedMode else { throw PairError.wrongMode }
        return Pair(host: host, code: code)
    }
}

private struct TakopiPCPairingScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        DispatchQueue.main.async {
            try? scanner.startScanning()
        }
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController,
                                          coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var finished = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !finished else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let text = barcode.payloadStringValue {
                    finished = true
                    dataScanner.stopScanning()
                    onScan(text)
                    break
                }
            }
        }
    }
}
