# Takopi Ghost Explorer v0.7 — iOS 27

Explorador de **nombres de rutas**, experimental y separado de la versión principal de Takopi Explorer.

Los escaneos reales de iOS 27 estable permiten recuperar nombres con `fsgetpath`, incluso donde el sandbox prohíbe listar carpetas. **No permite abrir o copiar archivos protegidos, ni confirma un escape del sandbox**.

## Funciones

- Barrido limitado a 4 segundos y hasta 30,000 rutas en memoria.
- Árbol de nombres, búsqueda, filtros y clasificación por área.
- Inspector de permisos para comprobar manualmente el acceso a listados.
- Importación/exportación de listas TXT, sin envío automático.
- Análisis agregado por categorías y extensiones de nombre.
- **Comparar dos barridos:** importar un TXT anterior y mostrar rutas que aparecen solo en el nuevo, que dejan de observarse y que coinciden.
- **Compartir resumen sin rutas:** las estadísticas de comparación no incluyen nombres ni identificadores personales.

**Advertencia de interpretación:** una ruta no observada en un barrido parcial NO significa que se haya borrado. Los directorios intermedios inferidos en el árbol tampoco implican acceso.

## Prueba de comparación

1. Desde la pantalla principal, pulsa «Explorar rutas».
2. Abre «Comparar dos barridos».
3. Selecciona con el importador un TXT previo (compatibilidad con exportaciones de las versiones 0.5/0.6).
4. Revisa las diferencias por área, filtra por nombre o comparte únicamente el resumen agregado.

La comparación es **local**. No publiques archivos TXT completos sin revisarlos, pues pueden revelar nombres sensibles del dispositivo.

## Compilar e instalar

El workflow `Takopi iOS 27 Sandbox Probe` ejecuta pruebas del árbol, las categorías y la comparación de 10,122 rutas antes de compilar para iPhone.

El IPA de GitHub Actions está **sin firmar**. La variante `org.nikaido.mirror.T449Z5SVHW` se empaqueta aparte y puede reemplazar Nikaido Mirror: haz respaldo antes de instalarla.

No se modifican archivos del sistema ni se solicitan privilegios adicionales. No se ha portado `bad_query` a iOS 27 estable.
