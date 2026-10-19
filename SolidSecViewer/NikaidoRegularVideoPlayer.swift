import SwiftUI
import AVKit

struct NikaidoRegularVideoTarget: Identifiable {
    let id = UUID()
    let url: URL
}

/// Standard Explorer media can use PiP because it does not contain a vault key.
/// Import, deletion and vault lock policies remain unchanged.
struct NikaidoRegularVideoPlayer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var hasScopedAccess = false
    @State private var errorText: String?

    static func supports(_ file: ExplorerFileItem) -> Bool {
        !file.isDirectory && ["mp4", "mov", "m4v", "mp3", "m4a"].contains(file.pathExtension)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    NikaidoSecureVideoView(
                        player: player,
                        videoID: NikaidoVideoResumeStore.stableID(for: url),
                        allowsPictureInPicture: true
                    )
                } else if let errorText {
                    Text(errorText).foregroundStyle(.red).padding()
                } else {
                    ProgressView("Abriendo video…")
                }
            }
            .background(Color.black)
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cerrar") { dismiss() } }
        }
        .onAppear {
            guard player == nil else { return }
            hasScopedAccess = url.startAccessingSecurityScopedResource()
            guard FileManager.default.fileExists(atPath: url.path) else {
                errorText = "El archivo no está disponible."
                return
            }
            let playback = AVPlayer(url: url)
            player = playback
            playback.play()
        }
        .onDisappear {
            if let player {
                NikaidoVideoResumeStore.capture(
                    player,
                    id: NikaidoVideoResumeStore.stableID(for: url)
                )
                player.pause()
                player.replaceCurrentItem(with: nil)
                self.player = nil
            }
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
                hasScopedAccess = false
            }
        }
    }
}
