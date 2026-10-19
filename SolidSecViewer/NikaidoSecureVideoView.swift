import SwiftUI
import AVKit
import Security
import CryptoKit

/// Video progress is stored only in this device's protected Keychain, never in
/// unencrypted defaults. Keys use the vault's random UUID rather than filenames.
enum NikaidoVideoResumeStore {
    private static let service = "com.teamnikaido.explorer.video-resume.v1"

    static func stableID(for url: URL) -> UUID {
        // External .sec indexes build new VaultItem objects on every open.
        // Hash the encrypted on-disk location rather than the random in-memory ID.
        let digest = Array(SHA256.hash(data: Data(url.standardizedFileURL.path.utf8)))
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }

    static func load(_ id: UUID) -> Double? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8),
              let seconds = Double(text), seconds.isFinite, seconds > 3
        else { return nil }
        return seconds
    }

    static func capture(_ player: AVPlayer, id: UUID) {
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds > 3 else { return }
        let duration = player.currentItem?.duration.seconds ?? .nan
        if duration.isFinite && duration > 10 && seconds >= duration - 5 {
            remove(id)
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = Data(String(seconds).utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        _ = SecItemAdd(insert as CFDictionary, nil)
    }

    static func remove(_ id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// No background playback: the vault explicitly kills video loaders on lock.
/// PiP stays unavailable for encrypted video until a secure policy is designed.
struct NikaidoSecureVideoView: View {
    let player: AVPlayer
    let videoID: UUID

    @State private var rate: Float = 1
    @State private var resumedAt: Double?

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: player)
                .accessibilityLabel("Reproductor de video cifrado")

            HStack(spacing: 12) {
                if let resumedAt {
                    Text("Continuaste desde \(Int(resumedAt) / 60):\(String(format: "%02d", Int(resumedAt) % 60))")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .accessibilityLabel("Reproducción retomada")
                }

                Spacer(minLength: 0)

                Button {
                    player.seek(to: .zero)
                    NikaidoVideoResumeStore.remove(videoID)
                    resumedAt = nil
                } label: {
                    Label("Desde el inicio", systemImage: "backward.end.fill")
                }
                .accessibilityHint("Regresar al principio del video")

                Menu {
                    ForEach([0.5, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button("\(speed.formatted())×") {
                            rate = Float(speed)
                            player.playImmediately(atRate: rate)
                        }
                    }
                } label: {
                    Label("\(Double(rate).formatted())×", systemImage: "speedometer")
                }
                .accessibilityLabel("Velocidad de reproducción")
                .accessibilityValue("\(Double(rate).formatted()) veces")
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black)
        }
        .onAppear {
            if let saved = NikaidoVideoResumeStore.load(videoID) {
                resumedAt = saved
                player.seek(to: CMTime(seconds: saved, preferredTimescale: 600))
            }
        }
        .onDisappear {
            NikaidoVideoResumeStore.capture(player, id: videoID)
        }
    }
}
