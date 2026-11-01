import SwiftUI
import VisionKit

/// Reads a QR code with the camera. Shows a plain message where the camera cannot scan.
struct QRScannerView: View {
    let onCode: (String) -> Void

    var body: some View {
        if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
            ScannerRepresentable(onCode: onCode)
                .ignoresSafeArea()
        } else {
            ContentUnavailableView(
                "Scanning Isn't Available",
                systemImage: "qrcode.viewfinder",
                description: Text("Allow camera access in Settings, or ask your friend to send the invite link instead.")
            )
        }
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (String) -> Void
        private var handled = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !handled else { return }
            for case .barcode(let code) in addedItems {
                if let text = code.payloadStringValue {
                    handled = true
                    onCode(text)
                    return
                }
            }
        }
    }
}
