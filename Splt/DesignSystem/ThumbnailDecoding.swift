import UIKit

extension UIImage {
    /// Decodes image data shrunk so its shortest side is at most `pixels`, ready to draw. Call it
    /// away from the main thread: a full photo takes long enough to stall scrolling.
    static func thumbnail(from data: Data, shortestSide pixels: CGFloat) -> UIImage? {
        guard let full = UIImage(data: data) else { return nil }
        let shortest = min(full.size.width, full.size.height)
        guard shortest > pixels, shortest > 0 else { return full.preparingForDisplay() ?? full }
        let factor = pixels / shortest
        let size = CGSize(width: full.size.width * factor, height: full.size.height * factor)
        return full.preparingThumbnail(of: size) ?? full
    }
}
