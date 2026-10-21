# NikaView v0.12.4 — Visual Identity Refresh

## Novedades

- Emblema NikaView redibujado como componente vectorial, con degradado y relieve muy discreto que siguen el color de acento.
- Emblema independiente para Nikaido Vault y nuevo sistema uniforme de iconos para archivos, carpetas, categorías y almacenamiento.
- Inicio con una jerarquía visual más clara, detalles sutiles, tarjetas con respuesta al toque y animaciones de aparición por secciones.
- Transiciones suaves entre Inicio, Explorador y pantallas públicas.
- Pantalla de desbloqueo de Vault con icono propio y opciones de acceso más coherentes.

## Seguridad y accesibilidad

- Al salir de una bóveda desbloqueada se bloquea inmediatamente y el cambio de pantalla **no se anima**, para evitar que el contenido privado permanezca visible.
- Respeta Reducir movimiento y el modo de bajo consumo; los efectos decorativos ya existentes permanecen controlados.
- Conserva las burbujas de Vault, el saludo animado de la N, las opciones de Liquid Glass y las funciones previas.

## Pruebas

- Nuevas comprobaciones automáticas de iconos, animaciones, accesibilidad y salida segura de Vault.
- La compilación de iOS y el IPA se validan mediante el flujo existente de GitHub Actions; no se afirma compilación local.
