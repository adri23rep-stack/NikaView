import SwiftUI
import UIKit

// MARK: - Peticiones desde el inicio hacia el Explorador

struct ExplorerLaunchRequest: Identifiable, Equatable {
    enum Kind: Equatable {
        case files
        case location(UUID)
        case folder(UUID, URL)
        case global(ExplorerGlobalFilter)
        case settings
        case smb
    }

    let id = UUID()
    let kind: Kind
}

// MARK: - Formas e íconos propios

/// La "N" del logo, dibujada como trazo.
struct NikaidoNMark: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + rect.width * x / 24,
                y: rect.minY + rect.height * y / 24
            )
        }

        var path = Path()
        path.move(to: point(7, 18))
        path.addLine(to: point(7, 6))
        path.addLine(to: point(17, 18))
        path.addLine(to: point(17, 6))
        return path
    }
}

private struct NikaidoSmileCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.60))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.60),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.90)
        )
        return path
    }
}

/// Carita feliz dibujada (no es un emoji).
struct NikaidoSmileIcon: View {
    var color: Color = .primary

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 1.9)

            NikaidoSmileCurve()
                .stroke(color, style: StrokeStyle(lineWidth: 1.9, lineCap: .round))

            Circle()
                .fill(color)
                .frame(width: 2.8, height: 2.8)
                .offset(x: -3.2, y: -2.4)

            Circle()
                .fill(color)
                .frame(width: 2.8, height: 2.8)
                .offset(x: 3.2, y: -2.4)
        }
        .frame(width: 22, height: 22)
    }
}

extension Color {
    func nikaidoDarkened(_ factor: CGFloat) -> Color {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return Color(
            red: Double(red * factor),
            green: Double(green * factor),
            blue: Double(blue * factor)
        )
    }
}

// MARK: - Inicio

enum HomeTourSource: String, Identifiable {
    case iCloud
    case iPhone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iCloud: return "Añade tus carpetas de iCloud"
        case .iPhone: return "Añade carpetas de este iPhone"
        }
    }

    var intro: String {
        switch self {
        case .iCloud:
            return "Takopi Explorer solo puede abrir las carpetas que tú elijas. Te guiamos en tres pasos."
        case .iPhone:
            return "Solo se pueden añadir carpetas que tú elijas en Archivos. Las del sistema y las de otras apps no están permitidas."
        }
    }

    var steps: [String] {
        switch self {
        case .iCloud:
            return [
                "Abrimos Archivos en iCloud Drive",
                "Eliges una carpeta, o creas una nueva",
                "Tocas Abrir y aparece en el inicio"
            ]
        case .iPhone:
            return [
                "Abrimos Archivos en En mi iPhone",
                "Eliges una carpeta que hayas creado",
                "Tocas Abrir y aparece con una manzana"
            ]
        }
    }

    var symbol: String {
        switch self {
        case .iCloud: return "icloud"
        case .iPhone: return "applelogo"
        }
    }

    var gradient: [Color] {
        switch self {
        case .iCloud:
            return [Color(red: 0.30, green: 0.61, blue: 1.0), Color(red: 0.16, green: 0.37, blue: 0.82)]
        case .iPhone:
            return [Color(red: 0.48, green: 0.48, blue: 0.53), Color(red: 0.26, green: 0.26, blue: 0.31)]
        }
    }

    var pickerPlace: String {
        switch self {
        case .iCloud: return "iCloud Drive"
        case .iPhone: return "En mi iPhone"
        }
    }
}

private struct HomeCategory: Identifiable {
    let filter: ExplorerGlobalFilter
    let symbol: String
    let title: String

    var id: String { filter.rawValue }

