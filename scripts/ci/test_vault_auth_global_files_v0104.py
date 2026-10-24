#!/usr/bin/env python3
"""Static guards for v0.10.4: per-file auth, thumbnails, folders, global files."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "SolidSecViewer"

vault = (APP / "PrivateVaultView.swift").read_text(encoding="utf-8")
session = (APP / "PrivateVaultSession.swift").read_text(encoding="utf-8")
bio = (APP / "NikaidoBiometricUnlock.swift").read_text(encoding="utf-8")
store = (APP / "SecurityScopedFolderStore.swift").read_text(encoding="utf-8")
models = (APP / "ExplorerModels.swift").read_text(encoding="utf-8")
explorer = (APP / "ExplorerView.swift").read_text(encoding="utf-8")
global_files = (APP / "ExplorerGlobalFiles.swift").read_text(encoding="utf-8")
drag = (APP / "ExplorerDragMove.swift").read_text(encoding="utf-8")
sec_crypto = (APP / "SecCollectionCrypto.swift").read_text(encoding="utf-8")
sec_viewer = (APP / "StoredSecCollectionViewer.swift").read_text(encoding="utf-8")
sec_thumb = (APP / "VaultThumbnail.swift").read_text(encoding="utf-8")
home = (APP / "HomeView.swift").read_text(encoding="utf-8")
content_view = (APP / "ContentView.swift").read_text(encoding="utf-8")
pbx = (ROOT / "SolidSecViewer.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")

checks = {
    "file auth helper": "enum NikaidoFileAuth" in bio and "evaluatePolicy" in bio,
    "password verification (constant time)": "func verifyPassword" in session and "constantTimeEquals" in session,
    "protected open gate": "func protectedOpen" in vault and vault.count("protectedOpen(") >= 6,
    "cancel never opens": "case .cancelled:" in vault,
    "thumbnails hidden until auth": "revealed: thumbnailsRevealed" in vault and "guard revealed else" in vault,
    "vault thumbnail fixed container": "Color.clear" in vault and ".aspectRatio(1.25, contentMode: .fit)" in vault,
    "explorer thumbnail fixed container": "Color.clear" in explorer and "thumbnailContent" in explorer,
    "folder source labels": "enum ExplorerStorageSource" in models and "ExplorerUnavailableLocation" in models,
    "stale folder handling": "retryUnavailable" in store and "removeUnavailable" in store,
    "duplicate folder identity": "fileResourceIdentifierKey" in store and "isSameFolder" in store,
    "global files scanner": "enum ExplorerGlobalScanner" in global_files and "nextObject()" in global_files,
    "global files filters": "case images" in global_files and "case videos" in global_files and "case text" in global_files,
    "global files wired": "ExplorerGlobalFilesView" in explorer and "showGlobalFiles" in explorer,
    "global files registered": "ExplorerGlobalFiles.swift" in pbx and "NikaidoExtras.swift" in pbx,
    "vault is not indexed": "PrivateVault" not in global_files,
    "custom drag handle": "struct ExplorerDragHandle" in drag and "LongPressGesture" in drag,
    "drop onto folders": "case folder(ExplorerFileItem, pane: Int)" in drag and "moveItems(" in explorer,
    "drop onto other pane": "case pane(Int)" in drag and "func performDrop" in explorer,
    "no move into itself": "hasPrefix(itemPath" in explorer,
    "drag files registered": "ExplorerDragMove.swift" in pbx,
    "sec thumbnails fixed container": "Color.clear" in sec_thumb and "Color.clear" in sec_viewer,
    "no video left playing (vault)": "viewerIsActive" in vault and "Un solo video a la vez" in session,
    "no video left playing (.sec)": "viewerIsActive" in sec_viewer and "Un solo video a la vez" in sec_viewer,
    "face id releases stored password": "kSecUseAuthenticationContext" in bio and "verifyPassword(storedPassword)" in vault,
    "home shows added folders": "Carpetas añadidas" in explorer and "ExplorerExternalLocationRow" in drag,
    "cloud and apple badges": "icloud.fill" in models and "applelogo" in models,
    "drop onto added folders": "case location(ExplorerStorageLocation)" in drag and "destinationRoot:" in explorer,
    "home screen": "struct HomeView" in home and "mode: AppMode = .home" in content_view,
    "home tour + all folders": "struct HomeFolderTourView" in home and "struct HomeAllFoldersView" in home,
    "home fluid Vault + logo hop": "HomeVaultGlow" in home and "playLogoHop" in home and "HomeVaultGlow" in home,
    "home categories filters": "case music" in global_files and "case packages" in global_files and "case documents" in global_files,
    "home registered": "HomeView.swift" in pbx,
    "vault unlock has two options": "unlockOptionCard" in vault and "passwordPanelVisible" in vault,
    ".sec unlock has two options": "secOptionCard" in sec_viewer and "NikaidoSecFaceID" in sec_viewer,
    ".sec tap skips redundant Face ID": (
        "if entry.isSecCollectionFolder {\n                // The .sec viewer prompts" in vault
        and "selectedSecFolder = entry\n            } else if entry.kind == .folder" in vault
    ),
    ".sec menu skips redundant Face ID": (
        "if entry.isSecCollectionFolder {\n                Button {\n                    // Same direct route as tapping the collection.\n                    selectedSecFolder = entry" in vault
    ),
    ".sec remains encrypted until password or Face ID": (
        "if session.isUnlocked {\n                    gallery\n                } else {\n                    unlock" in sec_viewer
        and "await session.unlock(" in sec_viewer
        and "unlockWithFaceID()" in sec_viewer
    ),
    ".sec password change (safe copy)": "makeRekeyedCopy" in sec_viewer and "StoredSecRekeyView" in sec_viewer and "encodeBase64URL" in sec_crypto,
    "face id store diagnostics": "NikaidoBiometricEnableResult" in bio and "storeFailed" in vault,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("OK   " if ok else "FAIL ") + name)

if failed:
    print("VAULT AUTH / GLOBAL FILES GUARD: FAIL")
    sys.exit(1)

print("VAULT AUTH / GLOBAL FILES GUARD: OK")

