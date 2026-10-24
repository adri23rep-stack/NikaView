#!/usr/bin/env python3
"""Contracts for fast, bounded, two-stage IPA browsing in v0.12.11."""
from pathlib import Path
root = Path(__file__).resolve().parents[2]
source = (root / "SolidSecViewer/ExplorerPackageBrowser.swift").read_text()
project = (root / "SolidSecViewer.xcodeproj/project.pbxproj").read_text()
checks = {
    "bounded tail check": "static func verifyZipTail(_ url: URL)" in source and "65_557" in source,
    "readIndex without decompression": "static func readIndex(_ url: URL)" in source and "return Snapshot(entries: entries, details: Details())" in source,
    "early validation": "try verifyZipTail(url)" in source and "try verifyZipTail(packageURL)" in source,
    "entry scan limit": "visited <= maxEntries" in source,
    "visible contents before details": source.index("snapshot = value\n                    loading = false") < source.index("details = info"),
    "details after index": "ExplorerPackageArchive.read(package).details" in source,
    "large icon guard": "(values?.fileSize ?? 0) > 512 * 1024 * 1024" in source,
    "fewer candidates for large icon": "ranked.prefix(isLarge ? 3 : 16)" in source,
    "safe size display": "Int64(clamping: entry.size)" in source,
    "keeps individual extraction": 'Button("Extraer al otro panel")' in source,
    "version bump": project.count("MARKETING_VERSION = 0.12.16;") == 2 and project.count("CURRENT_PROJECT_VERSION = 53;") == 2,
}
for name, passed in checks.items():
    print(("[OK] " if passed else "[FAIL] ") + name)
assert all(checks.values()), "Large package regression detected"