    static let all: [HomeCategory] = [
        HomeCategory(filter: .music, symbol: "music.note", title: "Música"),
        HomeCategory(filter: .images, symbol: "photo", title: "Imágenes"),
        HomeCategory(filter: .videos, symbol: "film", title: "Videos"),
        HomeCategory(filter: .text, symbol: "doc.plaintext", title: "Texto"),
        HomeCategory(filter: .packages, symbol: "shippingbox", title: "IPA y dylibs"),
        HomeCategory(filter: .documents, symbol: "doc", title: "Documentos")
    ]
}

struct HomeView: View {
    @ObservedObject var locations: SecurityScopedFolderStore
    let onOpenExplorer: (ExplorerLaunchRequest.Kind) -> Void
    let onOpenVault: () -> Void

    @Environment(\.nikaidoAccent) private var nikaidoAccent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var homeIntroTask: Task<Void, Never>?

    @State private var logoOffset: CGFloat = 0
    @State private var showSettingsHint = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showHomeContent = false

    private var motionEnabled: Bool {
        !reduceMotion && scenePhase == .active && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    @State private var tourSource: HomeTourSource?
    @State private var showAllFolders = false
    @StateObject private var savedFavorites = ExplorerFavoritesStore()
    @State private var recentFolders: [NikaidoRecentFolder] = []

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 14) {
                    header
                    storageSection
                        .nikaidoHomeEntrance(showHomeContent, enabled: motionEnabled, delay: 0.00)
                    vaultBar
                        .nikaidoHomeEntrance(showHomeContent, enabled: motionEnabled, delay: 0.07)
                    quickAccessSection
                        .nikaidoHomeEntrance(showHomeContent, enabled: motionEnabled, delay: 0.13)
                    categoriesSection
                        .nikaidoHomeEntrance(showHomeContent, enabled: motionEnabled, delay: 0.18)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $tourSource) { source in
            HomeFolderTourView(source: source, locations: locations)
        }
        .sheet(isPresented: $showAllFolders) {
            HomeAllFoldersView(locations: locations) { kind in
                showAllFolders = false
                onOpenExplorer(kind)
            }
        }
        .onAppear {
            recentFolders = NikaidoRecents.all
            showHomeContent = false
            DispatchQueue.main.async { showHomeContent = true }

            // Repeat the little greeting whenever Home appears, not just on
            // the first launch. Never persistently suppress the speech bubble.
            homeIntroTask?.cancel()
            logoOffset = 0
            showSettingsHint = true
            homeIntroTask = Task {
                await playLogoHop()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 4_500_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    showSettingsHint = false
                }
            }
        }
        .onDisappear {
            homeIntroTask?.cancel()
            homeIntroTask = nil
            logoOffset = 0
            showSettingsHint = false
            showHomeContent = false
        }
    }

    private var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ACCESO RÁPIDO")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onOpenExplorer(.smb)
                } label: {
                    Label("SMB", systemImage: "network")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("Conectar a servidor SMB")
            }
            let favorites = savedFavorites.favorites.compactMap { favorite in
                savedFavorites.resolve(favorite, locations: locations.locations)
            }
            ForEach(Array(favorites.prefix(4).enumerated()), id: \.offset) { _, pair in
                Button {
                    onOpenExplorer(.folder(pair.0.id, pair.1))
                } label: {
                    Label(pair.1.lastPathComponent, systemImage: "star.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 14))
            }
            ForEach(recentFolders.prefix(4)) { item in
                if let location = locations.locations.first(where: { $0.id == item.locationID }) {
                    let url = URL(fileURLWithPath: item.path)
                    if url.path == location.rootURL.standardizedFileURL.path ||
                       url.path.hasPrefix(location.rootURL.standardizedFileURL.path + "/") {
                        Button {
                            onOpenExplorer(.folder(location.id, url))
                        } label: {
                            Label(item.label, systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    // MARK: Fondo

    private var background: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !motionEnabled)) { timeline in
                let time = motionEnabled ? timeline.date.timeIntervalSinceReferenceDate : 0
                ZStack {
                Color(uiColor: .systemBackground)

                // Seis orbes suaves; se suspenden con Reducir movimiento y Bajo consumo.
                if !reduceTransparency {
                    ambientOrb(.mint.opacity(0.21), diameter: 340, blur: 65,
                        from: [-0.42, -0.2], to: [0.04, 0.18], seconds: 13, bounds: proxy.size, time: time)
                    ambientOrb(.blue.opacity(0.16), diameter: 380, blur: 76,
                        from: [0.42, 0.36], to: [0.1, -0.23], seconds: 17, bounds: proxy.size, time: time)
                    ambientOrb(nikaidoAccent.opacity(0.18), diameter: 290, blur: 65,
                        from: [0.26, -0.3], to: [-0.35, 0.05], seconds: 11, bounds: proxy.size, time: time)
                    ambientOrb(.cyan.opacity(0.11), diameter: 220, blur: 47,
                        from: [-0.34, 0.48], to: [0.28, 0.14], seconds: 15, bounds: proxy.size, time: time)
                    ambientOrb(.purple.opacity(0.13), diameter: 200, blur: 46,
                        from: [0.3, 0.55], to: [-0.24, -0.31], seconds: 19, bounds: proxy.size, time: time)
                    ambientOrb(.indigo.opacity(0.10), diameter: 260, blur: 58,
                        from: [0.12, -0.45], to: [-0.3, 0.37], seconds: 14, bounds: proxy.size, time: time)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func ambientOrb(
        _ tint: Color,
        diameter: CGFloat,
        blur: CGFloat,
        from: [CGFloat],
        to: [CGFloat],
        seconds: Double,
        bounds: CGSize,
        time: TimeInterval
    ) -> some View {
        let progress = CGFloat((sin(time * .pi / seconds + seconds) + 1) / 2)
        return Circle()
            .fill(tint)
            .frame(width: diameter, height: diameter)
            .blur(radius: blur)
            .offset(
                x: (from[0] + (to[0] - from[0]) * progress) * bounds.width,
                y: (from[1] + (to[1] - from[1]) * progress) * bounds.height
            )

    }

    // MARK: Encabezado

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    showSettingsHint = false
                }
                onOpenExplorer(.settings)
            } label: {
                Image("TakopiLogo")
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .offset(y: logoOffset)
            .accessibilityLabel("Abrir ajustes")
            .accessibilityHint("Toca el pulpo para abrir ajustes")
            .overlay(alignment: .topLeading) {
                if showSettingsHint {
                    Text("¡Hazme click!")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(nikaidoAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07)))
                        .fixedSize()
                        .offset(x: 29, y: -21)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .zIndex(1)

            VStack(alignment: .leading, spacing: 2) {
                Text("Takopi Explorer")
                    .font(.system(size: 25, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("EXPLORADOR DE ARCHIVOS")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(height: 60)
        .padding(.top, 8)
    }

    /// Animación visible que se repite al volver a Inicio.
    private func playLogoHop() async {
        guard !reduceMotion else { return }

        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }

        for height in [CGFloat(-17), CGFloat(-9), CGFloat(-15)] {
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                logoOffset = height
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeIn(duration: 0.15)) {
                logoOffset = 0
            }
            try? await Task.sleep(nanoseconds: 190_000_000)
        }
    }

    // MARK: Almacenamiento

    private var storageSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("ALMACENAMIENTO")
                    .font(.footnote.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showAllFolders = true
                } label: {
                    HStack(spacing: 6) {
                        NikaidoSmileIcon(color: .primary)

                        Text("Todas")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 12)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.primary.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ver todas mis carpetas juntas")
            }
            .frame(height: 34)

            HStack(spacing: 12) {
                HomeStorageCard(
                    title: "iCloud",
                    subtitle: "Añadir carpetas",
                    symbol: "icloud",
                    colors: HomeTourSource.iCloud.gradient
                ) {
                    tourSource = .iCloud
                }

                HomeStorageCard(
                    title: "Almacenamiento local",
                    subtitle: "Añadir carpetas",
                    symbol: "applelogo",
                    colors: HomeTourSource.iPhone.gradient
                ) {
                    tourSource = .iPhone
                }
            }

            filesCard
        }
    }

    private var filesCard: some View {
        Button {
            onOpenExplorer(.files)
        } label: {
            HStack(spacing: 14) {
                NikaidoFeatureMark(
                    systemName: "folder.fill",
                    tint: nikaidoAccent,
                    size: 48
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Takopi Files")
                        .font(.headline)

                    Text("Tus carpetas y archivos")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 82)
            .background(Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .foregroundStyle(.primary)
        }
        .buttonStyle(NikaidoPressCardStyle())
    }

    // MARK: Vault

    private var vaultBar: some View {
        Button {
            onOpenVault()
        } label: {
            HStack(spacing: 12) {
                NikaidoVaultMark(
                    tint: nikaidoAccent,
                    size: 44,
                    onDarkBackground: true
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Takopi Vault")
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)

                    Text("Tu espacio privado")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 2)


                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 76)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                nikaidoAccent.nikaidoDarkened(0.88),
                                nikaidoAccent.nikaidoDarkened(0.67)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .overlay {
                HomeVaultGlow(animated: motionEnabled)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: nikaidoAccent.opacity(0.12), radius: 8, y: 4)
        }
        .buttonStyle(NikaidoPressCardStyle())
        .accessibilityLabel("Abrir Takopi Vault")
    }

    // MARK: Por tipo

    private var categoriesSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("POR TIPO")
                    .font(.footnote.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Todos los archivos") {
                    onOpenExplorer(.global(.all))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(nikaidoAccent)
            }
            .frame(height: 30)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 10),
                    count: 3
                ),
                spacing: 10
            ) {
                ForEach(HomeCategory.all) { category in
                    Button {
                        onOpenExplorer(.global(category.filter))
                    } label: {
                        VStack(spacing: 9) {
                            NikaidoFeatureMark(
                                systemName: category.symbol,
                                tint: nikaidoAccent,
                                size: 48
                            )

                            Text(category.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(NikaidoPressCardStyle())
                }
            }
        }
    }
}

// MARK: - Tarjeta de almacenamiento (iCloud / local)

private struct HomeStorageCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(colors.first ?? .blue)
                    .frame(width: 44, height: 44)
                    .background((colors.first ?? .blue).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 13))

                Spacer(minLength: 6)

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 135)
            .padding(15)
            .foregroundStyle(.primary)
            .background(Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(NikaidoPressCardStyle())
    }
}

