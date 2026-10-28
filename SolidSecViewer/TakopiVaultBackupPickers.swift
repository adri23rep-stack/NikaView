import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Export the already encrypted .tkvault ZIP by asking the system for an
/// iCloud Drive / On My iPhone destination. Never stages plaintext.
struct TakopiVaultBackupExportPicker: UIViewControllerRepresentable {
    let archiveURL: URL
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forExporting: [archiveURL], asCopy: true
        )
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController,
                                context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            onFinish()
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish()
        }
    }
}

/// Import a backup from any location supported by Files. Copy mode grants
/// a private snapshot; the restore routine independently authenticates it.
struct TakopiVaultBackupImportPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.data], asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController,
                                context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void
        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { onCancel(); return }
            onPick(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
