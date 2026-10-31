#!/usr/bin/env python3
"""Encrypted vault backup and IPA handoff security regression."""
from pathlib import Path

root=Path(__file__).resolve().parents[2]
browser=(root/"SolidSecViewer/ExplorerPackageBrowser.swift").read_text()
backup=(root/"SolidSecViewer/TakopiVaultBackup.swift").read_text()
picker=(root/"SolidSecViewer/TakopiVaultBackupPickers.swift").read_text()
session=(root/"SolidSecViewer/PrivateVaultSession.swift").read_text()
vault=(root/"SolidSecViewer/PrivateVaultView.swift").read_text()
biometric=(root/"SolidSecViewer/NikaidoBiometricUnlock.swift").read_text()
pbx=(root/"SolidSecViewer.xcodeproj/project.pbxproj").read_text()
checks={
 "IPA install action":'Label("Instalar con BloomBox"' in browser,
 "handoff via iOS share":'ExplorerShareSheet(urls: [target.url])' in browser,
 "no inaccessible sandbox URL scheme hack":'livecontainer://install?url=' not in browser,
 "export encrypted only":'ZIPFoundation.Archive(url: result, accessMode: .create)' in backup and 'PrivateVaultCrypto.decrypt' not in backup,
 "all encrypted blobs":'("blobs", "ssvb")' in backup,
 "encrypted thumbnails":'("thumbnails", "nkt")' in backup,
 "config and both index copies":all(x in backup for x in ['"vault.json"','"vault.backup.json"','"index.ssv"','"index.previous.ssv"']),
 "streaming SHA256":'try input.read(upToCount: 256 * 1024)' in backup,
 "manifest SHA256 verification":'guard try digest(output) == expected.sha256' in backup,
 "zip slip prevented":'allowedPath(item.path)' in backup,
 "no links":'item.type == .file' in backup,
 "duplicate files rejected":'names.insert(item.path).inserted' in backup,
 "duplicate manifest safe":'indexed[record.path] == nil' in backup,
 "stage outside live vault":'".TakopiVault-restore-"' in backup,
 "authenticated index before publish":'try Self.authenticateEncryptedBackup(at: stage, password: password)' in session,
 "vault password verifier":'PrivateVaultCrypto.openSmall(config.verifier, key: candidateKey)' in session,
 "vault entries graph validation":'try validateLoadedIndex(restored)' in session,
 "referenced encrypted blobs present":'TakopiVaultBackup.BackupError.missingEncryptedFile' in session,
 "rollback on failure":'try? fm.moveItem(at: rollback, to: root)' in session,
 "replace only after lock":session.index('lock()\n        isBusy = true\n        let fm = FileManager.default',session.index("func importEncryptedBackup")) < session.index('try fm.moveItem(at: root, to: rollback)',session.index("func importEncryptedBackup")),
 "Face ID secrets reset only on success":'NikaidoUnlockPreference.disableBiometric()' in session and 'NikaidoSecFaceID.clearAll()' in session,
 "export via Files":'UIDocumentPickerViewController(' in picker and 'forExporting: [archiveURL], asCopy: true' in picker,
 "import via Files":'forOpeningContentTypes: [.data], asCopy: true' in picker,
 "user confirmation":'Reemplazar bóveda actual' in vault and 'showBackupRestorePrompt' in vault,
 "password input":'SecureField("Contraseña del respaldo"' in vault,
 "restore available when locked":'Label("Restaurar copia cifrada desde Archivos"' in vault,
 "version":pbx.count("MARKETING_VERSION = 0.12.20;")==2 and pbx.count("CURRENT_PROJECT_VERSION = 57;")==2,
 "new source files registered":all(x in pbx for x in ["A973","A974","B973","B974"]),
}
for name,success in checks.items():print(("[OK] " if success else "[FAIL] ")+name)
assert all(checks.values()),"Vault backup / IPA handoff regression"
