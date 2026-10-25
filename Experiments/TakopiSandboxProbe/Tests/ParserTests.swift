import Foundation

let sample = (0..<10122).map { "/private/var/mobile/Library/TestFolder/item-\($0)" }
let tree = GhostPathParser(paths: sample + [sample[0]])
precondition(tree.seen.count == 10122)
precondition(tree.children["/"] == ["/private"])
precondition(tree.search("item-10").count > 0)
precondition(tree.search("does-not-exist").isEmpty)
precondition(tree.visible(expanded: []).count == 1)
let expanded: Set<String> = ["/", "/private", "/private/var", "/private/var/mobile",
                              "/private/var/mobile/Library",
                              "/private/var/mobile/Library/TestFolder"]
precondition(tree.visible(expanded: expanded, limit: 1500).count == 1500)
precondition(tree.seen.contains(sample[4321]))
let legacy = "EJEMPLOS POR CATEGORÍA\n • /a/b\nPRUEBA DE PERMISOS\n/a: BLOQUEADO"
precondition(GhostPathParser(report: legacy).seen == ["/a/b"])
let imported = GhostPathParser(report: "/test/a\n/test/b\n")
precondition(imported.seen.count == 2)
print("9 Ghost Explorer checks passed")
