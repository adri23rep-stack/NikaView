import Foundation

let previous = Set([
    "/private/var/mobile/Containers/Data/Application/old/Documents",
    "/private/var/mobile/Library/Safari",
    "/private/var/mobile/Library/Preferences/com.example.plist",
    "/private/var/mobile/Library/Cache"
])
let current = Set([
    "/private/var/mobile/Library/Safari",
    "/private/var/mobile/Library/Preferences/com.example.plist",
    "/private/var/mobile/Containers/Data/Application/new/Documents"
])
let diff = GhostSnapshotDiff(previous: previous, current: current)
precondition(diff.previousTotal == 4)
precondition(diff.currentTotal == 3)
precondition(diff.shared == 2)
precondition(diff.appeared.count == 1)
precondition(diff.noLongerObserved.count == 2)
precondition(diff.appeared[0].hasSuffix("new/Documents"))
precondition(diff.matching(diff.noLongerObserved, query: "Application").count == 1)
precondition(diff.matching(diff.appeared, query: "unknown").isEmpty)
precondition(!diff.safeSummary.contains("com.example"))
precondition(!diff.safeSummary.contains("old/Documents"))
precondition(diff.counts.reduce(0) { $0 + $1.appeared } == 1)
precondition(diff.counts.reduce(0) { $0 + $1.notObserved } == 2)
let giant = Set((0..<10122).map { "/private/var/mobile/Library/folder/\($0)" })
let stable = GhostSnapshotDiff(previous: giant, current: giant)
precondition(stable.appeared.isEmpty)
precondition(stable.noLongerObserved.isEmpty)
precondition(stable.shared == 10122)
print("15 snapshot comparison checks passed")
