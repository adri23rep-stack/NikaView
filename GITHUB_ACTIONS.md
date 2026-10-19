# Compilar NikaView con GitHub Actions

NikaView se compila en un runner de **macOS 15** con **Xcode 16.4**. No hace falta tener una Mac para ejecutar el flujo desde GitHub.

> **Versión técnica actual:** 0.10.5 (build 30). El ZIP original llevaba el nombre v0.12.0, pero no hay evidencia de que esa versión se haya actualizado en el proyecto Xcode.
>
> El resultado es un **IPA sin firmar, destinado a pruebas con LiveContainer**. No es un IPA firmado para instalación normal ni una publicación de App Store.

## Cómo compilar

1. Abre [Actions — NikaView](https://github.com/adri23rep-stack/NikaView/actions).
2. Selecciona **Build Nikaido Explorer IPA**.
3. Haz clic en **Run workflow** y elige la rama `main`.
4. Al finalizar, entra en la ejecución y descarga el artefacto **NikaidoExplorer-LiveContainer-v0.10.5**.
5. Descomprime el artefacto; incluye `NikaidoExplorer-LiveContainer-v0.10.5.ipa`.

El flujo también se ejecuta automáticamente al subir cambios a `main` que afecten al código, proyecto de Xcode, scripts de pruebas, herramientas de PC o al propio workflow.

## Comprobaciones que ejecuta

- Preparación y revisión del SDK de iPhone, plist, proyecto Xcode y sintaxis Swift.
- Auditoría del proyecto y pruebas de protección de datos.
- Autopruebas de cifrado, formatos `.sec` y compatibilidad del índice.
- Resolución de las dependencias Swift Package Manager.
- Pruebas del cliente de transferencia por red para PC.
- Compilación iPhoneOS Release arm64 con firma desactivada.
- Revisión de advertencias del código, bundle y dependencias dinámicas (AMSMB2).
- Creación y validación del IPA.

Si alguna prueba falla, **el IPA no se publica como artefacto exitoso**. En su lugar, consulta el artefacto de diagnóstico `NikaidoExplorer-build-diagnostics-v0.10.3`, el resumen de pasos y los logs de `xcodebuild`.

## Seguridad y límites

- El proyecto se publica como código fuente; nunca incluyas bóvedas reales, archivos `.sec` privados, certificados, perfiles de firma ni credenciales.
- El IPA generado no tiene firma; GitHub Actions no instala aplicaciones en tu iPhone.
- La ejecución verde indica que pasó la compilación y las pruebas automatizadas; **no sustituye** probarlo en un iPhone real.
- No cambies el identificador heredado de la app sin planificar primero la migración de datos.

## Publicación en Releases

Cada cambio a `main` que dispare GitHub Actions se compila y prueba antes de publicarse. Si todo termina correctamente, el flujo lee la versión y compilación del `Info.plist` **del ejecutable generado**, crea la etiqueta `vX.Y.Z` y publica el IPA sin firmar en [GitHub Releases](https://github.com/adri23rep-stack/NikaView/releases), junto con `RELEASE_NOTES_vX.Y.Z.md`.

La versión debe ser nueva: si esa etiqueta de Release ya existe, el flujo **no la sobrescribe**. Es necesario incrementar `MARKETING_VERSION` y `CURRENT_PROJECT_VERSION` para publicar una nueva mejora. Ejecutar el flujo manualmente desde Actions solo genera un artefacto de prueba y no publica una nueva Release.
