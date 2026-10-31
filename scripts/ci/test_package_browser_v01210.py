#!/usr/bin/env python3
"""Verifica contratos de integración del explorador de paquetes v0.12.10."""
from pathlib import Path
root = Path(__file__).resolve().parents[2]
pkg = (root / "SolidSecViewer/ExplorerPackageBrowser.swift").read_text()
view = (root / "SolidSecViewer/ExplorerView.swift").read_text()
model = (root / "SolidSecViewer/ExplorerModels.swift").read_text()
archive = (root / "SolidSecViewer/ExplorerArchiveManager.swift").read_text()
project = (root / "SolidSecViewer.xcodeproj/project.pbxproj").read_text()
inspector = (root / "SolidSecViewer/NikaidoBinaryInspector.swift").read_text()
checks = {
    "IPA y APK reconocidos": '"ipa", "apk", "zip"' in pkg,
    "Explora entradas sin instalar": "static func read(_ url: URL)" in pkg,
    "Verifica rutas antes de extraer": "validatedComponents(path)" in pkg,
    "Rechaza enlaces al exportar": "entry.type == .file" in pkg,
    "Extracción limitada": "maxExportFile" in pkg,
    "Escritura temporal segura": ".takopi-package-" in pkg and "fm.moveItem(at: temporary" in pkg,
    "Extracción al otro panel": 'Button("Extraer al otro panel")' in pkg,
    "Lee metadatos de IPA": '"CFBundleIdentifier"' in pkg,
    "Icono PNG opcional": "UIImage(data: data)" in pkg and "ExplorerPackageIconStore" in pkg,
    "Enlace con interfaz": "ExplorerPackageBrowserView(target: target)" in view,
    "Miniaturas lista y cuadrícula": view.count("item.isAppPackage") >= 4,
    "Modelo IPA/APK": '"ipa", "apk"' in model,
    "ZIP de IPA y APK": 'case "zip", "ipa", "apk":' in archive,
    "Inspector APK": 'case "ipa", "apk", "zip"' in inspector,
    "Código incluido en Xcode": "A960" in project and "B960" in project,
    "Versión correcta": project.count("MARKETING_VERSION = 0.12.21;") == 2 and project.count("CURRENT_PROJECT_VERSION = 59;") == 2,
}
for label, ok in checks.items():
    print(("[OK] " if ok else "[ERROR] ") + label)
assert all(checks.values()), "Integración incompleta"
