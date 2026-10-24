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
    "hint hides when tapped": 'showSettingsHint = false' in home and 'onOpenExplorer(.settings)' in home,
    "hint not blocking interaction": ".allowsHitTesting(false)" in home,
    "hint returns on every Home appearance": ".onAppear {" in home and "showSettingsHint = true" in home,
    "hint not persistently suppressed": "nikaido.settingsHintAlreadyTapped" not in home,
    "intro task cancelled on leave": "homeIntroTask?.cancel()" in home,
    "original hop kept": "await playLogoHop()" in home,
    "living background has 6 orbs": home.count("ambientOrb(") >= 7 and "sin(time * .pi / seconds" in home,
    "Reduce Motion respected": "accessibilityReduceMotion" in home and "motionEnabled" in home,
    "Reduce Transparency respected": "accessibilityReduceTransparency" in home and "if !reduceTransparency" in home,
    "Low Power Mode respected": "isLowPowerModeEnabled" in home,
    "vault still opens": "onOpenVault()" in home,
    "no glass dock on Home": "homeBottomDock" not in home and ".safeAreaInset(edge: .bottom" not in home,
    "no protruding drips": "HomeVaultGlow(" in home and "HomeVaultMelt" not in home,
    "Vault text clear": 'Text("Takopi Vault")' in home,
    "fluid shape animates": "HomeVaultGlow" in home and "sin(time * 1.2)" in home,
    "fluid shape remains moving": "minimumInterval: 1.0 / 20.0" in home,
    "vault animations pause in low power mode": "animated: motionEnabled" in home and "isLowPowerModeEnabled" in home,
    "glow pauses without animation": "paused: !animated" in home,
    "no fake bubbles": "HomeVaultBubbles" not in home,
    "version v0.12.9": pbx.count("MARKETING_VERSION = 0.12.17;") == 2 and pbx.count("CURRENT_PROJECT_VERSION = 54;") == 2,
}
for name, ok in checks.items():
    print(("OK " if ok else "FAIL ") + name)
if not all(checks.values()):
    sys.exit(1)

