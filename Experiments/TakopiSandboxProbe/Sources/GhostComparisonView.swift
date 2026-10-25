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
    @State private var history: [GhostSavedSnapshot] = []
    @State private var historyError: String?
    @State private var deleteCandidate: GhostSavedSnapshot?
    @State private var confirmDeletion = false
    @State private var selectedSource = "TXT importado"
    private let historyStore = GhostSnapshotHistory()

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
                Text("Compara esta captura con una guardada en el iPhone o con otro TXT. Todo ocurre localmente.")
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

            Section("Historial privado en este iPhone") {
                Text("Solo se guarda una captura cuando presionas Guardar. Las rutas permanecen en la app, protegidas por iOS y excluidas de la copia de seguridad.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    saveCurrent()
                } label: {
                    Label("Guardar captura actual", systemImage: "internaldrive")
                }
                .disabled(current.seen.isEmpty || history.count >= GhostSnapshotHistory.maximumSnapshots)

                if history.isEmpty {
                    Text("Aún no hay capturas guardadas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(history) { record in
                    HStack(alignment: .center) {
                        Button {
                            select(record)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.createdAt, format: .dateTime.day().month().year().hour().minute())
                                    .foregroundStyle(.primary)
                                Text("\(record.numberOfPaths.formatted()) rutas · comparar")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button {
                            deleteCandidate = record
                            confirmDeletion = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Eliminar captura guardada")
                    }
                }

                if let historyError {
                    Text(historyError).font(.caption).foregroundStyle(.red)
                }
                Text("Máximo 8 capturas. Eliminar una no borra archivos del sistema.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let comparison {
                Section("Diferencias entre capturas") {
                    Text("Comparación con: \(selectedSource)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .onAppear(perform: refreshHistory)
        .confirmationDialog("¿Eliminar esta captura local?",
                            isPresented: $confirmDeletion,
                            titleVisibility: .visible) {
            Button("Eliminar captura", role: .destructive) {
                if let item = deleteCandidate { delete(item) }
                deleteCandidate = nil
            }
            Button("Cancelar", role: .cancel) {
                deleteCandidate = nil
            }
        }
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
                    selectedSource = "TXT importado"
                    errorText = nil
                } catch {
                    errorText = error.localizedDescription
                }
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
    }

    private func refreshHistory() {
        do {
            history = try historyStore.list()
            historyError = nil
        } catch {
            historyError = "No se pudo leer el historial: \(error.localizedDescription)"
        }
    }

    private func saveCurrent() {
        do {
            _ = try historyStore.save(paths: current.seen)
            refreshHistory()
        } catch {
            historyError = "No se pudo guardar: \(error.localizedDescription)"
        }
    }

    private func select(_ record: GhostSavedSnapshot) {
        let parser = GhostPathParser(paths: record.paths)
        baseline = parser
        comparison = GhostSnapshotDiff(previous: parser.seen, current: current.seen)
        selectedSource = record.createdAt.formatted(date: .abbreviated, time: .shortened)
        errorText = nil
    }

    private func delete(_ record: GhostSavedSnapshot) {
        do {
            try historyStore.delete(id: record.id)
            refreshHistory()
            if selectedSource == record.createdAt.formatted(date: .abbreviated, time: .shortened) {
                comparison = nil
                baseline = nil
                selectedSource = "TXT importado"
            }
        } catch {
            historyError = "No se pudo eliminar: \(error.localizedDescription)"
        }
    }
}
