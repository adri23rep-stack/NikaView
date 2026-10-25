import SwiftUI
import UniformTypeIdentifiers

struct GhostComparisonView: View {
    let current: GhostPathParser
    @State private var baseline: GhostPathParser?
    @State private var comparison: GhostSnapshotDiff?
    @State private var importing = false
    @State private var errorText: String?
    @State private var query = ""
    @State private var selection = 0

    private var selectedPaths: [String] {
        guard let comparison else { return [] }
        return comparison.matching(
            selection == 0 ? comparison.appeared : comparison.noLongerObserved,
            query: query,
            limit: 250
        )
    }

    var body: some View {
        List {
            Section {
                Text("Compara este barrido con otro TXT exportado desde Takopi Ghost. Todo ocurre en el iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LabeledContent("Captura actual", value: current.seen.count.formatted())
                Button {
                    importing = true
                } label: {
                    Label("Seleccionar captura anterior", systemImage: "doc.badge.plus")
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                }
            }

            if let comparison {
                Section("Diferencias entre capturas") {
                    LabeledContent("Rutas anteriores", value: comparison.previousTotal.formatted())
                    LabeledContent("Rutas actuales", value: comparison.currentTotal.formatted())
                    LabeledContent("Coinciden", value: comparison.shared.formatted())
                    LabeledContent("Solo en la actual", value: comparison.appeared.count.formatted())
                    LabeledContent("No detectadas esta vez",
                                   value: comparison.noLongerObserved.count.formatted())
                    Text("Que una ruta no aparezca NO significa que haya sido borrada. El escaneo cubre solo una parte del sistema.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Cambios por área") {
                    ForEach(comparison.counts) { bucket in
                        HStack {
                            Text(bucket.area)
                                .lineLimit(2)
                            Spacer()
                            Text("+\(bucket.appeared) / −\(bucket.notObserved)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Section {
                    Picker("Tipo de diferencia", selection: $selection) {
                        Text("Solo actuales").tag(0)
                        Text("No observadas").tag(1)
                    }
                    .pickerStyle(.segmented)

                    ForEach(selectedPaths, id: \.self) { path in
                        Text(path)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    let selectedCount = selection == 0
                        ? comparison.appeared.count
                        : comparison.noLongerObserved.count
                    if selectedCount > 250 {
                        Text("Mostrando hasta 250 rutas. Usa la búsqueda para filtrar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Nombres diferentes")
                } footer: {
                    Text("Los identificadores y nombres pueden ser privados. No compartas capturas completas sin revisarlas.")
                }

                Section {
                    ShareLink(item: comparison.safeSummary) {
                        Label("Compartir resumen sin rutas", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Buscar entre los cambios")
        .navigationTitle("Comparar barridos")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText]) { result in
            switch result {
            case .success(let url):
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    let parsed = GhostPathParser(report: text)
                    guard !parsed.seen.isEmpty else {
                        errorText = "El TXT no contiene rutas válidas."
                        return
                    }
                    baseline = parsed
                    comparison = GhostSnapshotDiff(previous: parsed.seen, current: current.seen)
                    errorText = nil
                } catch {
                    errorText = error.localizedDescription
                }
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
    }
}
