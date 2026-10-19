# Nikaido Explorer v0.10.4 — auditoría de Vault, carpetas, miniaturas y filtro global

Cambios hechos por inspección del código. **No se compiló con Xcode en este entorno**; la validación real es el workflow de GitHub Actions (build + cero warnings) y una prueba en un iPhone.

## Bug 1 — Seguridad al abrir archivos de la bóveda
- Nueva barrera por archivo (`NikaidoFileAuth`, `protectedOpen` en `PrivateVaultView`): antes de abrir una imagen/video, un ZIP o galería `.sec`, exportar una copia descifrada o guardarla en el Explorador, se pide Face ID. Si Face ID no está disponible, falla o el usuario elige la contraseña, se pide la contraseña de la bóveda.
- Cancelar o fallar nunca ejecuta la acción (`.cancelled` no hace nada; el resto exige contraseña).
- `PrivateVaultSession.verifyPassword` valida la contraseña derivando la clave y comparándola en tiempo constante con la que ya está en memoria. No se guarda ni se muestra ninguna contraseña.
- Las miniaturas de la cuadrícula ya no se descifran ni se muestran hasta que el usuario las revela (menú ⋯ → "Mostrar miniaturas", pide identidad). Se ocultan al bloquear, al pasar a segundo plano o al desactivar la protección.
- Ajuste en el menú de la bóveda: "Pedir identidad al abrir archivos" (activado por defecto; apagarlo también pide identidad).
- Sin cambios de formato: los archivos existentes siguen siendo compatibles. La caché de miniaturas ya estaba cifrada y los temporales ya se borraban al bloquear.

## Bug 2 — Carpetas locales de "En mi iPhone"
- Si el permiso del selector no llega, se intenta una segunda vía (ida y vuelta por un bookmark) antes de rechazar la carpeta.
- Mensajes de error comprensibles (`ExplorerErrorText`): permisos (513/257, EPERM/EACCES), archivo inexistente, disco lleno, solo lectura.
- El mensaje de rechazo explica que iOS no permite carpetas del sistema ni de otras apps.
- Limitación: iOS solo da acceso a lo que el usuario elige en Archivos. No pude probar esto en un iPhone real.

## Bug 3 — Carpetas agregadas en la raíz
- Cada ubicación muestra su origen (iCloud Drive, En mi iPhone, Otro proveedor, Nikaido Explorer) con su ícono.
- Una misma carpeta no se duplica aunque iOS cambie la ruta (se compara también la identidad real del archivo).
- Las referencias caducadas, movidas o con permiso revocado ya no desaparecen: aparecen en "No disponibles" con el motivo, con "Reintentar acceso" y "Quitar". Volver a añadir la carpeta reemplaza la referencia vieja.

## Bug 4 — Miniaturas de video encimadas
- Causa: la imagen escalada para llenar se dibujaba dentro del `ZStack` que definía el tamaño, así que su tamaño interno desbordaba la celda. Ahora el tamaño lo fija un `Color.clear` con proporción fija y la imagen se dibuja encima y se recorta (Bóveda y Explorador).

## Bug 5 — Filtro global
- Menú ⋯ → "Todos los archivos": filtros Todos / Fotos / Videos / Texto (TXT, MD, RTF y los demás formatos de texto del proyecto), búsqueda por nombre, miniatura, origen y ruta.
- Escaneo en segundo plano con resultados progresivos, sin duplicados, sin seguir enlaces simbólicos, con tope de 25 000 archivos y aviso de carpetas que no se pudieron leer.
- Abrir un archivo (editor o vista previa) y "Mostrar en su carpeta". Si el archivo ya no existe se quita de la lista y se avisa.
- La bóveda NO se indexa. La caché es solo en memoria (90 s), nada se escribe en disco.

## Bug 6 — Otros
- Se quitó un `first!` en la papelera (ahora tiene alternativa).
- Mensajes de error del Explorador unificados.

## Arrastrar y soltar (carpetas y entre paneles)
- Causa de que no funcionara: el arrastre del sistema (`onDrag`/`onDrop`) depende de la sesión de UIKit y no es fiable en este entorno (LiveContainer). Se reemplazó por un gesto propio.
- Cómo se usa: mantén presionada el asa (≡) de un archivo o carpeta ~0.25 s, arrastra y suelta sobre una carpeta (se resalta) para moverlo ahí, o sobre el otro panel para moverlo a su carpeta actual. Aparece una "sombra" con el nombre que sigue al dedo.
- Si el archivo está seleccionado junto con otros, se mueven todos los seleccionados.
- No permite mover algo adonde ya está, ni una carpeta dentro de sí misma o de sus subcarpetas.
- Límite: no hay auto-scroll al arrastrar cerca de los bordes.
- La posición de carpetas y paneles se lee en vivo al soltar, así que funciona aunque la lista se haya desplazado.

