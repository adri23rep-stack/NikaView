import SwiftUI
import UIKit

/// Estilo visual compartido de Nikaido: colores, botones, tarjetas y estados vacíos.
enum NikaidoTheme {
    static let accent = Color(red: 0.38, green: 0.36, blue: 0.96)
    static let accentSoft = Color(red: 0.58, green: 0.40, blue: 0.98)

    static var gradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentSoft],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

/// Botón de ícono plano y minimalista (sin fondo) para barras de herramientas.
struct NikaidoIconButtonStyle: ButtonStyle {
    var prominent = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.nikaidoAccent) private var accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(prominent ? accent : Color.primary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.3)
    }
}

/// Botón principal ancho con degradado.
struct NikaidoPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.nikaidoAccent) private var accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .padding(.horizontal, 28)
    }
}

/// Ícono plano de archivo/carpeta (sin cajita de fondo).
struct NikaidoIconBadge: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.72, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: size + 6, height: size)
    }
}

/// Pantalla vacía amigable.
struct NikaidoEmptyState: View {
    let systemName: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// Campo de búsqueda en forma de cápsula.
struct NikaidoSearchField: View {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)

            if !text.isEmpty {
                Button {
                    text = ""
                    onSubmit()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

extension View {
    /// Fondo redondeado para campos de texto.
    func nikaidoField() -> some View {
        self
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
    }
}

 
/// Glass only on primary controls. iOS 16–25 uses a material fallback.
/// Reduce Transparency uses an opaque capsule on every supported iOS version.
struct NikaidoGlassCapsule: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 5)
        }
    }
}

struct NikaidoGlassActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.35)
    }
}

struct NikaidoGlassFloatingCircle: ViewModifier {
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(tint, in: Circle())
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(), in: .circle)
        } else {
            content.background(tint, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.15), radius: 10, y: 5)
        }
    }
}


// MARK: - Identidad visual NikaView v0.12.4

/// Emblema vectorial: no usa imágenes rasterizadas y se adapta al acento elegido.
struct NikaidoBrandMark: View {
    let accent: Color
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.nikaidoDarkened(0.70)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(.white.opacity(0.17))
                .frame(width: size * 0.72, height: size * 0.72)
                .offset(x: -size * 0.28, y: -size * 0.30)

            NikaidoNMark()
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: max(2, size * 0.052),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .padding(size * 0.14)

            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .strokeBorder(.white.opacity(0.24), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
        .shadow(color: accent.opacity(0.24), radius: size * 0.18, y: size * 0.09)
        .accessibilityHidden(true)
    }
}

/// Íconos de categorías, carpetas y almacenamiento con el mismo lenguaje visual.
struct NikaidoFeatureMark: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.23), tint.opacity(0.09)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(tint.opacity(0.14), lineWidth: 1)

            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(tint)

            Circle()
                .fill(tint.opacity(0.88))
                .frame(width: size * 0.09, height: size * 0.09)
                .offset(x: size * 0.31, y: -size * 0.31)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Identificador de la bóveda, separado del emblema principal y sin tapar las burbujas.
struct NikaidoVaultMark: View {
    let tint: Color
    var size: CGFloat = 48
    var onDarkBackground = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: onDarkBackground
                            ? [.white.opacity(0.21), .white.opacity(0.09)]
                            : [tint, tint.nikaidoDarkened(0.69)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .strokeBorder(.white.opacity(0.24), lineWidth: 1)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)


        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Respuesta táctil visual sutil, desactivada si iOS solicita reducir movimiento.
struct NikaidoPressCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.975 : 1))
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.80),
                value: configuration.isPressed
            )
    }
}

