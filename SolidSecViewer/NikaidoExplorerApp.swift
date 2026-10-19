import SwiftUI

@main
struct NikaidoExplorerApp: App {
    @StateObject private var vault = VaultSession()

    @AppStorage("NikaidoTheme.accentHex")
    private var accentHex = NikaidoThemePalette.defaultAccentHex

    @AppStorage("NikaidoTheme.folderHex")
    private var folderHex = ""

    @AppStorage("NikaidoTheme.appearance")
    private var appearance = "system"

    private var accentColor: Color {
        Color(nikaidoHex: accentHex) ?? NikaidoTheme.accent
    }

    private var folderColor: Color {
        folderHex.isEmpty
            ? accentColor
            : (Color(nikaidoHex: folderHex) ?? accentColor)
    }

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vault)
                .environment(\.nikaidoAccent, accentColor)
                .environment(\.nikaidoFolderColor, folderColor)
                .tint(accentColor)
                .preferredColorScheme(preferredScheme)
        }
    }
}
