import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum QRCodeImage {
    /// A crisp QR code for `text`, scaled up so it stays sharp. Nil if the text cannot be encoded.
    static func make(from text: String, scale: CGFloat = 8) -> UIImage? {
        guard let data = text.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
