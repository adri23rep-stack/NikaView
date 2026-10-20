# NikaView v0.11.3 — Build 34

## Sincronización segura entre los dos paneles

- Nueva opción **Sincronizar en ambos sentidos** desde la comparación de carpetas.
- Vista previa de archivos faltantes y archivos diferentes en ambos paneles.
- Los conflictos se **omiten de forma predeterminada**: para reemplazar debes elegir una dirección concreta para cada archivo y confirmar.
- No elimina archivos ni carpetas. Crea un respaldo con nombre único antes de reemplazar un archivo.
- Recomprueba archivos y rutas después de la vista previa y antes de guardar; si cambiaron, detiene la operación.
- Bloquea enlaces simbólicos y la sincronización de carpetas idénticas o anidadas.
- Límite de 1,500 elementos por panel; si se supera, no hace una copia parcial inadvertida.
- Incorpora verificaciones automáticas en GitHub Actions.

## Pendiente de comprobar en iPhone

La compilación automatizada no demuestra que todos los proveedores de Archivos e iCloud respeten los mismos permisos. Prueba primero con carpetas de ejemplo, y verifica los respaldos antes de usar datos importantes.

## Compatibilidad

iOS 16+, arquitectura arm64. IPA sin firma orientado a pruebas en LiveContainer.
