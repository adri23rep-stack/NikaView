# NikaView v0.11.1 — Build 32

## Mejoras en esta versión

- **Video cifrado:** reproduce a 0.5×, 1×, 1.25×, 1.5× o 2×, y retoma desde la posición anterior. El punto guardado se almacena exclusivamente en el **Llavero protegido del dispositivo**, no en archivos abiertos ni en preferencias.
- **Arrastrar archivos:** desplazamiento automático de la lista o cuadrícula cuando acercas el dedo al borde superior/inferior de cualquiera de los dos paneles. El desplazamiento termina al soltar.
- **Archivos desde otras apps:** recepción con confirmación desde «Abrir en» cuando iOS reconozca una instalación independiente. No es una Share Extension de LiveContainer.
- **Accesibilidad:** acciones de apertura/selección y descripciones para VoiceOver en los paneles; títulos de inicio adaptados a Dynamic Type y botones de bóveda con etiquetas claras.
- **Seguridad:** se mantiene el cierre de reproductores de video al bloquear la bóveda; no se habilita PiP en medios cifrados mientras implique continuar el descifrado en segundo plano.

## Pendientes

La extensión nativa Compartir (limitada por firma y LiveContainer), PiP seguro, pulido exhaustivo de Dynamic Type, importación compleja desde iCloud y herramientas profesionales restantes siguen en el roadmap de GitHub.

## Validación

Este IPA se publica sin firmar tras pasar GitHub Actions y sus pruebas. No implica que todas las acciones de VoiceOver o drag se hayan probado en hardware.
