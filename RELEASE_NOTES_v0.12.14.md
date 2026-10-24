# Takopi Explorer v0.12.14 (build 51) — selección múltiple

- Takopi Files: botón superior Seleccionar/Listo en cada panel. Al marcar varios archivos siguen disponibles Copiar, Mover, Compartir, Comprimir, Enviar a Vault y Eliminar, y puedes arrastrar el lote con el asa de uno de los seleccionados.
- Takopi Vault: botón Seleccionar/Listo arriba de las tarjetas. Muestra casillas, Seleccionar todos y menú para Mover, Renombrar (un elemento) o Eliminar.
- Takopi Vault: mover archivos y carpetas cifrados arrastrándolos sobre otra carpeta de Vault. Usa el asa disponible incluso durante la selección múltiple.
- Ficha flotante de arrastre que muestra cuántos archivos cifrados se llevan. Se puede soltar en una carpeta hija o en la zona del encabezado para volver a la carpeta superior. Antes de mover se confirma el destino.
- Movimiento en lote protegido y atómico: la operación modifica solamente las referencias del índice cifrado; no descifra blobs. Rechaza carpetas dentro de sí mismas, destinos no válidos y nombres duplicados; un error mantiene todo en su ubicación previa.
- Selección y arrastre se limpian cuando se bloquea la bóveda o la app pasa a segundo plano.
- Mantiene las mejoras de la 0.12.13: botón de Vault en Liquid Glass y arrastre de Files a Vault.

## Pendiente de prueba real
La compilación y las comprobaciones de código no sustituyen probar el gesto en LiveContainer y el redimensionado. Empezar con archivos no importantes, luego verificar un lote y una carpeta anidada.
