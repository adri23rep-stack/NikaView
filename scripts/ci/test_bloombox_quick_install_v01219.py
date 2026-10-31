#!/usr/bin/env python3
"""Verify IPA install action without a private sandbox deep-link and vault backup retained."""
from pathlib import Path
root = Path(__file__).resolve().parents[2]
explorer=(root/"SolidSecViewer/ExplorerView.swift").read_text()
browser=(root/"SolidSecViewer/ExplorerPackageBrowser.swift").read_text()
vault=(root/"SolidSecViewer/PrivateVaultView.swift").read_text()
backup=(root/"SolidSecViewer/TakopiVaultBackup.swift").read_text()
session=(root/"SolidSecViewer/PrivateVaultSession.swift").read_text()
project=(root/"SolidSecViewer.xcodeproj/project.pbxproj").read_text()
pane=explorer.split("struct ExplorerPaneView: View {",1)[1]
menu=pane.split("private func itemContextMenu(_ item: ExplorerFileItem) -> some View {",1)[1].split("private func",1)[0]
checks={
 "IPA context menu install":'Label("Instalar con BloomBox"' in menu,
 "IPA / TIPA only":'["ipa", "tipa"].contains(item.url.pathExtension.lowercased())' in menu,
 "does not offer for folders":'if !item.isDirectory' in menu,
 "parent callback wired":"onInstallIPA: { item in" in explorer and "let onInstallIPA: (ExplorerFileItem) -> Void" in pane,
 "native secure share used":"shareURLs = [item.url]" in explorer and "showShareSheet = true" in explorer,
 "BloomBox receives via extension":"ExplorerShareSheet(urls: shareURLs)" in explorer,
 "no invalid private sandbox link":"livecontainer://install?url=" not in explorer,
 "install action also in IPA viewer":'Label("Instalar con BloomBox"' in browser,
 "full encrypted backup kept":"TakopiVaultBackup.create(" in session and "ZIPFoundation.Archive(url: result, accessMode: .create)" in backup,
 "backup to iCloud or local":"TakopiVaultBackupExportPicker" in vault,
 "backup restore with password":'SecureField("Contraseña del respaldo"' in vault and "authenticateEncryptedBackup" in session,
 "backup replacement rollback":'try? fm.moveItem(at: rollback, to: root)' in session,
 "version":project.count("MARKETING_VERSION = 0.12.19;")==2 and project.count("CURRENT_PROJECT_VERSION = 57;")==2
}
for title,ok in checks.items(): print(("[OK] " if ok else "[FAIL] ")+title)
assert all(checks.values()), "BloomBox quick install and Vault backup regression"
