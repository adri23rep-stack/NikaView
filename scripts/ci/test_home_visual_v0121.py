#!/usr/bin/env python3
"""Checks for the compact HomeView visual refresh and accessibility."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[2]
home = (root / "SolidSecViewer/HomeView.swift").read_text()
pbx = (root / "SolidSecViewer.xcodeproj/project.pbxproj").read_text()
checks = {
    "settings N still opens real settings": "onOpenExplorer(.settings)" in home,
    "small Spanish hint": 'Text("¡Hazme click!")' in home,
    "hint ends when tapped": 'settingsHintAlreadyTapped = true' in home,
    "hint not blocking interaction": ".allowsHitTesting(false)" in home,
    "settings hint only shown until tapped": 'if !settingsHintAlreadyTapped' in home,
    "original hop kept": "await playLogoHop()" in home,
    "background giant slow blurred orbs": home.count(".blur(radius:") >= 3 and "repeatForever(autoreverses: true)" in home,
    "Reduce Motion respected": "accessibilityReduceMotion" in home and "animated: !reduceMotion" in home,
    "Reduce Transparency respected": "accessibilityReduceTransparency" in home and "if !reduceTransparency" in home,
    "Low Power Mode respected": "isLowPowerModeEnabled" in home,
    "vault still opens": "onOpenVault()" in home,
    "glass bubbles on vault": "HomeVaultBubbles(tint: nikaidoAccent" in home,
    "glossy bubbles render even without animation": "bubbleCanvas(time: 0)" in home,
    "no obsolete sparkles": "HomeVaultSparkles" not in home,
    "version v0.12.1": pbx.count("MARKETING_VERSION = 0.12.1;") == 2 and pbx.count("CURRENT_PROJECT_VERSION = 38;") == 2,
}
for name, ok in checks.items():
    print(("OK " if ok else "FAIL ") + name)
if not all(checks.values()):
    sys.exit(1)
