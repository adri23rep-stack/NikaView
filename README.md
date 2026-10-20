# NikaView

**Un explorador de archivos para iPhone, con dos paneles, conexiones de red y una bóveda privada.**

> **Estado:** proyecto experimental en desarrollo · **Plataforma:** iOS 16 o posterior · **Lenguaje:** Swift / SwiftUI
>
> **Versión actual del proyecto:** `0.12.1` (build `38`). El archivo ZIP original se llamaba `NikA-vIEW-v0.12.0.zip`; ese nombre no reflejaba la versión de Xcode.

NikaView es el nombre de este repositorio y del proyecto que seguiremos desarrollando. La aplicación todavía muestra el nombre **Nikaido Explorer** y mantiene identificadores internos anteriores para proteger la compatibilidad de los datos existentes. Cambiar el nombre visible se hará por separado, después de las pruebas correspondientes.

## NikaView v0.12.1 — Detalles minimalistas del inicio

- Globo «¡Hazme click!» junto a la N animada para descubrir Ajustes; desaparece después de unos segundos o al tocarla, y recuerda cuando ya la usaste.
- Tarjeta Nikaido Vault rediseñada: contorno limpio, color sobrio y pequeñas burbujas dentro del botón, sin protuberancias.
- Fondo con tres círculos difuminados en movimiento lento tipo lámpara de lava.
- Respeta accesibilidad de movimiento/transparencia reducidos y modo de bajo consumo.
- Las seis acciones Liquid Glass de la bóveda ahora flotan abajo, separadas del título de la carpeta, con compatibilidad para iOS anteriores.

## NikaView v0.12.0 — Seguridad + Liquid Glass

- **Bóveda:** protección adicional al desactivarse la escena, al bloquearse el teléfono y al empezar una grabación detectada; los recursos cifrados se invalidan al bloquear.
- **Capturas:** iOS notifica cuando ya se tomó la captura; NikaView bloquea después del aviso, **no puede impedir ni borrar la primera captura**.
- **Liquid Glass nativo en iOS 26+:** seis acciones de la bóveda en una sola fila translúcida, ahora anclada en la parte inferior; el nombre de la carpeta permanece arriba.
- **Explorador:** barra principal y botón flotante de crear con efecto de vidrio.
- **iOS 16–25:** conserva las mismas funciones mediante un material translúcido compatible. La opción Reducir transparencia utiliza controles opacos.
- **GitHub Actions:** compilación verificada con Xcode 26.6, iOS SDK 26, sin errores ni advertencias del código.

**Descargar:** [v0.12.0 (IPA para LiveContainer)](https://github.com/adri23rep-stack/NikaView/releases/tag/v0.12.0). El cambio visual todavía necesita pruebas en iPhone real.

## Novedades recientes — v0.11.3 y v0.11.4

- **Sincronización bidireccional:** compara los dos paneles, propone archivos ausentes y deja conflictos sin tocar hasta elegir manualmente qué copiar. Crea respaldos antes de reemplazos y nunca elimina originales.
- **Compartir videos sin metadatos:** admite MP4/MOV/M4V y genera una nueva copia MOV. Filtra los metadatos identificables, revisa fecha/GPS/ubicación/autor conocidos tras exportar y rechaza la copia cuando la comprobación detecta información sensible. No borra ni modifica el original.
- **Validación:** el código pasó todas las pruebas de GitHub Actions y se publicó en [Releases v0.11.4](https://github.com/adri23rep-stack/NikaView/releases/tag/v0.11.4). Las funciones nuevas aún necesitan pruebas en un iPhone real.
- **Límites:** máximo 1,500 entradas por panel en esta sincronización. La exportación de video puede volver a codificar y usa almacenamiento temporal. No garantiza identificar cualquier formato propietario de metadatos.

## Novedades recientes — v0.11.1 y v0.11.2

- **Videos:** guardar el punto de reproducción en el Llavero, ajustar velocidad y Picture in Picture para videos **no cifrados** del explorador cuando iOS lo permita.
- **Arrastrar y soltar:** desplazamiento automático cerca de los bordes.
- **Archivos:** inspector de IPA/ZIP, Mach-O/dylib y DEB con vista hexadecimal, SQLite paginado y mejoras de VoiceOver.
- **Abrir en NikaView:** recepción de documentos por el sistema en instalaciones independientes; **no equivale** a una Share Extension funcional dentro de LiveContainer.
- Las colecciones cifradas siguen bloqueando el video al salir de la bóveda. Algunas funciones requieren pruebas en iPhone y no se afirma que PiP esté disponible en LiveContainer.

**Descarga:** [NikaView v0.11.2](https://github.com/adri23rep-stack/NikaView/releases/tag/v0.11.2) · [Pendientes](https://github.com/adri23rep-stack/NikaView/issues/1).

## Novedades en v0.11.0

- **Fotos y videos a la bóveda:** selector del carrete, cifrado al importar y opción de solicitar el borrado de originales **solo tras verificar que se importaron todos**, con confirmación adicional de iOS.
- **Herramientas avanzadas:** inspector de cabeceras IPA, ZIP, DEB y dylib; hexadecimal inicial; vistas JSON/plist; tablas SQLite en modo lectura.
- **Búsqueda local:** nombres, contenido de archivos y PDF, objetos y texto reconocidos en imágenes de carpetas autorizadas (sin conexión a servidores).
- **Archivos:** comparación de paneles, sincronización unidireccional con copias de respaldo, mapa de espacio, renombrado masivo con vista previa, exportación de imágenes sin metadatos y hasta diez revisiones locales de textos.
- **Pulido:** diálogo para mover o copiar al soltar, carpetas recientes y favoritas desde Inicio, y acceso directo a SMB.

Las herramientas tienen límites para proteger el rendimiento: el inspector no hace análisis profundo de firmas, la sincronización no borra ni replica continuamente y el limpiador de metadatos todavía no procesa video. **Estas mejoras pasaron GitHub Actions, pero necesitan pruebas manuales en iPhone.**

### Próximas funciones

Las funciones que aún faltan (Share Extension real de iOS, Picture in Picture, velocidad/posición de video, desplazamiento automático al arrastrar, mejoras completas de VoiceOver y otras ampliaciones) están documentadas en [el roadmap del proyecto](https://github.com/adri23rep-stack/NikaView/issues/1).

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
