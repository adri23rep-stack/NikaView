import re
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
    "version not downgraded": (len(re.findall(r"MARKETING_VERSION = (\d+)\.(\d+)\.(\d+);", pbx)) == 2 and all(tuple(map(int, v)) >= (0, 11, 4) for v in re.findall(r"MARKETING_VERSION = (\d+)\.(\d+)\.(\d+);", pbx)) and len(re.findall(r"CURRENT_PROJECT_VERSION = (\d+);", pbx)) == 2 and all(int(v) >= 35 for v in re.findall(r"CURRENT_PROJECT_VERSION = (\d+);", pbx))),
}
for title, ok in checks.items():
    print(("OK " if ok else "FAIL ") + title)
if not all(checks.values()):
    sys.exit(1)
