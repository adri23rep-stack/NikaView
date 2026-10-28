# Takopi Explorer v0.12.19 — Build 56

## Instalación más fácil con BloomBox
- Añadida la opción **Instalar con BloomBox** directamente al menú contextual de archivos .ipa y .tipa en Takopi Files (pulsación larga), además del botón que ya existe al abrir el explorador interno del IPA.
- El botón entrega el archivo real a la hoja nativa de compartir. Selecciona la extensión **Instalar IPA** de BloomBox: ella crea un marcador de acceso de seguridad y abre el instalador de BloomBox.
- No se usa el enlace `livecontainer://install?url=file://...` porque BloomBox no puede acceder a rutas privadas de otras aplicaciones. Si su extensión no está disponible, abre BloomBox y selecciona el IPA manualmente desde Archivos.
- No se requiere que Takopi lea el índice completo del IPA, por lo que el botón del menú contextual sirve también para archivos grandes.

## Copia completa de Takopi Vault
- Conserva **Exportar copia completa cifrada** e **Importar copia completa cifrada** en el menú de la bóveda; exporta mediante Archivos a iCloud Drive o En mi iPhone.
- La copia .tkvault incluye configuración, índices, blobs y miniaturas cifradas con verificación SHA-256. Importar requiere la contraseña del respaldo y confirmación para reemplazar la bóveda; valida antes de sustituir y permite recuperar la bóveda anterior si la operación falla.
- Ni la instalación de IPA ni el respaldo descifran archivos de la bóveda. No se modifica el formato del respaldo ya publicado en v0.12.18.

## Verificaciones
- CI: pruebas de integración y compilación iOS.
- Comprobar en dispositivo real la presencia de la extensión de BloomBox y respaldar a iCloud Drive antes de probar una restauración.