// MARK: - Luz suave, contenida dentro de la tarjeta

private struct HomeVaultGlow: View {
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !animated)) { timeline in
            let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            let pulse = (sin(time * 1.2) + 1) / 2
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.22 + pulse * 0.20), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.5
                )
        }
    }
}

// MARK: - Recorrido para añadir carpetas

struct HomeFolderTourView: View {
    let source: HomeTourSource
    @ObservedObject var locations: SecurityScopedFolderStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nikaidoAccent) private var nikaidoAccent
    @Environment(\.nikaidoFolderColor) private var folderColor

    @State private var step = 0
    @State private var showPicker = false
    @State private var noticeText: String?

    var body: some View {
        VStack(spacing: 22) {
            topBar

            Group {
                switch step {
                case 0:
                    introStep
                case 1:
                    pickStep
                default:
                    doneStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .transition(.opacity)

            Spacer(minLength: 0)

            buttons
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showPicker) {
            ExplorerFolderPicker { url in
                handlePicked(url)
            }
        }
        .alert(
            "Carpetas",
            isPresented: Binding(
                get: { noticeText != nil },
                set: { if !$0 { noticeText = nil } }
            )
        ) {
            Button("Entendido", role: .cancel) {
                noticeText = nil
            }
        } message: {
            Text(noticeText ?? "")
        }
    }

    // MARK: Piezas

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? nikaidoAccent : Color.primary.opacity(0.18))
                        .frame(width: index == step ? 28 : 6, height: 6)
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.primary.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar")
        }
    }

    private var heroTile: some View {
        Image(systemName: source.symbol)
            .font(.system(size: 52, weight: .light))
            .foregroundStyle(.white)
            .frame(width: 108, height: 108)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: source.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private func numberedStep(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(nikaidoAccent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(nikaidoAccent.opacity(0.18)))

            Text(text)
                .font(.body)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private var introStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            heroTile

            Text(source.title)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.6)

            Text(source.intro)
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(source.steps.enumerated()), id: \.offset) { index, text in
                    numberedStep(index + 1, text)

                    if index < source.steps.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
    }

    private var pickStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Elige una carpeta")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.6)

            Text("Así se verá en Archivos. Toca la carpeta y luego Abrir.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: source.symbol)
                        .foregroundStyle(source.gradient[0])

                    Text(source.pickerPlace)
                        .font(.system(size: 16, weight: .semibold))

                    Spacer()

                    Text("Ejemplo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.25), lineWidth: 1)
                        )
                }
                .padding(14)

                Divider()

                mockFolderRow("Mis proyectos", selected: true)
                Divider()
                mockFolderRow("Respaldos", selected: false)
                Divider()
                mockFolderRow("Videos", selected: false)
                Divider()

                HStack {
                    Text("Cancelar")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("Abrir")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(nikaidoAccent)
                        )
                }
                .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.orange)

                Text("Usa una carpeta que hayas creado tú. iOS no permite añadir las del sistema ni las de otras apps.")
                    .font(.subheadline)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
    }

    private func mockFolderRow(_ name: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "folder.fill" : "folder")
                .font(.system(size: 22))
                .foregroundStyle(selected ? nikaidoAccent : Color.secondary)

            Text(name)
                .font(.system(size: 16, weight: selected ? .semibold : .regular))

            Spacer()

            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(nikaidoAccent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(selected ? nikaidoAccent.opacity(0.16) : Color.clear)
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(nikaidoAccent)
                )

            Text("Carpeta añadida")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.6)

            Text("Ya aparece en el inicio. Una nube marca las de iCloud y una manzana las de este iPhone.")
                .font(.body)
                .foregroundStyle(.secondary)

            let added = locations.locations.filter { $0.kind == .authorized }

            VStack(spacing: 0) {
                ForEach(Array(added.enumerated()), id: \.element.id) { index, location in
                    HStack(spacing: 14) {
                        ExplorerLocationBadgeIcon(
                            source: location.source,
                            folderColor: folderColor,
                            size: 30
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name)
                                .font(.system(size: 17, weight: .semibold))

                            Text(location.source.title)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if index < added.count - 1 {
                        Divider()
                            .padding(.leading, 76)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            Button {
                primaryAction()
            } label: {
                Text(primaryTitle)
            }
            .buttonStyle(NikaidoPrimaryButtonStyle())
            .padding(.horizontal, -28)

            Button {
                secondaryAction()
            } label: {
                Text(secondaryTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var primaryTitle: String {
        switch step {
        case 0: return "Empezar"
        case 1: return "Elegir carpeta"
        default: return "Listo"
        }
    }

    private var secondaryTitle: String {
        switch step {
        case 0: return "Ahora no"
        case 1: return "Atrás"
        default: return "Añadir otra carpeta"
        }
    }

    private func go(to newStep: Int) {
        withAnimation(.easeInOut(duration: 0.25)) {
            step = newStep
        }
    }

    private func primaryAction() {
        switch step {
        case 0: go(to: 1)
        case 1: showPicker = true
        default: dismiss()
        }
    }

    private func secondaryAction() {
        switch step {
        case 0: dismiss()
        case 1: go(to: 0)
        default: go(to: 1)
        }
    }

    private func handlePicked(_ url: URL) {
        if locations.addAuthorizedFolder(url) != nil {
            go(to: 2)

            if let notice = locations.lastError {
                noticeText = notice
            }
        } else {
            noticeText = locations.lastError ?? "No se pudo añadir la carpeta."
        }
    }
}

// MARK: - Todas mis carpetas

struct HomeAllFoldersView: View {
    @ObservedObject var locations: SecurityScopedFolderStore
    let onOpen: (ExplorerLaunchRequest.Kind) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nikaidoAccent) private var nikaidoAccent
    @Environment(\.nikaidoFolderColor) private var folderColor

    private enum Chip: String, CaseIterable, Identifiable {
        case all
        case iCloud
        case iPhone
        case nikaview

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "Todas"
            case .iCloud: return "iCloud"
            case .iPhone: return "iPhone"
            case .nikaview: return "Takopi"
            }
        }
    }

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let source: ExplorerStorageSource
        let request: ExplorerLaunchRequest.Kind
    }

    @State private var chip: Chip = .all
    @State private var localFolders: [URL] = []

    private var entries: [Entry] {
        var result: [Entry] = []

        if let local = locations.localLocation {
            for url in localFolders {
                result.append(
                    Entry(
                        id: url.path,
                        name: url.lastPathComponent,
                        source: .app,
                        request: .folder(local.id, url)
                    )
                )
            }
        }

        for location in locations.locations where location.kind == .authorized {
            result.append(
                Entry(
                    id: location.id.uuidString,
                    name: location.name,
                    source: location.source,
                    request: .location(location.id)
                )
            )
        }

        return result.filter { entry in
            switch chip {
            case .all: return true
            case .iCloud: return entry.source == .iCloud
            case .iPhone: return entry.source == .iPhone
            case .nikaview: return entry.source == .app
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Chip.allCases) { option in
                            Button {
                                chip = option
                            } label: {
                                Text(option.title)
                                    .font(.system(size: 15, weight: chip == option ? .bold : .semibold))
                                    .foregroundStyle(chip == option ? Color.white : Color.primary)
                                    .padding(.horizontal, 16)
                                    .frame(height: 36)
                                    .background(
                                        Capsule().fill(
                                            chip == option
                                            ? nikaidoAccent
                                            : Color.primary.opacity(0.10)
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }

                let shown = entries

                if shown.isEmpty {
                    Spacer()

                    NikaidoEmptyState(
                        systemName: "folder",
                        title: "Aquí no hay carpetas",
                        message: "Añade carpetas de iCloud o de este iPhone desde el inicio."
                    )

                    Spacer()
                } else {
                    List {
                        ForEach(shown) { entry in
                            Button {
                                onOpen(entry.request)
                            } label: {
                                HStack(spacing: 14) {
                                    ExplorerLocationBadgeIcon(
                                        source: entry.source,
                                        folderColor: folderColor,
                                        size: 30
                                    )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(.system(size: 17, weight: .semibold))

                                        Text(entry.source.title)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Todas mis carpetas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadLocalFolders()
            }
        }
    }

    private func loadLocalFolders() async {
        guard let root = locations.localLocation?.rootURL else { return }

        localFolders = await Task.detached(priority: .utility) { () -> [URL] in
            let children = (try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            return children
                .filter { url in
                    (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                }
                .sorted {
                    $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
                }
        }.value
    }
}


// Las secciones llegan en secuencia sin retener vistas privadas en pantalla.
private struct NikaidoHomeEntrance: ViewModifier {
    let visible: Bool
    let enabled: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(!enabled || visible ? 1 : 0)
            .offset(y: !enabled || visible ? 0 : 12)
            .animation(
                enabled ? .easeOut(duration: 0.36).delay(delay) : nil,
                value: visible
            )
    }
}

private extension View {
    func nikaidoHomeEntrance(
        _ visible: Bool,
        enabled: Bool,
        delay: Double
    ) -> some View {
        modifier(NikaidoHomeEntrance(visible: visible, enabled: enabled, delay: delay))
    }
}

