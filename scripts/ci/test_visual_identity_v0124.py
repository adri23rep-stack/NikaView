#!/usr/bin/env python3
"""Static regression checks for the NikaView 0.12.4 visual update."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
theme = (root / "SolidSecViewer/NikaidoTheme.swift").read_text()
home = (root / "SolidSecViewer/HomeView.swift").read_text()
content = (root / "SolidSecViewer/ContentView.swift").read_text()
vault = (root / "SolidSecViewer/PrivateVaultView.swift").read_text()
pbx = (root / "SolidSecViewer.xcodeproj/project.pbxproj").read_text()

checks = {
    "brand mark is drawn in SwiftUI": "struct NikaidoBrandMark: View" in theme and "NikaidoNMark()" in theme,
    "feature mark exists": "struct NikaidoFeatureMark: View" in theme,
    "vault mark is separate": "struct NikaidoVaultMark: View" in theme,
    "reduce motion respected by press effect": "struct NikaidoPressCardStyle" in theme and "reduceMotion ? 1" in theme,
    "branding appears in header": 'Image("TakopiLogo")' in home and 'Text("Takopi Explorer")' in home,
    "file icon refreshed": 'systemName: "folder.fill"' in home,
    "vault animated glow": "HomeVaultGlow" in home and "minimumInterval: 1.0 / 20.0" in home,
    "N logo greeting retained": "await playLogoHop()" in home and 'Text("¡Hazme click!")' in home,
    "category icons share identity": "systemName: category.symbol" in home,
    "staggered entrances": home.count(".nikaidoHomeEntrance(") >= 4,
    "Home is glass-free": "homeBottomDock" not in home and ".safeAreaInset(edge: .bottom" not in home,
    "Takopi image used": 'Image("TakopiLogo")' in home,
    "low power stops decoration": "ProcessInfo.processInfo.isLowPowerModeEnabled" in home,
    "reduced motion stops entrances": "!reduceMotion" in home and "enabled: motionEnabled" in home,
    "private vault uses new logo": "NikaidoVaultMark(tint: nikaidoAccent, size: 92)" in vault,
    "unlock cards respond visually": "NikaidoPressCardStyle()" in vault,
    "screen switching animated": "withAnimation(.easeInOut(duration: 0.24))" in content and ".transition(" in content,
    "vault exit is not animated": "privateVault.lock()\n                        navigate(.home, animated: false)" in content,
    "screens still accessible": "onOpenExplorer: { kind in" in content and "onOpenVault: {" in content,
    "build version updated": pbx.count("MARKETING_VERSION = 0.12.11;") == 2 and pbx.count("CURRENT_PROJECT_VERSION = 48;") == 2,
}

for label, passed in checks.items():
    print(("OK " if passed else "FAIL ") + label)
if not all(checks.values()):
    sys.exit(1)

