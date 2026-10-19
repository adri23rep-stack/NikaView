# Visor y portadas de archivos

## Visor que no se podía cerrar

La vista rápida de Quick Look se alojaba directamente en una hoja SwiftUI sin
un control de cierre propio. Algunos formatos, como ZIP, solo muestran su
ficha gris de metadatos y no ofrecen una navegación visible para volver.

`ExplorerPreviewSheet` ahora muestra un botón **Cerrar** persistente sobre
cualquier vista previa. Funciona para ZIP y para los demás tipos que soporta
Quick Look.

## Portadas de imágenes y videos

La nueva preferencia **Mostrar portadas de fotos y videos** aparece en
**Ajustes > Vista de archivos**. Está activada inicialmente y usa el generador
de miniaturas de iOS para mostrar la imagen de portada en lista y cuadrícula.
Los videos conservan el indicador de reproducción; si iOS no puede generar una
miniatura se mantiene el icono del tipo de archivo.
