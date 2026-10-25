import Foundation
import Darwin
import UIKit

@_silgen_name("fsgetpath")
private func ghost_fsgetpath(
    _ buffer: UnsafeMutablePointer<CChar>,
    _ bufferSize: Int,
    _ filesystemID: UnsafePointer<fsid_t>,
    _ inode: UInt64
) -> Int

struct GhostScanSnapshot {
    let paths: [String]
    let checked: Int
    let resolved: Int
    let elapsed: TimeInterval
    let environment: String
    let error: String?

    static func failure(_ reason: String, environment: String) -> GhostScanSnapshot {
        GhostScanSnapshot(paths: [], checked: 0, resolved: 0, elapsed: 0,
                          environment: environment, error: reason)
    }
}

enum GhostScanner {
    static let maximumSeconds = 4.0
    static func capture() -> GhostScanSnapshot {
        let home = NSHomeDirectory()
        let environment = home.contains("/Documents/Data/Application/")
            ? "Posible LiveContainer" : "Contenedor directo"
        var volume = statfs()
        guard home.withCString({ statfs($0, &volume) }) == 0 else {
            return .failure("statfs errno \(errno)", environment: environment)
        }
        var ownMetadata = stat()
        guard home.withCString({ lstat($0, &ownMetadata) }) == 0 else {
            return .failure("lstat errno \(errno)", environment: environment)
        }
        var fsid = volume.f_fsid
        func resolve(_ inode: UInt64) -> String? {
            var data = [CChar](repeating: 0, count: 2048)
            let count = withUnsafePointer(to: &fsid) { pointer in
                data.withUnsafeMutableBufferPointer { buffer in
                    ghost_fsgetpath(buffer.baseAddress!, buffer.count, pointer, inode)
                }
            }
            guard count > 0 else { return nil }
            let path = String(cString: data)
            return path.hasPrefix("/") ? path : nil
        }
        let ownID = UInt64(ownMetadata.st_ino)
        guard resolve(ownID) != nil else {
            return .failure("La ruta propia no pudo resolverse.", environment: environment)
        }
        let start = ProcessInfo.processInfo.systemUptime
        var visited = Set<UInt64>()
        var unique = Set<String>()
        var checked = 0
        var resolved = 0
        func exceeded() -> Bool {
            ProcessInfo.processInfo.systemUptime - start >= maximumSeconds
                || unique.count >= 30000
        }
        func inspect(_ inode: UInt64) {
            guard visited.insert(inode).inserted else { return }
            checked += 1
            guard let path = resolve(inode) else { return }
            resolved += 1
            unique.insert(path)
        }
        for inode in UInt64(1)...UInt64(25000) {
            if checked % 128 == 0 && exceeded() { break }
            inspect(inode)
        }
        if !exceeded() {
            let lower = ownID > 350 ? ownID - 350 : 1
            let upper = ownID > UInt64.max - 350 ? UInt64.max : ownID + 350
            for inode in lower...upper {
                if checked % 128 == 0 && exceeded() { break }
                inspect(inode)
            }
        }
        return GhostScanSnapshot(paths: unique.sorted(), checked: checked,
                                 resolved: resolved,
                                 elapsed: ProcessInfo.processInfo.systemUptime - start,
                                 environment: environment, error: nil)
    }
}
