import SwiftUI
import Photos
import PhotosUI
import UniformTypeIdentifiers

/// Files are copied out of the Photos item provider before the callback returns.
/// The originals are never deleted as part of the import transaction.
struct NikaidoPickedPhoto: Identifiable {
    let id = UUID()
    let fileURL: URL
    let assetIdentifier: String?
}

struct NikaidoPhotoPicker: UIViewControllerRepresentable {
    let onFinished: ([NikaidoPickedPhoto], String?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 0
        configuration.filter = .any(of: [.images, .videos])
        configuration.preferredAssetRepresentationMode = .current
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: NikaidoPhotoPicker
        init(_ parent: NikaidoPhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }
            Task {
                var picked: [NikaidoPickedPhoto] = []
                var failures = 0
                for result in results {
                    let provider = result.itemProvider
                    let available = provider.registeredTypeIdentifiers
                    let type = available.first(where: { UTType($0)?.conforms(to: .movie) == true })
                        ?? available.first(where: { UTType($0)?.conforms(to: .image) == true })
                    guard let type else { failures += 1; continue }
                    do {
                        let url = try await Self.copyRepresentation(provider, type: type)
                        picked.append(NikaidoPickedPhoto(fileURL: url, assetIdentifier: result.assetIdentifier))
                    } catch {
                        failures += 1
                    }
                }
                await MainActor.run {
                    self.parent.onFinished(picked, failures > 0 ? "No se pudieron preparar \(failures) elementos del carrete." : nil)
                }
            }
        }

        private static func copyRepresentation(_ provider: NSItemProvider, type: String) async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadFileRepresentation(forTypeIdentifier: type) { source, error in
                    guard let source else {
                        continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                        return
                    }
                    do {
                        let ext = source.pathExtension.isEmpty ? (UTType(type)?.preferredFilenameExtension ?? "dat") : source.pathExtension
                        let target = FileManager.default.temporaryDirectory
                            .appendingPathComponent("NikaView-Photo-\(UUID().uuidString)")
                            .appendingPathExtension(ext)
                        try FileManager.default.copyItem(at: source, to: target)
                        continuation.resume(returning: target)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

@MainActor
final class NikaidoPhotoImportCoordinator: ObservableObject {
    @Published var isImporting = false
    @Published var notice: String?
    @Published var deleteConfirmation = false
    private var verifiedIdentifiers: [String] = []

    func importPicked(_ picked: [NikaidoPickedPhoto], vault: PrivateVaultSession, parentID: UUID?, requestDelete: Bool, pickerError: String?) {
        guard !isImporting else { picked.forEach { try? FileManager.default.removeItem(at: $0.fileURL) }; return }
        guard vault.isUnlocked else {
            picked.forEach { try? FileManager.default.removeItem(at: $0.fileURL) }
            notice = "Desbloquea la bóveda antes de importar."
            return
        }
        guard !picked.isEmpty else { notice = pickerError; return }
        isImporting = true
        Task { @MainActor in
            defer {
                isImporting = false
                for item in picked { try? FileManager.default.removeItem(at: item.fileURL) }
            }
            let previousCount = vault.entries.count
            await vault.importFiles(urls: picked.map(\.fileURL), parentID: parentID)
            let insertedCount = vault.entries.count - previousCount
            guard vault.isUnlocked, vault.errorMessage == nil, insertedCount == picked.count else {
                notice = "No se confirmó la importación completa. Los originales permanecen en Fotos. " + (vault.errorMessage ?? "")
                return
            }
            if !requestDelete {
                notice = "\(picked.count) archivo(s) cifrados correctamente en la bóveda." + (pickerError.map { " \($0)" } ?? "")
            }
            if requestDelete {
                verifiedIdentifiers = picked.compactMap(\.assetIdentifier)
                if verifiedIdentifiers.count == picked.count {
                    deleteConfirmation = true
                } else {
                    notice = "Importados y cifrados. No fue posible identificar todos los originales; no se borró nada."
                }
            }
        }
    }

    func deleteVerifiedOriginals() {
        let identifiers = verifiedIdentifiers
        verifiedIdentifiers = []
        guard !identifiers.isEmpty else { return }
        Task { @MainActor in
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard authorization == .authorized || authorization == .limited else {
                notice = "Fotos no concedió permiso para eliminar originales; permanecen intactos."
                return
            }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            guard assets.count == identifiers.count else {
                notice = "No se encontraron todos los originales. No se borró ninguno."
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(assets)
                }
                notice = "Fotos confirmó la eliminación de \(assets.count) original(es). Comprueba Eliminado recientemente en Fotos."
            } catch {
                notice = "Fotos no eliminó los originales: \(error.localizedDescription)"
            }
        }
    }
}
