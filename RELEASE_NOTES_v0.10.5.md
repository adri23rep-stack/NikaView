# NikaView v0.10.5 — Build 30

Fecha: 19 de octubre de 2026

## Cambios

- Eliminada la **solicitud extra de Face ID** al elegir una colección cifrada `.sec` dentro de la bóveda.
- Al tocar una colección `.sec` o abrirla desde su menú contextual, ahora se muestra directamente la pantalla para elegir **Face ID o contraseña de la colección**.
- La colección permanece cifrada hasta que el usuario se autentica en esa pantalla.
- Se mantienen los controles de seguridad de la bóveda para otros archivos y operaciones.
- Añadidas pruebas estáticas para detectar si regresa la verificación duplicada.
- El IPA toma la versión del `Info.plist` compilado y GitHub Actions publica automáticamente las versiones que superen sus comprobaciones.

## Compatibilidad

- iOS 16 o posterior, arquitectura arm64.
- IPA **sin firmar**, preparado para pruebas mediante LiveContainer.
- Se conserva el nombre interno `SolidSecViewer` y los identificadores anteriores para no alterar los datos guardados.

## Validación

La compilación, las pruebas y la publicación deben completar correctamente en GitHub Actions. Publicar la Release no sustituye comprobar el comportamiento en un iPhone real.
