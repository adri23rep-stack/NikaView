import Foundation
import AVFoundation

/// Makes a new video with only playback metadata. Never modifies or removes the original.
/// Successful exports are re-opened and checked before the Share Sheet is offered.
enum NikaidoVideoCleanExporter {
    private static func privacyError(_ message: String) -> NSError {
        NSError(domain: "NikaView.VideoPrivacy", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func exportCleanCopy(from input: URL) async throws -> URL {
        let granted = input.startAccessingSecurityScopedResource()
        defer { if granted { input.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: input)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw privacyError("No se puede exportar este video sin perder compatibilidad.")
        }
        // Empty output metadata and filter out source-identifying metadata.
        exporter.metadata = []
        exporter.metadataItemFilter = AVMetadataItemFilter.forSharing()
        exporter.shouldOptimizeForNetworkUse = true

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("NikaView-video-clean-" + UUID().uuidString)
            .appendingPathExtension("mov")
        do {
            if #available(iOS 18.0, *) {
                try await exporter.export(to: output, as: .mov)
            } else {
                // Older iOS uses the compatibility export API.
                exporter.outputURL = output
                exporter.outputFileType = .mov
                await exporter.export()
                guard exporter.status == .completed else {
                    throw exporter.error ?? privacyError("El video no pudo exportarse de forma segura.")
                }
            }
            try Task.checkCancellation()
            let attrs = try FileManager.default.attributesOfItem(atPath: output.path)
            guard (attrs[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
                throw privacyError("La copia exportada está vacía.")
            }

            let result = AVURLAsset(url: output)
            let containerMetadata = try await result.load(.metadata)
            let commonMetadata = try await result.load(.commonMetadata)
            let all = containerMetadata + commonMetadata
            let sensitiveTerms = ["location", "gps", "creationdate", "datecreated",
                                  "creation_date", "com.apple.quicktime.creationdate",
                                  "author", "artist", "camera", "make", "model"]
            let stillIdentifiable = all.contains { item in
                let tag = (item.identifier?.rawValue ?? "") + " " + (item.commonKey?.rawValue ?? "")
                let normalized = tag.lowercased().replacingOccurrences(of: " ", with: "")
                return sensitiveTerms.contains(where: { normalized.contains($0) })
            }
            guard !stillIdentifiable else {
                throw privacyError("La exportación conservó datos de fecha, autor o ubicación. No se compartirá esta copia.")
            }
            try Task.checkCancellation()
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
