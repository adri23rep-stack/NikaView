# Takopi Explorer v0.12.12 — build 49

- El icono de la cabecera de Inicio ahora es el pulpo Takopi plano, sin el recuadro, carpeta ni logo de la aplicación. Se conservan la animación de brinco, el globo "¡Hazme click!" y la acción para abrir Ajustes.
- Nueva opción **Acciones → Takopi → Bóveda en pantalla dividida**. Reutiliza el divisor arrastrable existente (16 puntos, color de acento).
- Panel secundario Takopi Vault: desbloqueo por contraseña si ya existe, listado de carpetas y archivos cifrados, navegación dentro de carpetas, acceso a bóveda completa y botón para regresar a dos paneles de archivos.
- Arrastra archivos y carpetas desde Takopi Files al panel de Takopi Vault mediante el asa de arrastre existente. Confirma **Cifrar y conservar originales** o **Cifrar y borrar originales** antes de empezar.
- La transferencia usa la misma sesión cifrada y el puente de importación existente. No se crea una carpeta descifrada espejo de la bóveda.
- Cada elemento se valida contra el almacenamiento autorizado. Solo se borran originales después de que todos los elementos hayan sido cifrados correctamente, y si la bóveda sigue desbloqueada.
- Cerrar el panel dividido vuelve a Takopi Files sin cerrar automáticamente la bóveda. El bloqueo global conserva los controles de privacidad anteriores.

## Límites
- La vista dividida está enfocada en **introducir archivos a la bóveda**. Para exportar archivos desde Vault se usa de momento la bóveda completa y su procedimiento de exportación controlada.
- Los archivos cifrados se muestran sin descifrarlos en el panel para evitar copias expuestas.
- Las optimizaciones para IPA grandes continúan en análisis; esta versión no afirma resolver todos los casos de IPA de 1.65 GB.
- Las pruebas CI son automatizadas; se debe probar la interacción de arrastre y el cifrado en iPhone.
