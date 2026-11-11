import SwiftUI
import UIKit

/// A small preview of a stored receipt photo, or of one still waiting to be saved.
struct ReceiptThumbnail: View {
    let fileName: String?
    var pendingImage: Data?
    let store: PhotoStore
    var side: CGFloat = 56

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    /// Changes whenever the picture does, including a new scan that has not been saved yet.
    private struct Source: Equatable {
        var fileName: String?
        var pendingImage: Data?
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "doc.text.image")
                    .foregroundStyle(Ink.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Depth.thumbnailRadius, style: .continuous))
        .accessibilityLabel("Receipt photo")
        .task(id: Source(fileName: fileName, pendingImage: pendingImage)) {
            image = await Self.load(
                fileName: fileName, pendingImage: pendingImage, store: store, pixels: side * displayScale
            )
        }
    }

    /// Reads and shrinks the photo away from the main thread, so a full scan never stalls scrolling.
    private static func load(fileName: String?, pendingImage: Data?, store: PhotoStore, pixels: CGFloat) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = pendingImage ?? fileName.flatMap({ store.thumbnail(named: $0) }),
                  let full = UIImage(data: data) else { return nil }
            let shortest = min(full.size.width, full.size.height)
            guard shortest > pixels, shortest > 0 else { return full.preparingForDisplay() ?? full }
            let factor = pixels / shortest
            let size = CGSize(width: full.size.width * factor, height: full.size.height * factor)
            return full.preparingThumbnail(of: size) ?? full
        }.value
    }
}
