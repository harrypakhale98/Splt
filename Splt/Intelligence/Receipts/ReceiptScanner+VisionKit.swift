import UIKit
import VisionKit

extension ReceiptScanning {
    /// Scans the pages returned by the document camera.
    @MainActor
    func scan(_ documentScan: VNDocumentCameraScan) async -> ParsedReceipt {
        let images = (0..<documentScan.pageCount).compactMap { documentScan.imageOfPage(at: $0).uprightCGImage }
        return await scan(images)
    }

    /// Scans an image picked from the library or taken with the camera.
    @MainActor
    func scan(_ image: UIImage) async -> ParsedReceipt {
        guard let cgImage = image.uprightCGImage else { return await scan([]) }
        return await scan([cgImage])
    }
}

private extension UIImage {
    /// The pixels with the orientation applied, since `cgImage` alone ignores it.
    var uprightCGImage: CGImage? {
        guard imageOrientation != .up else { return cgImage }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(at: .zero) }.cgImage
    }
}
