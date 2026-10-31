#!/usr/bin/env python3
"""Ensure the Vault Liquid Glass controls stay at the bottom and Home card is calm."""
from pathlib import Path
import sys
r = Path(__file__).resolve().parents[2]
home = (r / "SolidSecViewer/HomeView.swift").read_text()
vault = (r / "SolidSecViewer/PrivateVaultView.swift").read_text()
pbx = (r / "SolidSecViewer.xcodeproj/project.pbxproj").read_text()
card = home.split("private var vaultBar: some View {", 1)[1].split("// MARK: Por tipo", 1)[0]
browser = vault.split("private var browser: some View {", 1)[1].split("private var browserHeader:", 1)[0]
checks = {
    "Vault still opens": "onOpenVault()" in card,
    "small adaptive card": "HomeTintedCardSurface(" in card and "strength: 0.58" in card,
    "not saturated solid gradient": "LinearGradient(" not in card,
    "no oversized glow": "HomeVaultGlow" not in home and "HomeVaultMelt" not in card,
    "no trailing bubbles": "HomeVaultBubbles" not in card and "HomeVaultSparkles" not in card,
    "correct theme colors": ".foregroundStyle(.primary)" in card and ".foregroundStyle(.secondary)" in card,
    "Vault controls fixed to bottom": ".safeAreaInset(edge: .bottom, spacing: 0)" in browser and "browserActions" in browser,
    "Vault title and selection remain at top": "browserHeader" in browser and "vaultSelectionToolbar" in browser,
    "old top glass absent": "browserActions" not in vault.split("private var browserHeader: some View {", 1)[1].split("private var vaultSelectionToolbar:", 1)[0],
    "all actions kept": all(a in vault for a in ["showNewFolder = true", "showLANReceiver = true", "showPhotoPicker = true", "showImporter = true", "vault.lock()"]),
    "version updated": pbx.count("MARKETING_VERSION = 0.12.21;") == 2 and pbx.count("CURRENT_PROJECT_VERSION = 59;") == 2,
}
for name, valid in checks.items():
    print(("OK " if valid else "FAIL ") + name)
if not all(checks.values()):
    sys.exit(1)
