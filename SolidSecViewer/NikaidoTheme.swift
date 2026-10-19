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
            .frame(width: 36, height: 36)
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
