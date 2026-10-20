#!/usr/bin/env python3
"""Guard actual iOS 26 glass APIs and older iOS fallbacks."""
from pathlib import Path
import re
import sys
root = Path(__file__).resolve().parents[2]
app = root / "SolidSecViewer"
theme = (app / "NikaidoTheme.swift").read_text()
vault = (app / "PrivateVaultView.swift").read_text()
explorer = (app / "ExplorerView.swift").read_text()
workflow = (root / ".github/workflows/build-ipa.yml").read_text()
pbx = (root / "SolidSecViewer.xcodeproj/project.pbxproj").read_text()
checks = {
    "native Liquid Glass on iOS 26": ".glassEffect(.regular, in: .capsule)" in theme,
    "interactive floating glass button": ".glassEffect(.regular.tint(tint).interactive(), in: .circle)" in theme,
    "opaque fallback for Reduce Transparency": "accessibilityReduceTransparency" in theme,
    "legacy iOS material fallback": "content.background(.regularMaterial, in: Capsule())" in theme,
    "vault controls horizontal": "HStack(spacing: 2)" in vault and "NikaidoGlassActionStyle()" in vault,
    "vault title isolated from buttons": ".truncationMode(.middle)" in vault and "private var browserHeader" in vault,
    "vault controls retain their actions": all(s in vault for s in (
        "showNewFolder = true", "showLANReceiver = true", "showPhotoPicker = true",
        "showImporter = true", "vault.lock()", "protectedOpen(",
    )),
    "explorer toolbar glass": ".modifier(NikaidoGlassCapsule())" in explorer,
    "floating add action glass": ".modifier(NikaidoGlassFloatingCircle" in explorer,
    "iOS 26 capable build runner": "runs-on: macos-26" in workflow and "Xcode_26.6.app" in workflow,
    "deployment floor retained": "IPHONEOS_DEPLOYMENT_TARGET = 16.0;" in pbx,
    "version not downgraded": len(re.findall(r"MARKETING_VERSION = (\d+)\.(\d+)\.(\d+);", pbx)) == 2 and all(tuple(map(int, v)) >= (0, 12, 0) for v in re.findall(r"MARKETING_VERSION = (\d+)\.(\d+)\.(\d+);", pbx)) and len(re.findall(r"CURRENT_PROJECT_VERSION = (\d+);", pbx)) == 2 and all(int(v) >= 37 for v in re.findall(r"CURRENT_PROJECT_VERSION = (\d+);", pbx)),
}
for key, ok in checks.items(): print(("OK " if ok else "FAIL ") + key)
if not all(checks.values()): sys.exit(1)
