# Takopi Explorer v0.12.10 — build 47

- Abre IPA, APK y ZIP como paquetes: navega carpetas internas y busca por nombre sin instalar ni ejecutar código.
- Extracción individual segura al panel actual o al otro panel (si está abierto). El paquete original queda intacto.
- Reconocimiento visual de IPA/APK en lista y cuadrícula; usa los iconos PNG incluidos en el paquete cuando están disponibles y un icono de app si solo existen recursos compilados.
- IPA: muestra nombre, versión e identificador desde Info.plist. APK: explora sus archivos y busca iconos PNG convencionales.
- IPA y APK también se pueden extraer completos usando el extractor ZIP existente.
- Conserva ZIP, RAR y 7z; DEB/DYLIB continúan en el inspector existente.

## Límites intencionales
- Assets.car de iOS y el formato binario de recursos Android no se decodifican aún: algunos iconos usarán el distintivo genérico.
- La navegación por carpetas de RAR/7z y el navegador de paquetes DEB quedan para futuras etapas.
- No permite modificar ni volver a firmar aplicaciones.
- Máximo 100,000 entradas al listar; máximo 1 GiB por extracción individual; rechaza symlinks y rutas peligrosas.

Pruebas: CI de GitHub Actions + verificación de comportamiento en iPhone pendiente.
