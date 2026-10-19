# NikaView

**Un explorador de archivos para iPhone, con dos paneles, conexiones de red y una bóveda privada.**

> **Estado:** proyecto experimental en desarrollo · **Plataforma:** iOS 16 o posterior · **Lenguaje:** Swift / SwiftUI
>
> **Versión actual del proyecto:** `0.10.5` (build `30`). El archivo ZIP original se llamaba `NikA-vIEW-v0.12.0.zip`; ese nombre no reflejaba la versión de Xcode.

NikaView es el nombre de este repositorio y del proyecto que seguiremos desarrollando. La aplicación todavía muestra el nombre **Nikaido Explorer** y mantiene identificadores internos anteriores para proteger la compatibilidad de los datos existentes. Cambiar el nombre visible se hará por separado, después de las pruebas correspondientes.

## ¿Qué incluye?

| Módulo | Funciones actuales |
| --- | --- |
| **Explorador** | Dos paneles independientes, carpetas, búsqueda, orden, favoritos, selección múltiple y operaciones de copiar, mover, renombrar, compartir y eliminar. |
| **Archivos externos** | Acceso a carpetas que elijas explícitamente desde el selector de documentos de iOS; mantiene permisos de acceso donde el sistema lo permite. |
| **Comprimidos** | Crear y extraer ZIP; extraer RAR (incluidos archivos con contraseña) y 7z, con límites y controles de seguridad. |
| **Nikaido Vault** | Bóveda privada con cifrado AES-256-GCM, contraseña, desbloqueo biométrico opcional, vistas de fotos y videos y miniaturas cifradas. |
| **Colecciones `.sec`** | Abrir/importar colecciones compatibles, gestionar contraseñas y reproducir contenidos admitidos. |
| **Red local** | Navegación SMB y transferencia desde la PC mediante Nikaido Link/Bridge, con mecanismos de reanudación. |
| **Personalización** | Apariencia clara/oscura, colores de acento y ajustes del explorador. |

Las funciones descritas aparecen en el código actual; **no equivalen a una certificación de funcionamiento en todos los iPhone**.

## Aspectos importantes

- **El target actual está configurado para iPhone** (`TARGETED_DEVICE_FAMILY = 1`); el soporte nativo de iPad está pendiente de revisión.
- **No es un jailbreak.** Acceder a una carpeta autorizada por el usuario no concede acceso a la raíz del sistema ni a los datos privados de otras aplicaciones.
- **La bóveda no sustituye una copia de seguridad.** Guarda respaldos de tus archivos antes de instalar una nueva versión o experimentar con migraciones.
- **La seguridad no cuenta todavía con una auditoría independiente.** Hay pruebas automáticas y protecciones implementadas, pero aún se necesitan pruebas reales y revisión externa.
- **La compilación automatizada genera una IPA sin firma**, preparada para pruebas en entornos compatibles, como LiveContainer. No es una instalación convencional desde App Store.
- La extracción de **7z tiene un límite deliberado de 384 MiB expandidos** en la ruta actual por el consumo de memoria.

## Publicar este código en GitHub (Windows)

El paquete incluye `PUBLICAR_NIKAVIEW_PUBLICO.bat`. Para crear **un repositorio nuevo y público llamado `NikaView`**:

