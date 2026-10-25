import SwiftUI

struct GhostDetailsView: View {
    let entry: GhostEntry
    @State private var access = "Acceso sin comprobar"

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre de ruta") {
                    Text(entry.path)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    Text(entry.observed ? "Nombre observado" : "Ruta intermedia deducida")
                        .foregroundStyle(.secondary)
                    ShareLink(item: entry.path) {
                        Label("Copiar o compartir nombre", systemImage: "square.and.arrow.up")
                    }
                }
                Section("Permiso para listar una carpeta") {
                    Text(access)
                    Button("Comprobar permiso") {
                        do {
                            let names = try FileManager.default.contentsOfDirectory(atPath: entry.path)
                            access = "✅ Listado permitido: \(names.count) nombres (no mostrados)"
                        } catch {
                            let info = error as NSError
                            access = info.code == 257
                                ? "🔒 iOS bloquea el listado (257)"
                                : "No se pudo listar (error \(info.code))"
                        }
                    }
                    Text("No abre contenidos ni altera archivos o permisos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Detalles")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
