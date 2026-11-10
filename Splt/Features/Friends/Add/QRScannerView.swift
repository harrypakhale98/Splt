import SwiftUI
import VisionKit

/// Reads a QR code with the camera. Shows a plain message where the camera cannot scan.
/// `onCode` returns false to reject a code and keep scanning.
struct QRScannerView: View {
    let onCode: (String) -> Bool

    var body: some View {
        if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
            ScannerRepresentable(onCode: onCode)
                .ignoresSafeArea()
        } else {
            EmptyStateView(
                title: "Scanning Isn't Available",
                systemImage: "qrcode.viewfinder",
                description: "Allow camera access in Settings, or ask your friend for the invite link."
            )
        }
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Bool

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
        private let onCode: (String) -> Bool
        private var handled = false

        init(onCode: @escaping (String) -> Bool) {
            self.onCode = onCode
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !handled else { return }
            for case .barcode(let code) in addedItems {
                if let text = code.payloadStringValue {
                    handled = true
                    // A rejected code leaves the scanner ready for the next one.
                    handled = onCode(text)
                    return
                }
            }
        }
    }
}
