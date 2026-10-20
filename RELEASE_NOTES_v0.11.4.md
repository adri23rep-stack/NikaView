# NikaView v0.11.4 — Build 35

## Limpiar datos de videos antes de compartir

- «Compartir sin metadatos» ahora acepta además MP4, MOV y M4V.
- Genera una copia temporal MOV con los metadatos exportados vacíos y un filtro de privacidad para no trasladar datos identificables.
- Después de exportar, reabre la copia y revisa metadatos de fecha, ubicación, GPS, autor y equipo; si detecta datos sensibles, **no permite compartirla**.
- El original nunca se modifica ni elimina. Las copias temporales se limpian al cerrar la herramienta.
- Exportación compatible con iOS 16+ y ruta moderna para iOS 18+. Puede tardar y volver a codificar el video.

## Limitaciones

- El contenedor nuevo puede mostrar la fecha de creación actual; no es la fecha original de grabación.
- La herramienta revisa metadatos AVFoundation estándar, pero no garantiza detectar todos los campos privados de formatos propietarios.
- Prueba con copias de ejemplo antes de compartir material sensible. La firma e instalación en LiveContainer podrían afectar funciones del sistema.
