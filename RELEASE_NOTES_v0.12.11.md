# Takopi Explorer v0.12.11 — build 48

## Apertura más rápida de IPA grandes
- Escanea primero el índice de carpetas sin descomprimir el contenido; los detalles y el icono se leen después, con las carpetas ya visibles.
- Verifica el final del ZIP leyendo como máximo 65 557 bytes en lugar de buscar sin límite si el archivo está dañado o incompleto.
- En la lista de archivos evita el lector de iconos completo para IPA/APK de más de 512 MB: al abrirlos intentará mostrar los datos del icono en segundo plano.
- Reduce de 16 a 3 los iconos candidatos que se prueban en paquetes de más de 512 MB.
- Mantiene límites de seguridad, extracción individual y navegación en panel dividido.
- Mensaje claro si el paquete no está completo (por ejemplo, no está descargado desde iCloud).

Esta mejora evita descomprimir 1.65 GB para listar carpetas, pero no acelera transferencias ni descargas de iCloud.
Validado por CI; el rendimiento real en el IPA Samba de Amigo de 1.65 GB aún requiere prueba en iPhone.
