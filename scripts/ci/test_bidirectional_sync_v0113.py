#!/usr/bin/env python3
"""Non-destructive synchronization invariants; the Xcode job also typechecks Swift."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[2]
swift = (root / 'SolidSecViewer/NikaidoBidirectionalSync.swift').read_text()
ui = (root / 'SolidSecViewer/NikaidoFolderTools.swift').read_text()
pbx = (root / 'SolidSecViewer.xcodeproj/project.pbxproj').read_text()
checks = {
    'new sync included exactly once': pbx.count('NikaidoBidirectionalSync.swift in Sources') == 1 and 'B933' in pbx,
    'separate bidirectional UI': 'NikaidoBidirectionalSync(left: left, right: right' in ui,
    'conflicts omitted by default': 'item.conflict ? .skip' in swift,
    'all copies require confirmation': 'confirmationDialog(' in swift and 'Confirmar sincronización' in swift,
    'original files never removed': 'removeItem(at: staging)' in swift and not re.search(r'removeItem\(at: (?!staging)', swift),
    'destination saved before replacement': 'fm.moveItem(at: rechecked, to: backup)' in swift,
    'restores backup when writing fails': 'fm.moveItem(at: backup, to: rechecked)' in swift,
    'changes rechecked after preview': swift.count('unchanged(from, source) && unchanged(') == 2,
    'symlinks disallowed including dangling': 'destinationOfSymbolicLink(atPath:' in swift,
    'no nested root recursion': 'a.hasPrefix(b + "/")' in swift and 'b.hasPrefix(a + "/")' in swift,
    'bounded scan rejects partial runs': 'scanned.count <= 1500' in swift,
    'no background capture of vault content': 'PrivateVault' not in swift,
}
for title, ok in checks.items():
    print(('OK: ' if ok else 'FAIL: ') + title)
if not all(checks.values()):
    sys.exit(1)
