import SwiftUI
import UIKit

/// The picture the iCloud invite sheet shows beside the group's name: the cover photo when this
/// device has it, otherwise the group's symbol in ink on paper, as in the group list.
@MainActor
enum GroupShareThumbnail {
    /// The tile's side in points. It is drawn at three times this.
    static let side: CGFloat = 120

    static func png(symbol: String, coverFileName: String?) async -> Data? {
        var photo: UIImage?
        if let coverFileName {
            photo = await CoverImageCache.shared.load(coverFileName, store: .covers, pixels: side * 3)
        }
        // always light, like the recap card, so the tile reads the same wherever it ends up
        let renderer = ImageRenderer(content: Tile(symbol: symbol, photo: photo).environment(\.colorScheme, .light))
        renderer.scale = 3
        return renderer.uiImage?.pngData()
    }

    private struct Tile: View {
        let symbol: String
        let photo: UIImage?

        var body: some View {
            ZStack {
                Ink.paper
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: side * 0.42, weight: .regular))
                        .foregroundStyle(Ink.text)
                }
            }
            .frame(width: side, height: side)
            .clipped()
        }
    }
}
