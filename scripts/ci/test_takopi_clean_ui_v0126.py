#!/usr/bin/env python3
"""Check clean Takopi v0.12.6 layout without weakening vault regression tests."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
home = (root / "SolidSecViewer/HomeView.swift").read_text()
explorer = (root / "SolidSecViewer/ExplorerView.swift").read_text()
vault = (root / "SolidSecViewer/PrivateVaultView.swift").read_text()
pbx = (root / "SolidSecViewer.xcodeproj/project.pbxproj").read_text()

pane = explorer.split("private var paneHeader: some View {", 1)[1].split("@ViewBuilder", 1)[0]
dock = explorer.split("private var explorerBottomDock: some View {", 1)[1].split("/// Abre la carpeta", 1)[0]

checks = {
    "no Liquid Glass or dock on Home": "homeBottomDock" not in home and ".safeAreaInset(edge: .bottom" not in home,
    "Takopi logo and animations retained": 'Image("TakopiLogo")' in home and "await playLogoHop()" in home,
    "ambient background retained": home.count("ambientOrb(") >= 7 and "accessibilityReduceMotion" in home,
    "storage without decorative circles": "private struct HomeStorageCard" in home and "colors.first ?? .blue" in home,
    "vault glow contained": "HomeVaultMelt" not in home and "HomeVaultGlow" in home,
    "Explorer optional search header": "explorerTopBar" not in explorer and "paneHeader" in explorer,
    "top header has no titles or action buttons": "Button {" not in pane and 'Text(pane.title)' not in pane and 'Text(pane.relativePath)' not in pane,
    "bottom glass controls": "NikaidoGlassCapsule()" in dock and "toggleSplit()" in dock,
    "plus outside glass capsule": dock.find(".modifier(NikaidoGlassCapsule())") < dock.find("floatingAddButton"),
    "search still accessible": "searchingPaneIndex = activePane" in dock and "@Binding var showSearch: Bool" in explorer,
    "safe Vault controls": "private var browserActions" in vault and "vault.lock()" in vault,
    "new build number": pbx.count("MARKETING_VERSION = 0.12.11;") == 2 and pbx.count("CURRENT_PROJECT_VERSION = 48;") == 2,
}
for name, passed in checks.items():
    print(("OK " if passed else "FAIL ") + name)
if not all(checks.values()):
    sys.exit(1)

