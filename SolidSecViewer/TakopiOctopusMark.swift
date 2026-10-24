import SwiftUI

/// Takopi sin carpeta ni recuadro de icono: el pulpo del inicio es un
/// personaje interactivo, mientras el icono de la app permanece sin cambios.
struct TakopiOctopusMark: View {
    private let lavender = Color(red: 0.62, green: 0.59, blue: 0.92)
    private let shade = Color(red: 0.43, green: 0.43, blue: 0.73)

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)

            ZStack {
                // Brazos detrás de la cabeza. Trazos sencillos y sin sombras.
                Path { path in
                    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                        CGPoint(x: side * x, y: side * y)
                    }
                    path.move(to: p(0.35, 0.61))
                    path.addCurve(to: p(0.08, 0.76),
                                  control1: p(0.22, 0.60), control2: p(0.13, 0.55))
                    path.move(to: p(0.39, 0.70))
                    path.addCurve(to: p(0.24, 0.93),
                                  control1: p(0.30, 0.76), control2: p(0.35, 0.91))
                    path.move(to: p(0.48, 0.72))
                    path.addQuadCurve(to: p(0.49, 0.95), control: p(0.40, 0.89))
                    path.move(to: p(0.57, 0.72))
                    path.addCurve(to: p(0.74, 0.92),
                                  control1: p(0.67, 0.79), control2: p(0.62, 0.92))
                    path.move(to: p(0.65, 0.60))
                    path.addCurve(to: p(0.92, 0.76),
                                  control1: p(0.80, 0.60), control2: p(0.87, 0.54))
                }
                .stroke(shade, style: StrokeStyle(
                    lineWidth: side * 0.11, lineCap: .round, lineJoin: .round
                ))

                Ellipse()
                    .fill(lavender)
                    .frame(width: side * 0.71, height: side * 0.63)
                    .position(x: side * 0.5, y: side * 0.43)

                HStack(spacing: side * 0.21) {
                    Circle().fill(Color(red: 0.23, green: 0.23, blue: 0.39))
                        .frame(width: side * 0.07, height: side * 0.10)
                    Circle().fill(Color(red: 0.23, green: 0.23, blue: 0.39))
                        .frame(width: side * 0.07, height: side * 0.10)
                }
                .position(x: side * 0.5, y: side * 0.48)

                Path { path in
                    path.move(to: CGPoint(x: side * 0.46, y: side * 0.60))
                    path.addQuadCurve(
                        to: CGPoint(x: side * 0.54, y: side * 0.60),
                        control: CGPoint(x: side * 0.50, y: side * 0.65)
                    )
                }
                .stroke(shade, style: StrokeStyle(lineWidth: side * 0.025,
                                                 lineCap: .round))
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}
