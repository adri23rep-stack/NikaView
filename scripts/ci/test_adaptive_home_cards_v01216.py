#!/usr/bin/env python3
"""Verify colorful adaptive Home cards while retaining theme/security behaviors."""
from pathlib import Path
root = Path(__file__).resolve().parents[2]
home = (root/"SolidSecViewer/HomeView.swift").read_text()
proj = (root/"SolidSecViewer.xcodeproj/project.pbxproj").read_text()
surface=home.split("private struct HomeTintedCardSurface: View {",1)[1].split("private struct HomeQuickAccessRow",1)[0]
quick=home.split("private var quickAccessSection: some View {",1)[1].split("// MARK: Fondo",1)[0]
storage=home.split("private var storageSection: some View {",1)[1].split("// MARK: Vault",1)[0]
categories=home.split("private var categoriesSection: some View {",1)[1].split("// MARK: - Tarjeta de almacenamiento",1)[0]
checks={
    "system-driven colors retained":"@Environment(\\.colorScheme)" in surface and "scheme == .dark" in surface,
    "dynamic base not hardcoded dark":"Color(uiColor: .secondarySystemBackground)" in surface,
    "lighter light scheme and deeper dark scheme":"dark ? 0.18 : 0.12" in surface,
    "subtle tinted borders":"strokeBorder" in surface,
    "reduced transparency respected":"@Environment(\\.accessibilityReduceTransparency)" in surface,
    "existing wallpaper preserved":"private var background: some View" in home and "ambientOrb(" in home,
    "both storage cards colored":storage.count("HomeStorageCard(")>=2 and "HomeTintedCardSurface(" in home.split("private struct HomeStorageCard: View",1)[1].split("// MARK: - Superficies",1)[0],
    "Files uses selected accent":"tint: nikaidoAccent" in storage and "shadowTone = tint.nikaidoDarkened(0.74)" in surface,
    "Vault design preserved":"HomeTintedCardSurface(" in home and "HomeVaultGlow" not in home and "NikaidoVaultMark(" in home,
    "favorites themed":"symbol: \"star.fill\"" in quick and "tint: nikaidoAccent" in quick,
    "recent folders themed":"symbol: \"clock.arrow.circlepath\"" in quick and "tint: .cyan" in quick,
    "quick row retains contrast":"foregroundStyle(.primary)" in home.split("private struct HomeQuickAccessRow: View",1)[1].split("// MARK: - Luz",1)[0],
    "category colors per type":"func categoryTint" in home and "tint: categoryTint(category.filter)" in categories,
    "category view keeps tap navigation":"onOpenExplorer(.global(category.filter))" in categories,
    "existing card press animations":"NikaidoPressCardStyle()" in home,
    "theme setting unchanged":"@Environment(\\.nikaidoAccent)" in home and "onOpenExplorer(.settings)" in home,
    "version correct":proj.count("MARKETING_VERSION = 0.12.20;")==2 and proj.count("CURRENT_PROJECT_VERSION = 57;")==2
}
for name, passed in checks.items():print(("[OK] " if passed else "[FAIL] ")+name)
assert all(checks.values()),"Home adaptive cards regression"
