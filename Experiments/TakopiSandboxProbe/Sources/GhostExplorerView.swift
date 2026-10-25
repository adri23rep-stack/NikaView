import SwiftUI
import UniformTypeIdentifiers

struct GhostExplorerView: View {
    @State private var index = GhostPathParser(paths: [])
    @State private var expanded: Set<String> = ["/", "/private", "/private/var", "/private/var/mobile"]
    @State private var query = ""
    @State private var busy = false
    @State private var scanned = false
    @State private var importVisible = false
    @State private var error: String?
    @State private var selected: GhostEntry?
    @State private var stats = ""
    @State private var exportText = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 11) {
                Label("Explorador fantasma", systemImage: "eye")
                    .font(.title2.bold())
                Text("Árbol de nombres de rutas, no acceso a archivos protegidos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(action: scan) {
                    Label(busy ? "Explorando…" : "Explorar rutas", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)

                HStack(spacing: 10) {
                    Button {
                        importVisible = true
                    } label: {
                        Label("Importar TXT", systemImage: "doc.badge.plus")
                    }
                    .disabled(busy)
                    if scanned {
                        ShareLink(item: exportText) {
                            Label("Exportar nombres", systemImage: "square.and.arrow.up")
                        }
                        .disabled(exportText.isEmpty)
                    }
                }
                .buttonStyle(.bordered)

                if scanned {
                    NavigationLink {
                        GhostInsightsView(index: index)
                    } label: {
                        Label("Resumen y categorías", systemImage: "chart.bar.xaxis")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    NavigationLink {
                        GhostComparisonView(current: index)
                    } label: {
                        Label("Comparar dos barridos", systemImage: "arrow.left.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Text("\(index.seen.count.formatted()) rutas únicas · \(stats)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Vista parcial del volumen. Los padres inferidos no son prueba de acceso.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding()

            if scanned && !index.seen.isEmpty {
                GhostRowsView(index: index, expanded: $expanded,
                              query: $query, selected: $selected)
            } else {
                ContentUnavailableView(
                    "Sin rutas exploradas", systemImage: "folder.badge.questionmark",
                    description: Text("Pulsa Explorar rutas para visualizar los nombres que iOS permite detectar.")
                )
            }
        }
        .navigationTitle("Takopi Ghost 0.8")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { item in
            GhostDetailsView(entry: item)
                .presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $importVisible, allowedContentTypes: [.plainText]) { result in
            switch result {
            case .success(let url):
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    accept(GhostPathParser(report: text), stats: "TXT importado")
                } catch {
                    self.error = "No se pudo importar: \(error.localizedDescription)"
                }
            case .failure(let problem):
                error = problem.localizedDescription
            }
        }
    }

    private func accept(_ newIndex: GhostPathParser, stats: String) {
        index = newIndex
        self.stats = stats
        scanned = true
        busy = false
        error = newIndex.seen.isEmpty ? "No se detectaron rutas válidas." : nil
        exportText = (["TAKOPI GHOST 0.8",
                       "Solo nombres; no se pueden leer archivos protegidos.",
                       ""] + newIndex.seen.sorted()).joined(separator: "\n")
    }

    private func scan() {
        busy = true
        error = nil
        DispatchQueue.global(qos: .utility).async {
            let scan = GhostScanner.capture()
            let parsed = GhostPathParser(paths: scan.paths)
            DispatchQueue.main.async {
                let summary = "\(scan.resolved) resoluciones · \(scan.checked) intentos · \(scan.elapsed.formatted(.number.precision(.fractionLength(1)))) s · \(scan.environment)"
                accept(parsed, stats: summary)
                if let failure = scan.error { error = failure }
            }
        }
    }
}