1. Instala [Git para Windows](https://git-scm.com/downloads/win) y [GitHub CLI](https://cli.github.com/) si todavía no los tienes.
2. Revisa que esta carpeta no contenga ningún dato privado.
3. Ejecuta `PUBLICAR_NIKAVIEW_PUBLICO.bat`, inicia sesión con GitHub si se solicita y confirma escribiendo `PUBLICAR`.
4. El script creará `TU_USUARIO/NikaView`, subirá el código e imprimirá su enlace. Si ya existe un repositorio con ese nombre, **se detendrá sin sobrescribirlo**.

Para las siguientes actualizaciones existe `ACTUALIZAR_GITHUB.bat`: antes de usarlo, revisa los cambios porque sincroniza el repositorio con la carpeta local y puede eliminar archivos del remoto que no estén aquí.

## Cómo compilar

### Opción A: GitHub Actions

1. Abre la pestaña **Actions** del repositorio.
2. Elige **Build Nikaido Explorer IPA**.
3. Pulsa **Run workflow** sobre la rama `main`.
4. Al finalizar correctamente, descarga el artifact que contiene la **IPA sin firma**.

El workflow usa **macOS 15 + Xcode 16.4** y comprueba el proyecto, ejecuta pruebas y compila para **iPhone arm64**. La compilación depende también de las librerías externas que descarga Swift Package Manager.

### Opción B: Xcode en una Mac

Abre `SolidSecViewer.xcodeproj` con Xcode, espera a que se resuelvan los paquetes Swift y selecciona el target `SolidSecViewer`.

Puedes ejecutar las comprobaciones de Python desde la raíz del repositorio:

```bash
python3 scripts/ci/audit_project.py
python3 scripts/ci/test_explorer_core_v010.py
python3 scripts/ci/test_vault_auth_global_files_v0104.py
python3 scripts/ci/test_pc_sender.py
```

**Verificaciones realizadas al preparar esta publicación:** pasaron las nueve comprobaciones de Python incluidas en el preflight y la prueba del emisor para PC. **No se ejecutó una compilación de Xcode ni una prueba en hardware en este entorno.** La pestaña Actions será la referencia para comprobar la compilación iOS.

## Transferencia con Windows

Dentro de `tools/LANTransfer/` están el emisor Python y los asistentes de Windows, entre ellos `PREPARAR_PC.bat`, `NIKAIDO_BRIDGE.bat` y `ENVIAR_SEC_A_IPHONE.bat`. La PC y el iPhone deben poder comunicarse por la red local. Consulta `tools/LANTransfer/LEEME_PC.txt` y `tools/LANTransfer/README_LAN.txt` antes de usarlos.

No expongas el receptor de red directamente a internet ni compartas colecciones privadas, contraseñas o claves de la bóveda.

## Organización

```text
.github/workflows/          Compilación y validaciones de GitHub Actions
SolidSecViewer/             Código Swift de la aplicación
SolidSecViewer.xcodeproj/   Proyecto de Xcode (nombre técnico heredado)
scripts/ci/                 Auditorías y pruebas automáticas
scripts/SelfTest/           Pruebas Swift para formatos y cifrado
tools/LANTransfer/          Herramientas de transferencia desde PC
RELEASE_NOTES_*.md          Historial de cambios disponible
THIRD_PARTY_NOTES.md       Avisos sobre dependencias y licencias
```

## Dependencias principales

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) `0.9.20`
- [SWCompression](https://github.com/tsolomko/SWCompression) `4.8.6`
- [Unrar.swift](https://github.com/mtgto/Unrar.swift) `0.5.4`
- [AMSMB2](https://github.com/amosavian/AMSMB2) `4.0.3`

Cada dependencia conserva su propia licencia. **UnRAR y las dependencias relacionadas con SMB tienen condiciones particulares**: lee `THIRD_PARTY_NOTES.md` y sus licencias originales antes de distribuir binarios.

## Participar en el proyecto

Puedes reportar errores y proponer mejoras mediante **Issues** y **Pull Requests**. Para que un reporte sea útil, incluye tu modelo de iPhone, versión de iOS, pasos para repetir el error y registros **sin datos privados**. Consulta [CONTRIBUTING.md](CONTRIBUTING.md) y [SECURITY.md](SECURITY.md).

**Licencia del código propio:** todavía no se ha seleccionado una licencia de reutilización para NikaView. Que el repositorio sea público permite ver su código, **pero no concede automáticamente permisos para copiarlo, modificarlo o redistribuirlo**. Se añadirá una licencia explícita cuando se decida cuál corresponde.

---

*English summary: NikaView is an experimental iOS file manager with dual-pane browsing, an encrypted vault, archive support, SMB and local PC transfers. The app still uses the legacy “Nikaido Explorer” display name and identifiers. iOS builds are unsigned, and device compatibility is not guaranteed.*

## Descargar el IPA

La versión actual se publica en [GitHub Releases](https://github.com/adri23rep-stack/NikaView/releases). El IPA para LiveContainer se genera con GitHub Actions y se publica **solo si pasa las pruebas y validaciones**. Es un IPA **sin firmar**, no una app instalable desde App Store.
