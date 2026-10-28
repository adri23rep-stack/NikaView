#!/usr/bin/env python3
"""UI contracts for compact, accessible Files/Vault selection toolbars."""
from pathlib import Path
root=Path(__file__).resolve().parents[2]
ex=(root/"SolidSecViewer/ExplorerView.swift").read_text()
vault=(root/"SolidSecViewer/PrivateVaultView.swift").read_text()
theme=(root/"SolidSecViewer/NikaidoTheme.swift").read_text()
proj=(root/"SolidSecViewer.xcodeproj/project.pbxproj").read_text()
a=ex.split("private var selectionToolbar: some View {",1)[1].split("private func pane(at index:",1)[0]
b=vault.split("private var vaultSelectionToolbar: some View {",1)[1].split("private func moveSelectedVaultEntries",1)[0]
checks={
    "Files count has adaptive single line": "TakopiSelectionCount(count: active.selectedItems.count)" in a,
    "Vault count has adaptive single line": "TakopiSelectionCount(count: selectedVaultIDs.count)" in b,
    "count never wraps": 'ViewThatFits(in: .horizontal)' in theme and '.lineLimit(1)' in theme.split("struct TakopiSelectionCount: View",1)[1].split("struct NikaidoGlassActionStyle",1)[0],
    "44-point touch targets": '.frame(width: 44, height: 44)' in theme,
    "Files no text labels in buttons": 'Label("Copiar"' not in a and 'Label("Mover"' not in a,
    "Files keeps copy move and more": 'systemName: "doc.on.doc"' in a and 'systemName: "folder.fill", prominent: true' in a and 'systemName: "ellipsis"' in a,
    "Vault keeps move and more": 'systemName: "folder.fill", prominent: true' in b and 'systemName: "ellipsis"' in b,
    "Files select all toggle": "active.clearSelection()" in a and "active.selectAll()" in a,
    "Vault select all toggle": "selectedVaultIDs.subtract(allIDs)" in b and "selectedVaultIDs.formUnion(allIDs)" in b,
    "Files actions accessible": 'accessibilityLabel("Copiar seleccionados")' in a and 'accessibilityLabel("Mover seleccionados")' in a,
    "Vault actions accessible": 'accessibilityLabel("Mover seleccionados")' in b,
    "no deletion moved outside confirmation": "requestDelete(active.selectedItems" in a and "showBatchDeleteConfirmation = true" in b,
    "accent can be yellow with contrast": "accent.opacity(0.25)" in theme and ".foregroundStyle(.primary)" in theme,
    "version 0.12.15":proj.count("MARKETING_VERSION = 0.12.18;")==2 and proj.count("CURRENT_PROJECT_VERSION = 55;")==2
}
for n,v in checks.items(): print(("[OK] " if v else "[FAIL] ")+n)
assert all(checks.values()),"Compact selection toolbar regression"
