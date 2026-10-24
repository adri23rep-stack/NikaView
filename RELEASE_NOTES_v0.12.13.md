# Takopi Explorer v0.12.13 (build 50) — Arrastre y Liquid Glass

- Botón permanente con **candado** dentro de la cápsula Liquid Glass de Takopi Files, junto al divisor. Al tocarlo se abre Files + Vault en el panel dividido; al tocarlo de nuevo se vuelve a los dos paneles de Files.
- El menú de tres puntos conserva el acceso anterior por compatibilidad.
- Asa de arrastre ampliada a 44 × 44 puntos, activación más ágil tras 0.18 segundos, señales táctiles al elegir un destino y una ficha flotante que explica dónde se soltará el archivo.
- Las **carpetas normales de Vault** ahora son zonas válidas de destino. Se puede soltar un archivo directamente en una carpeta cifrada sin navegar hasta ella primero.
- Autodesplazamiento del panel de Vault al arrastrar cerca de los bordes.
- Resaltado visual en la carpeta de Vault elegida, confirmación que indica el nombre de la carpeta de destino y opciones claras para cifrar conservando o borrando originales.
- La importación sigue pasando por ExplorerVaultBridge y el motor cifrado de PrivateVaultSession. Los originales se eliminan solo cuando el lote completo termina correctamente.
- No habilita arrastre de datos cifrados hacia fuera, ni permite colocar archivos en carpetas reservadas a colecciones .sec.

**Pendiente:** prueba en iPhone de arrastre personalizado, precisión en carpetas bajo el dedo y redimensionado del panel. La compilación por CI no sustituye esa prueba.
