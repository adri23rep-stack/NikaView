import SwiftUI

struct GhostRowsView: View {
    let index: GhostPathParser
    @Binding var expanded: Set<String>
    @Binding var query: String
    @Binding var selected: GhostEntry?

    private var searching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var rows: [GhostEntry] {
        searching ? index.search(query, limit: 1500)
                  : index.visible(expanded: expanded, limit: 1500)
    }

    var body: some View {
        List {
            ForEach(rows) { node in
                HStack(spacing: 7) {
                    if !searching {
                        Color.clear
                            .frame(width: CGFloat(min(node.level, 9)) * 10, height: 1)
                    }
                    if node.hasChildren && !searching {
                        Button {
                            if expanded.contains(node.path) {
                                expanded.remove(node.path)
                            } else {
                                expanded.insert(node.path)
                            }
                        } label: {
                            Image(systemName: expanded.contains(node.path) ?
                                  "chevron.down" : "chevron.right")
                                .frame(width: 20)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Color.clear.frame(width: 20, height: 1)
                    }

                    Button {
                        selected = node
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: node.hasChildren ? "folder" : "doc.questionmark")
                                .foregroundStyle(node.observed ? .indigo : .gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(searching ? node.path : node.name)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if !node.observed {
                                    Text("Ruta intermedia inferida")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if rows.count == 1500 {
                Text("Solo se muestran 1500 filas. Usa Buscar para localizar otras.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "Buscar carpeta o ruta")
    }
}
