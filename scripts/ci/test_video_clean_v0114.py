#!/usr/bin/env python3
"""Guards for privacy-first video metadata export."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
app = root / "SolidSecViewer"
video = (app / "NikaidoVideoCleanExporter.swift").read_text(encoding="utf-8")
tools = (app / "NikaidoFolderTools.swift").read_text(encoding="utf-8")
pbx = (root / "SolidSecViewer.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
checks = {
    "exporter registered in project": pbx.count("NikaidoVideoCleanExporter.swift in Sources") == 1,
    "metadata explicitly cleared": "exporter.metadata = []" in video,
    "identifying metadata filtered": "AVMetadataItemFilter.forSharing()" in video,
    "post-export metadata validation": "load(.metadata)" in video and "load(.commonMetadata)" in video,
    "rejects residual identifying metadata": "guard !stillIdentifiable else" in video,
    "source remains untouched": "removeItem(at: input)" not in video and "removeItem(at: output)" in video,
    "iOS 16-compatible fallback": "if #available(iOS 18.0, *)" in video and "await exporter.export()" in video,
    "large exports cancellable": "Task.checkCancellation()" in video and "exportTask?.cancel()" in tools,
    "only supported video types": '"mp4", "mov", "m4v"' in tools,
    "share only clean generated copy": "ExplorerShareSheet(urls: [cleanURL])" in tools,
    "new version": pbx.count("MARKETING_VERSION = 0.11.4;") == 2 and pbx.count("CURRENT_PROJECT_VERSION = 35;") == 2,
}
for title, ok in checks.items():
    print(("OK " if ok else "FAIL ") + title)
if not all(checks.values()):
    sys.exit(1)
