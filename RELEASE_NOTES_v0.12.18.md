# Takopi Explorer v0.12.18 — build 55

## IPA → BloomBox
Al pulsar un archivo .ipa (o .tipa) dentro del explorador de paquetes ahora aparece **Instalar con BloomBox**.
Se usa la función de compartir/«Abrir en» de iOS: el usuario elige BloomBox, que ya declara compatibilidad con documentos. No se utiliza un enlace file:// a una ruta privada inaccesible desde otra app. Si BloomBox no aparece, guardar en Archivos e instalar desde el selector de IPA de BloomBox. La instalación requiere autorización del usuario y se efectúa dentro de BloomBox, no de forma silenciosa.

## Respaldo completo cifrado
- Menú Opciones de Takopi Vault → **Exportar copia completa cifrada**.
- El selector de Archivos permite elegir **En mi iPhone** o **iCloud Drive**.
- Formato **.tkvault** (ZIP interno con archivos cifrados): config principal y redundante, índice AES-GCM principal y anterior, blobs .ssvb y miniaturas cifradas .nkt.
- Se empaqueta en disco en fragmentos, sin descifrar fotos ni archivos y sin copiarlos a RAM. Manifiesto con SHA-256 para detectar respaldos incompletos; rutas estrictas para evitar extracción insegura.
- **Restaurar copia cifrada** aparece también en pantalla bloqueada, incluso antes de crear una bóveda. Pide la contraseña del respaldo, verifica índice/configuración/archivos y prepara la extracción fuera de la carpeta activa.
- Si existe otra bóveda, requiere confirmación explícita de reemplazo. El cambio se realiza con carpeta de respaldo para recuperación en caso de error; ningún archivo activo se elimina por un fallo durante validación.
- Al restaurar se debe usar la contraseña ORIGINAL del respaldo. Face ID y contraseñas de colecciones .sec almacenadas únicamente en el Llavero del iPhone no viajan en el respaldo y se deberán configurar otra vez.
- La copia incluye **los archivos cifrados**, no las transferencias de red incompletas ni los secretos del Keychain. Conserva el diseño, arrastre, cambio automático claro/oscuro y Liquid Glass.

**Seguridad:** no sustituir un respaldo único por otro sin probar su restauración. CI no demuestra por sí solo una restauración completa en un iPhone real.