## v0.10.6 — miniaturas .sec, Face ID con contraseña guardada, audio
- Miniaturas encimadas: faltaban las de los visores de colecciones `.sec` y ZIP (`VaultThumbnail`, `StoredSecCollectionThumbnail`). Mismo arreglo (contenedor fijo + imagen recortada encima).
- Face ID: Face ID libera la contraseña guardada en el Llavero (cifrada por iOS, protegida por Face ID, solo en este iPhone) y se comprueba contra la clave real de la bóveda; no hay que escribir la contraseña. Si Face ID falla o eliges "Usar contraseña", se pide la contraseña. Después de escribirla se ofrece guardarla para usar Face ID. Si el Llavero no deja guardarla, el aviso muestra el código de error.
- Audio: si cerrabas el visor mientras el video se preparaba, el reproductor se creaba igual y seguía sonando. Ahora se descarta si el visor ya no está, y solo hay un video activo a la vez.

## v0.10.7 — carpetas añadidas en el inicio
- En el inicio (raíz del almacenamiento de Nikaido) aparece la sección "Carpetas añadidas" con las carpetas de iCloud y del iPhone, en lista y en cuadrícula. Cada una lleva un distintivo: nube si es de iCloud, manzana si es del iPhone (otro proveedor: disco). Tocar una la abre en ese panel.
- Desde una carpeta añadida, el botón de casa (Inicio) del panel regresa al inicio.
- Se puede arrastrar (con el asa) un archivo o carpeta sobre una carpeta añadida y se mueve a su raíz; también sobre cualquier carpeta normal.
- Los íconos del selector de almacenamiento usan los mismos distintivos.

## v0.11.0 — menú principal (diseñado en el prototipo)
- Nueva pantalla de inicio: logo con la N (toca para abrir Ajustes y salta dos veces al abrir la app), degradado con el color principal, tarjetas de iCloud y Almacenamiento local, NikaView Files, barra de Nikaido Vault con partículas y la cuadrícula "Por tipo" con íconos redondos.
- iCloud y Almacenamiento local abren un recorrido de 3 pasos para añadir carpetas (usa el selector de carpetas existente y muestra las carpetas añadidas con su nube o manzana).
- Botón "Todas" (carita): todas las carpetas juntas con filtros iCloud / iPhone / NikaView.
- Música, Imágenes, Videos, Texto, IPA y dylibs, y Documentos abren el filtro global ya en ese tipo.
- En el Explorador hay un botón de casa para volver al inicio. Salir de la bóveda regresa al inicio.
- Las animaciones respetan "Reducir movimiento".

## v0.12.0 — Nikaido Vault: dos opciones de entrada y contraseñas .sec
- Al abrir la bóveda se muestran dos opciones: Face ID y Contraseña (Face ID se activa después de entrar una vez con la contraseña). Ya no se lanza Face ID solo.
- Al abrir una colección .sec dentro de la bóveda también hay dos opciones. La primera vez se escribe su contraseña y se ofrece guardarla (Llavero, protegida por Face ID, una por colección); las siguientes veces se puede elegir Face ID. Si la contraseña guardada deja de servir, se descarta y se pide de nuevo.
- Cambiar la contraseña de una colección .sec (menú ··· de la colección): crea una COPIA re-cifrada con la contraseña nueva (por bloques, sin cargar archivos completos en memoria); la original no se toca hasta que el usuario decide borrarla. Si se bloquea la app o falla algo, la copia incompleta se elimina.
- Pantallas de desbloqueo con el estilo nuevo.
- NO incluido: cambiar la contraseña de la bóveda. La clave de la bóveda se deriva directamente de la contraseña y cifra el índice y cada archivo, así que cambiarla obliga a re-cifrar TODA la bóveda. Pendiente de hacerlo con copia de seguridad previa y pruebas.

## Pendiente / a probar en un iPhone
1. Face ID y la contraseña alternativa al abrir un archivo de la bóveda (incluido cancelar).
2. Añadir una carpeta de "En mi iPhone" y una de iCloud; reiniciar la app y comprobar que siguen.
3. Videos verticales, horizontales y cuadrados en la cuadrícula de la bóveda.
4. Filtro global con varias carpetas, y borrar un archivo desde Archivos para ver el aviso.