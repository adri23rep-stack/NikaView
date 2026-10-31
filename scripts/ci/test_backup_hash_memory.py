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
            print("Production hash: checksum and progress OK")
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
