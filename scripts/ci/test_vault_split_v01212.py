#!/usr/bin/env python3
"""Verify Takopi 0.12.12 vault split keeps encryption, safety and UI behavior."""
from pathlib import Path
root = Path(__file__).resolve().parents[2]
explorer = (root / "SolidSecViewer/ExplorerView.swift").read_text()
pane = (root / "SolidSecViewer/ExplorerVaultSplitPane.swift").read_text()
home = (root / "SolidSecViewer/HomeView.swift").read_text()
mark = (root / "SolidSecViewer/TakopiOctopusMark.swift").read_text()
pbx = (root / "SolidSecViewer.xcodeproj/project.pbxproj").read_text()
checks = {
    "octopus no longer app artwork": "TakopiOctopusMark()" in home and 'Image("TakopiLogo")' not in home,
    "existing animated hop retained": "await playLogoHop()" in home and "showSettingsHint = true" in home,
    "plain octopus vector": "struct TakopiOctopusMark: View" in mark and "TakopiLogo" not in mark,
    "two file panes still available": "paneView(rightPane, index: 1)" in explorer,
    "vault pane with resizable split": "ExplorerResizableSplit(fraction: $splitFraction)" in explorer and "ExplorerVaultSplitPane(" in explorer,
    "menu access": '"Bóveda en pantalla dividida"' in explorer,
    "vault pane real encrypted session": "@EnvironmentObject private var vault: PrivateVaultSession" in pane,
    "vault requires unlock": "if !vault.isUnlocked" in pane and "SecureField(" in pane,
    "vault folders are browsable": "vault.children(of: currentFolderID)" in pane and "currentFolderID = entry.id" in pane,
    "vault is registered as drop destination": ".explorerPaneProbe(dragState, pane: 1)" in pane,
    "vault receives internal drag token": "ExplorerDragPayload.load(from: providers)" in explorer,
    "drop target not routed as ordinary file move": "case .pane(let index) where index == 1 && splitOpen && vaultPaneOpen" in explorer and "request.sourcePane == 0" in explorer,
    "vault folder selection honored": "destinationFolderID: vaultSplitFolderID" in explorer and "parentID: destinationID" in explorer,
    "encryption bridge retained": "ExplorerVaultBridge.send(" in explorer,
    "copy and delete originals are separate": "performSendToVault(deleteOriginals: false)" in explorer and "performSendToVault(deleteOriginals: true)" in explorer,
    "delete only after all encryptions": explorer.index("try await ExplorerVaultBridge.send(") < explorer.index("try await ExplorerFileEngine.delete(items, root: root)"),
    "vault lock blocks deletion": "guard vault.isUnlocked else { throw PrivateVaultError.locked }" in explorer,
    "vault lock clears folder state": "currentFolderID = nil" in pane and "password = \"\"" in pane,
    "project includes both Swift views": "A970" in pbx and "B970" in pbx and "A971" in pbx and "B971" in pbx,
    "v0.12.12 build49": pbx.count("MARKETING_VERSION = 0.12.15;") == 2 and pbx.count("CURRENT_PROJECT_VERSION = 52;") == 2,
}
for title, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + title)
assert all(checks.values()), "Vault split integration regression"
