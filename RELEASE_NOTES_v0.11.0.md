# NikaView v0.11.0 · Build 31

Nueva caja de herramientas del explorador, importación desde Fotos y mejoras de usabilidad.

## Incluido

- Importación de fotos y videos seleccionados desde la fototeca a la bóveda cifrada. Borrado opcional de originales **solo tras verificar que se importaron todos** y mediante doble confirmación (NikaView e iOS); el resultado depende de los permisos de Fotos.
- Inspector de archivos IPA/ZIP/DEB/dylib con cabeceras y visor hexadecimal limitado a los primeros 4 KB; vista JSON, plist y lectura de tablas SQLite limitada a 50 filas por tabla. No ejecuta archivos binarios.
- Búsqueda local por nombre, texto dentro de archivos y PDFs y reconocimiento local de texto y objetos en imágenes de carpetas autorizadas; con límite de archivos y resultados para evitar bloqueos.
- Comparación de dos carpetas, con sincronización de archivos faltantes o más nuevos en una sola dirección, confirmación explícita y copia de respaldo de archivos que se reemplazan. No elimina archivos solo por faltar en origen.
- Mapa de tamaños de carpetas, renombrado masivo con vista previa, copias PNG sin metadatos para compartir y hasta 10 revisiones locales por archivo de texto modificado con el editor.
- Diálogo Mover/Copiar al soltar mediante el sistema de arrastre personalizado.
- Inicio: carpetas recientes, accesos rápidos a favoritos y acceso directo a SMB.
- Se conservan el arreglo anterior del Face ID duplicado y las opciones actuales de desbloqueo .sec.

## Límites conocidos

- El visor de IPA/DEB/dylib es **inspección inicial de cabeceras y bytes**, no análisis exhaustivo de permisos, firmas o dependencias.
- La búsqueda visual se realiza en las imágenes de carpetas accesibles por el explorador; no indexa en secreto toda la fototeca. Las etiquetas pueden ser más precisas en inglés.
- Limpieza de metadatos: imágenes compatibles únicamente, no videos.
- La sincronización de carpetas es **unidireccional** y no es una réplica bidireccional continua; no elimina archivos.
- No se añade todavía una extensión de compartir iOS, el desplazamiento automático de arrastre, mejoras PiP de video ni un modo nuevo de VoiceOver. Estas funciones requieren trabajo adicional y no se anuncian como implementadas.

## Instalación

Compilado para iOS 16+, arm64. El IPA distribuido no está firmado y está destinado a pruebas mediante LiveContainer. La versión no está verificada manualmente en iPhone hasta que se pruebe en un dispositivo.
