import SwiftUI

struct GhostInsightsView: View {
    let index: GhostPathParser

    private var insights: GhostInsights {
        GhostInsights(paths: Array(index.seen))
    }

    var body: some View {
        List {
            Section("Resultados") {
                LabeledContent("Rutas diferentes", value: insights.total.formatted())
                LabeledContent("Sin extensión", value: insights.unknownKind.formatted())
                Text("Una ruta sin extensión puede ser carpeta o archivo. No podemos saberlo solo por su nombre.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Explorar por área") {
                ForEach(insights.areas) { bucket in
                    NavigationLink {
                        GhostCategoryView(paths: insights.filtered(index.seen, area: bucket.name),
                                          name: bucket.name)
                    } label: {
                        HStack {
                            Text(bucket.name)
                            Spacer()
                            Text(bucket.count.formatted()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Extensiones más frecuentes") {
                ForEach(Array(insights.suffixes.prefix(18))) { bucket in
                    LabeledContent(bucket.name, value: bucket.count.formatted())
                }
            }
            Section("Privacidad") {
                ShareLink(item: insights.summary) {
                    Label("Compartir solo resumen anónimo", systemImage: "square.and.arrow.up")
                }
                Text("El resumen no incluye rutas, nombres propios ni identificadores. El archivo TXT completo sí puede contener datos privados.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Resumen del barrido")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GhostCategoryView: View {
    let name: String
    private let parser: GhostPathParser
    @State private var expanded: Set<String> = ["/", "/private", "/private/var", "/private/var/mobile",
                                                   "/private/var/mobile/Containers",
                                                   "/private/var/mobile/Containers/Data"]
    @State private var query = ""
    @State private var selected: GhostEntry?

    init(paths: [String], name: String) {
        self.name = name
        parser = GhostPathParser(paths: paths)
    }

    var body: some View {
        GhostRowsView(index: parser, expanded: $expanded,
                      query: $query, selected: $selected)
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selected) { item in
                GhostDetailsView(entry: item)
                    .presentationDetents([.medium, .large])
            }
    }
}
