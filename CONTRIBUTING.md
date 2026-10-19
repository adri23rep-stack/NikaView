# Colaborar en NikaView

¡Gracias por contribuir! Este repositorio está en desarrollo y prioriza conservar los datos del usuario.

## Reportar un error

Abre un Issue con: descripción breve, versión de iOS, modelo del dispositivo, versión/build de la aplicación, pasos para reproducirlo, resultado esperado y resultado obtenido. Puedes incluir capturas o logs **después de eliminar información personal**.

## Proponer código

1. Explica el cambio propuesto en un Issue, si es importante o afecta formatos de datos.
2. Mantén los cambios pequeños y evita romper los identificadores heredados, las colecciones `.sec` o la bóveda.
3. Ejecuta los tests en `scripts/ci/` y comparte los resultados. Si tocas código iOS, ejecuta también GitHub Actions cuando sea posible.
4. Abre un Pull Request explicando qué cambiaste y qué **no** pudiste probar.

No subas bóvedas reales, archivos `.sec` privados, llaves, certificados, contraseñas, perfiles de firma ni datos de otras personas. Usa archivos de prueba sintéticos.

**Nota legal:** todavía no hay una licencia de contribución y reutilización definida para el código propio del proyecto. Aclara tus condiciones antes de enviar cambios sustanciales; las dependencias mantienen sus licencias independientes.
