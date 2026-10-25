import SwiftUI

@main
struct TakopiSandboxProbeApp: App {
    var body: some Scene {
        WindowGroup {
            ProbeView()
        }
    }
}

struct ProbeView: View {
    @State private var report = "Prueba de solo lectura. No cambia archivos ni permisos."
    @State private var isRunning = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Diagnóstico iOS 27", systemImage: "externaldrive")
                        .font(.title2.bold())

                    Text("Comprueba qué rutas aparecen, cuáles se pueden listar y cuáles están bloqueadas. No intenta saltarse los permisos del sistema.")
                        .foregroundStyle(.secondary)

                    Button {
                        runProbe()
                    } label: {
                        Label(isRunning ? "Comprobando…" : "Iniciar barrido", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)

                    Button {
                        runInodeProbe()
                    } label: {
                        Label("Probar rutas por identificador", systemImage: "point.3.connected.trianglepath.dotted")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunning)

                    ShareLink(item: report) {
                        Label("Compartir resultado", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isRunning)

                    Text(report)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("Takopi Probe")
        }
    }

    private func runInodeProbe() {
        isRunning = true
        report = "Consultando solo nombres de rutas…"
        DispatchQueue.global(qos: .utility).async {
            let result = InodeProbe.run()
            DispatchQueue.main.async {
                report = result
                isRunning = false
            }
        }
    }

    private func runProbe() {
        isRunning = true
        report = "Analizando…"
        DispatchQueue.global(qos: .utility).async {
            let result = ProbeEngine.run()
            DispatchQueue.main.async {
                report = result
                isRunning = false
            }
        }
    }
}
