# Takopi Sandbox Probe — iOS 27 estable

Diagnóstico independiente, de **solo lectura**, para comprobar la visibilidad de rutas y los errores de permisos en un iPhone. No modifica archivos, no instala perfiles, no pide permisos adicionales y no ejecuta exploits.

## Objetivo

Comprobar las restricciones de enumeración de archivos en la versión estable de iOS 27 antes de investigar una posible adaptación de [bad_query](https://github.com/forcequitOS/bad_query). Su autor documenta el fallo hasta iOS **27 beta 4**, pero no confirma compatibilidad con la versión estable.

Un resultado de *lstat* correcto indica únicamente que se puede consultar cierta información de la ruta. Un listado exitoso puede limitarse a nombres de archivos. Ninguno de los dos demuestra acceso de lectura al contenido.

## Generación

Con XcodeGen instalado:

\`\`\`sh
cd Experiments/TakopiSandboxProbe
xcodegen generate
xcodebuild -project TakopiSandboxProbe.xcodeproj \
  -scheme TakopiSandboxProbe -configuration Release \
  -sdk iphoneos -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
\`\`\`

La GitHub Action crea un IPA **sin firmar** como artifact. Debe firmarse con una cuenta de desarrollo o con el método de instalación que utilices, antes de instalarse.

No se ha validado todavía el comportamiento en un dispositivo iOS 27 estable.
