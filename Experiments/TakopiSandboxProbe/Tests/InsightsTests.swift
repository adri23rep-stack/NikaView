import Foundation

let paths = [
    "/private/var/mobile/Containers/Data/PluginKitPlugin/one/Library/Preferences/a.plist",
    "/private/var/mobile/Containers/Data/Application/two/Documents/photo.heic",
    "/private/var/mobile/Library/Safari/history.db",
    "/private/var/mobile/Containers/Shared/AppGroup/three/Library/note.sqlite",
    "/private/var/mobile/Containers/Data/InternalDaemon/four/tmp",
    "/private/var/mobile/Media",
    "/private/var/mobile/Media"
]
let results = GhostInsights(paths: paths)
precondition(results.total == 6)
precondition(results.areas.reduce(0) { $0 + $1.count } == 6)
precondition(results.unknownKind == 2)
precondition(results.suffixes.contains { $0.name == ".plist" && $0.count == 1 })
precondition(results.filtered(Set(paths), area: "Aplicaciones").count == 1)
precondition(results.filtered(Set(paths), area: "Todas").count == 6)
precondition(!results.summary.contains("photo.heic"))
precondition(!results.summary.contains("/private/"))
print("8 Ghost Insights checks passed")
