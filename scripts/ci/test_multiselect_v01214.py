#!/usr/bin/env python3
"""Static regression: safe multi-select in Takopi Files and encrypted Vault."""
from pathlib import Path
root = Path(__file__).resolve().parents[2]
files = (root / "SolidSecViewer/ExplorerView.swift").read_text()
vault = (root / "SolidSecViewer/PrivateVaultView.swift").read_text()
session = (root / "SolidSecViewer/PrivateVaultSession.swift").read_text()
drag = (root / "SolidSecViewer/PrivateVaultMultiDrag.swift").read_text()
pbx = (root / "SolidSecViewer.xcodeproj/project.pbxproj").read_text()
checks = {
    "Files top selection": 'Button(pane.selectionMode ? "Listo" : "Seleccionar")' in files,
    "Files already supports selected drag group": "dragItems(for: item)" in files and "pane.selectedItems" in files,
    "Files actions persist": "private var selectionToolbar: some View" in files,
    "Vault top selection": 'Button(selectionMode ? "Listo" : "Seleccionar")' in vault,
    "Vault select all": "selectedVaultIDs.formUnion(allIDs)" in vault and "selectedVaultIDs.subtract(allIDs)" in vault,
    "Vault group drag": "selectedVaultIDs.contains(entry.id)" in vault and "vaultDrag.begin(ids: ids" in vault,
    "Vault drag handle in selection mode": "El asa permanece visible aun con varios elementos seleccionados" in vault,
    "Vault destination chosen by UUID": "struct PrivateVaultDrop" in drag and "folderID: UUID?" in drag,
    "Vault drag carries no decrypted URL": "makeTemporaryDecryptedCopy" not in drag and "PrivateVaultCrypto" not in drag,
    "Vault supports parent folder target": '"parent|vault"' in vault,
    "Vault supports child folders": 'vaultMoveFolderProbe(vaultDrag, entry: entry)' in vault,
    "Vault movement confirmation": 'Mover archivos cifrados' in vault and 'pendingVaultDrag' in vault,
    "Vault bulk menu": "showBatchMovePicker" in vault and "showBatchDeleteConfirmation" in vault,
    "Vault password lock clears selection": "selectedVaultIDs.removeAll()" in vault and "vaultDrag.cancel()" in vault,
    "Single atomic encrypted index update": "func moveEntries(_ ids: Set<UUID>, to parentID: UUID?) throws" in session and "try persistIndex(candidate)" in session,
    "Cycle prevention": "descendantIDs(startingAt: entry).contains(parentID)" in session,
    "Collision prevention": "occupied.contains($0.name.lowercased())" in session,
    "No cipher file moving": "var updated = entry" in session and "updated.parentID = parentID" in session,
    "New drag source included": "A972" in pbx and "B972" in pbx,
    "Version correct": pbx.count("MARKETING_VERSION = 0.12.17;") == 2 and pbx.count("CURRENT_PROJECT_VERSION = 54;") == 2,
}
for label, passed in checks.items():
    print(("[OK] " if passed else "[FAIL] ") + label)
assert all(checks.values()), "Multi-select regression"
