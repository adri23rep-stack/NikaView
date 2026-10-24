# Takopi Explorer v0.12.5 — Nueva identidad y distribución visual

- Nuevo nombre e icono plano de Takopi: pulpito con lupa detrás de una carpeta, elegido por el usuario.
- Icono incluido en la pantalla inicial y en el paquete de la app mediante Assets.xcassets/AppIcon.
- Controles Liquid Glass concentrados exclusivamente en las barras inferiores de Inicio, Explorador y Vault. Parte superior del Explorador despejada.
- Fondo de Inicio con seis círculos difuminados, amplitud y velocidades distintas. Respeta Reducir movimiento, Reducir transparencia y modo de bajo consumo.
- Takopi Vault: remate orgánico animado que sobresale del extremo derecho, en lugar de burbujas metidas en la tarjeta.
- Se conservan las transiciones entre pantallas, las funciones y la política de bloqueo inmediato al salir de la bóveda.

La migración modifica nombres de interfaz, no IDs, claves, rutas de datos, cifrado ni archivos guardados.

## Comprobación
GitHub Actions prepara un icono opaco 1024x1024, verifica la compilación de iOS y ofrece el IPA sin firma.
