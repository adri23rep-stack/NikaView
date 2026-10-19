# NikaView v0.11.2 — Build 33

## Video y archivos

- Reproductor para MP4, MOV, M4V y audio compatible del explorador, con el control nativo Picture in Picture (PiP) cuando iOS y el entorno de instalación lo permitan.
- Continúan los controles de velocidad y progreso de video guardado en el Llavero de iPhone; los videos cifrados **nunca** continúan descifrando al cerrar la bóveda.
- Inspector de Mach-O/dylib: arquitectura, dependencias declaradas, indicador de firma sin verificar y marcador de cifrado, sin ejecutar binarios.
- Inspector de IPA/ZIP: lista limitada de archivos, detección de paquete .app y frameworks.
- Inspector de DEB: lectura de miembros ar sin extraerlos ni ejecutarlos.
- Navegador de SQLite: 50 filas por página y límite razonable de paginación. Base de datos abierta solo para lectura.

## Límites

- La disponibilidad de PiP depende de permisos y soporte del sistema; LiveContainer puede no exponerlo aunque la compilación sea correcta.
- El inspector solo analiza estructuras, **no verifica firmas ni garantiza que un binario sea seguro**.
- Sharing nativo por extensión, sincronización avanzada, video sin metadatos y demás funciones están pendientes en el roadmap.
