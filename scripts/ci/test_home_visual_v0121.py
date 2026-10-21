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
    "background giant slow blurred orbs": home.count(".blur(radius:") >= 3 and "repeatForever(autoreverses: true)" in home,
    "Reduce Motion respected": "accessibilityReduceMotion" in home and "animated: !reduceMotion" in home,
    "Reduce Transparency respected": "accessibilityReduceTransparency" in home and "if !reduceTransparency" in home,
    "Low Power Mode respected": "isLowPowerModeEnabled" in home,
    "vault still opens": "onOpenVault()" in home,
    "minimal bubbles inside vault card": "HomeVaultBubbles(" in home and "tint: .white" in home and ".clipShape(RoundedRectangle(cornerRadius: 22" in home,
    "bubbles stay clear of logo and title": "Dedicated decoration area" in home and ".frame(width: 43, height: 66)" in home,
    "bubbles visibly rise": "truncatingRemainder(dividingBy: 1)" in home and "progress * (size.height + radius * 2)" in home,
    "bubbles run faster": "speed: 0.64" in home and "minimumInterval: 1.0 / 30.0" in home,
    "vault animations pause in low power mode": "animated: !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled" in home,
    "glossy bubbles render even without animation": "bubbleCanvas(time: 0)" in home,
    "no obsolete sparkles": "HomeVaultSparkles" not in home,
    "version v0.12.3": pbx.count("MARKETING_VERSION = 0.12.3;") == 2 and pbx.count("CURRENT_PROJECT_VERSION = 40;") == 2,
}
for name, ok in checks.items():
    print(("OK " if ok else "FAIL ") + name)
if not all(checks.values()):
    sys.exit(1)
