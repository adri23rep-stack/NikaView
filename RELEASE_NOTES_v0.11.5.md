# NikaView v0.11.5 — Build 36

## Protección de privacidad reforzada

- Cubre las escenas cuando se desactivan, además del aviso de salida de la app.
- Al bloquear el teléfono, detiene transferencia de red, invalida las sesiones cifradas y las reproducciones sensibles.
- Detecta grabación/duplicación de pantalla mediante avisos públicos de iOS y cubre el contenido.
- Al recibir una notificación de captura de pantalla, bloquea sin esperar 600 ms y muestra un aviso.

**Limitación importante:** iOS notifica las capturas de pantalla después de guardarlas. Esta versión **no puede impedir ni borrar** la primera captura con APIs públicas. Tampoco puede garantizar cobertura antes de que iOS empiece una grabación.

### Siguiente etapa
Rediseño de controles con Liquid Glass nativo iOS 26, conservando soporte iOS 16–25. Las acciones de la bóveda permanecen sin cambios funcionales.
