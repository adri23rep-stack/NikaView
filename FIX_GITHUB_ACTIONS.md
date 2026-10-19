# Corrección del fallo de GitHub Actions

El workflow fallaba durante `xcodebuild` con el código 65 porque Xcode 16.4 no
pudo inferir el tipo de la expresión SwiftUI completa en
`SolidSecViewer/ExplorerView.swift`.

Se dividió la composición de la pantalla en vistas intermedias pequeñas, sin
cambiar sus paneles, hojas, alertas ni comportamiento.

También se corrigieron dos avisos que habrían impedido la siguiente puerta de
CI:

- el acceso a `NSLock` desde una función `async` usa ahora `withLock`;
- el límite de tamaño del editor se movió fuera de una vista SwiftUI para que
  una tarea desprendida no lo trate como acceso aislado al `MainActor`.

El control final de GitHub Actions ahora imprime el resumen del compilador
cuando falle `iosbuild`, para que el error real aparezca directamente en el
registro del job.
