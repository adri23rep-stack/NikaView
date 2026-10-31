#!/usr/bin/env python3
"""Regression: softer two-tone home cards that follow the existing appearance."""
from pathlib import Path
root=Path(__file__).resolve().parents[2]
home=(root/"SolidSecViewer/HomeView.swift").read_text()
project=(root/"SolidSecViewer.xcodeproj/project.pbxproj").read_text()
surface=home.split("private struct HomeTintedCardSurface: View {",1)[1].split("private struct HomeQuickAccessRow: View",1)[0]
cards=home.split("private var storageSection: some View {",1)[1].split("// MARK: Vault",1)[0]
checks={
 "exactly 2 gradient color stops":'tint.opacity(primaryOpacity)' in surface and 'shadowTone.opacity(shadowOpacity)' in surface and 'tint.opacity(dark ? 0.08' not in surface,
 "shadow is from primary, not independent hue":'shadowTone = tint.nikaidoDarkened(0.74)' in surface and 'var secondary: Color?' not in surface,
 "softer than previous cards":'dark ? 0.18 : 0.12' in surface and 'dark ? 0.105 : 0.065' in surface,
 "subtle border":'dark ? 0.22 : 0.15' in surface and 'lineWidth: 0.8' in surface,
 "soft glow from shadow":'shadowTone.opacity(dark ? 0.08 : 0.045)' in surface,
 "existing theme dynamic":'@Environment(\\.colorScheme)' in surface and 'Color(uiColor: .secondarySystemBackground)' in surface,
 "respect accessibility":'@Environment(\\.accessibilityReduceTransparency)' in surface,
 "Files uses accent only":'tint: nikaidoAccent' in cards and 'secondary: .mint' not in cards,
 "storage cards derive shade":'tint: colors.first ?? .blue' in home,
 "categories keep distinctive primary":'categoryTint(category.filter)' in home,
 "quick access uses same surface":'HomeTintedCardSurface(tint: tint, radius: 16, strength: 0.72)' in home,
 "vault not replaced":'HomeTintedCardSurface(' in home and 'HomeVaultGlow' not in home,
 "version":project.count("MARKETING_VERSION = 0.12.20;")==2 and project.count("CURRENT_PROJECT_VERSION = 57;")==2
}
for name,ok in checks.items():print(("[OK] " if ok else "[FAIL] ")+name)
assert all(checks.values()),"Two-tone cards regression"
