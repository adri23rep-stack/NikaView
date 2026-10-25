import Foundation

let temp = FileManager.default.temporaryDirectory
    .appendingPathComponent("takopi-history-test-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: temp) }

let store = GhostSnapshotHistory(directory: temp)
let initiallySaved = try store.list()
precondition(initiallySaved.isEmpty)

let first = try store.save(paths: [
    "/private/var/mobile/TestA",
    "/private/var/mobile/TestB",
    "/private/var/mobile/TestB"
], source: "Prueba local")
precondition(first.numberOfPaths == 2)
let afterFirst = try store.list()
precondition(afterFirst.count == 1)
precondition(afterFirst[0].paths == ["/private/var/mobile/TestA", "/private/var/mobile/TestB"])
precondition(afterFirst[0].source == "Prueba local")

try store.delete(id: first.id)
let afterDelete = try store.list()
precondition(afterDelete.isEmpty)

do {
    _ = try store.save(paths: [])
    preconditionFailure("empty snapshots must fail")
} catch GhostHistoryError.emptySnapshot {
    // Expected.
}

for i in 0..<GhostSnapshotHistory.maximumSnapshots {
    _ = try store.save(paths: ["/test/sample-\(i)"])
}
let atCapacity = try store.list()
precondition(atCapacity.count == GhostSnapshotHistory.maximumSnapshots)

do {
    _ = try store.save(paths: ["/test/overflow"])
    preconditionFailure("snapshot count cap failed")
} catch GhostHistoryError.tooManySnapshots {
    // Expected.
}

let oldest = atCapacity.last!
try store.delete(id: oldest.id)
let afterPrune = try store.list()
precondition(afterPrune.count == GhostSnapshotHistory.maximumSnapshots - 1)

let newRecord = try store.save(paths: ["/test/replacement"])
let afterReplacement = try store.list()
precondition(afterReplacement.contains { $0.id == newRecord.id })

// Guard against accidentally following user-controlled filenames.
try store.delete(id: UUID())
let finalRecords = try store.list()
precondition(finalRecords.count == GhostSnapshotHistory.maximumSnapshots)

print("12 protected local snapshot history checks passed")
