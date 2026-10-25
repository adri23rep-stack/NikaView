# Takopi Ghost Explorer v0.5 — iOS 27

Aplicación experimental **separada** de Takopi/NikaView principal.

La prueba 0.3 recuperó 10,122 nombres de rutas diferentes en iOS 27 estable. Este prototipo convierte el resultado de un nuevo barrido en un árbol navegable y buscable, sin conceder acceso a archivos privados.

## Funciones

- Escaneo de metadatos limitado a cuatro segundos.
- Árbol completo de los nombres encontrados, expansión y búsqueda.
- Importar listas TXT de rutas y exportar nombres bajo demanda.
- Detalles de ruta y comprobación manual de si permite listar sus elementos.
- Deduplicación y límites de 1,500 filas visibles por vista para mejorar rendimiento.

Los directorios intermedios del árbol pueden ser inferidos, no detectados directamente. No se lee el contenido de archivos, no se elevan permisos y **no se ha portado ningún exploit**.

## Compilar

El workflow `Takopi iOS 27 Sandbox Probe` ejecuta nueve verificaciones de indexación y después compila un IPA para iPhone. El IPA está sin firmar: hace falta firmarlo antes de instalar.

**Advertencia:** la variante con identificador `org.nikaido.mirror.T449Z5SVHW` se genera por separado y podría sobrescribir Nikaido Mirror. Guarda un respaldo antes de instalarla.

Los reportes exportados pueden revelar nombres de archivos privados. No los publiques completos sin revisarlos.

Código fuente de referencia: https://github.com/forcequitOS/bad_query (el soporte de iOS 27 estable no está documentado por el autor).
