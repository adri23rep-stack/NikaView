#!/usr/bin/env python3
"""Regresión de arrastre seguro con acceso directo desde Liquid Glass."""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
view = (root / "SolidSecViewer/ExplorerView.swift").read_text()
drag = (root / "SolidSecViewer/ExplorerDragMove.swift").read_text()
pane = (root / "SolidSecViewer/ExplorerVaultSplitPane.swift").read_text()
project = (root / "SolidSecViewer.xcodeproj/project.pbxproj").read_text()

checks = {
    "botón Vault dentro de Liquid Glass": view.index('Image(systemName: vaultPaneOpen ? "lock.open.fill" : "lock.shield")') < view.index('Menu {',view.index('private var explorerBottomDock')),
    "sin navegación extra": "openVaultSplit()" in view and "showTwoFilePanes()" in view,
    "mantiene divisor ajustable": "ExplorerResizableSplit(fraction: $splitFraction)" in view,
    "asa más accesible": ".frame(width: 44, height: 44)" in drag,
    "arrastre con una pulsación corta": "LongPressGesture(minimumDuration: 0.18)" in drag,
    "vista previa destino": 'Suelta aquí' in drag and 'Lleva al panel de destino' in drag,
    "respuesta táctil al apuntar": "NikaidoTheme.haptic(.light)" in drag,
    "identificador de destino en carpeta cifrada": "case vaultFolder(UUID)" in drag,
    "zona por carpeta cifrada": "func explorerVaultFolderProbe(" in drag and ".explorerVaultFolderProbe(dragState, entry: entry)" in pane,
    "rechaza carpetas especiales para soltar": "!entry.isSecCollectionFolder" in pane and "!entry.isSecCollectionFolder" in drag,
    "prioriza carpeta sobre panel": drag.index("for entry in vaultFolderProbes.values") < drag.index("for (index, entry) in paneProbes"),
    "cifrado en carpeta seleccionada": "case .vaultFolder(let id) where splitOpen && vaultPaneOpen" in view and "destinationFolderID: id" in view,
    "arrastre sistema también acepta carpeta": "handleVaultDrop(providers, destinationFolderID: id)" in view,
    "muestra nombre de destino": 'privateVault.folderName(vaultSendDestinationID)' in view,
    "cifrado antes del borrado": view.index("try await ExplorerVaultBridge.send(") < view.index("try await ExplorerFileEngine.delete(items, root: root)"),
    "conservar original": "performSendToVault(deleteOriginals: false)" in view,
    "versión actual": project.count("MARKETING_VERSION = 0.12.19;") == 2 and project.count("CURRENT_PROJECT_VERSION = 56;") == 2,
}
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)
assert all(checks.values()), "Regresión del arrastre a la bóveda"
