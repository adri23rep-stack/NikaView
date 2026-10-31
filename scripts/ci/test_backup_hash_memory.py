"""Run the production hash loop on macOS against a sparse 512 MiB blob.

Extract the method verbatim to avoid linking UIKit/ZIPFoundation in this focused
regression test. The actual iOS target is compiled separately by the workflow.
"""
import hashlib
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'SolidSecViewer/TakopiVaultBackup.swift').read_text()
method = source[source.index('    static func digest('):source.rfind('\n}')]
method += "\n" + source[source.index('    struct InventoryItem'):source.index('    static func snapshot(')]
method += "\n" + source[source.index('    static func allowedPath('):source.index('    static func digest(')]
method += """
    enum BackupError: Error { case invalidPackage, tooManyEntries, missingEncryptedFile }
    static let maxFiles = 100_000
    static let maxTotalBytes: Int64 = 500 * 1024 * 1024 * 1024
    static let configFiles: Set<String> = ["vault.json", "vault.backup.json", "index.ssv", "index.previous.ssv"]
"""
size = 512 * 1024 * 1024
expected = hashlib.sha256()
for _ in range(512):
    expected.update(bytes(1024 * 1024))

with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    blob = work / 'large.ssvb'
    with blob.open('wb') as file:
        file.truncate(size)
    swift = work / 'HashMemory.swift'
    swift.write_text('import Foundation\nimport CryptoKit\nenum Production {\n' + method + '\n}\n' + r'''
@main struct HashMemory {
    static func main() async throws {
        let path = CommandLine.arguments[1]
        let expected = CommandLine.arguments[2]
        try await Task.detached {
            var last: Int64 = 0
            var reports = 0
            let digest = try Production.digest(URL(fileURLWithPath: path)) { count in
                precondition(count >= last)
                last = count
                reports += 1
            }
            precondition(digest == expected, "Ciphertext checksum changed")
            precondition(last == 512 * 1024 * 1024 && reports >= 16)
            enum Stop: Error { case checkpoint }
            do {
                _ = try Production.digest(URL(fileURLWithPath: path)) { _ in
                    throw Stop.checkpoint
                }
                preconditionFailure("A failed diagnostic write must stop hashing")
            } catch Stop.checkpoint {}
            let root = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("vault")
            let fm = FileManager.default
            for folder in ["blobs", "thumbnails"] {
                try fm.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
            for name in Production.configFiles {
                try Data([1, 2, 3]).write(to: root.appendingPathComponent(name))
            }
            let blob = root.appendingPathComponent("blobs/00000000-0000-0000-0000-000000000001.ssvb")
            try Data([4, 5, 6]).write(to: blob)
            try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: blob.path)
            var checkpoints = [String]()
            let items = try Production.inventory(from: root) { checkpoints.append($0) }
            precondition(items.count == 5 && items.reduce(Int64(0)) { $0 + $1.size } == 15)
            precondition(checkpoints.contains("Consultando tamaño: " + items[0].path))
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: blob.path)
            print("Production hash, diagnostic failure propagation and metadata-only inventory: OK")
        }.value
    }
}
''')
    binary = work / 'HashMemory'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    str(swift), '-o', str(binary)], check=True)
    run = subprocess.run(['/usr/bin/time', '-l', str(binary), str(blob), expected.hexdigest()],
                         text=True, capture_output=True, check=True)
    print(run.stdout)
    match = re.search(r'(\d+)\s+maximum resident set size', run.stderr)
    if not match:
        raise RuntimeError('Missing macOS peak memory measurement')
    peak = int(match[1])
    print(f'Peak memory for 512 MiB encrypted blob: {peak / 1024**2:.1f} MiB')
    assert peak < 192 * 1024 * 1024, 'Hash loop retained file-sized temporary buffers'
