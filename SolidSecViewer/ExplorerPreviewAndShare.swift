import SwiftUI
import UIKit
import QuickLook

struct ExplorerShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: urls,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

/// A Quick Look controller has no SwiftUI dismissal control when it is hosted
/// inside a sheet. Keep a native close action above it so every preview,
/// including archives that only show metadata, can always be dismissed.
struct ExplorerPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ExplorerQuickLookView(url: url)
                .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(radius: 3)
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
            .accessibilityLabel("Cerrar vista previa")
        }
    }
}

struct ExplorerQuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(
        context: Context
    ) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ uiViewController: QLPreviewController,
        context: Context
    ) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(
            in controller: QLPreviewController
        ) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}
