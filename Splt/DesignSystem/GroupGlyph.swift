import SwiftUI
import UIKit

/// A group's symbol, plain on the page, for list rows and headers. A group with a cover photo shows
/// the photo in the same square instead, with photo corners, so rows keep their height.
struct GroupGlyph: View {
    let symbol: String
    /// The cover photo's file name in `store`. Until the photo is on this device the symbol shows.
    var cover: String?
    var store: PhotoStore = .covers
    @ScaledMetric private var scaledSide: CGFloat
    private let baseSide: CGFloat

    init(symbol: String, cover: String? = nil, size: CGFloat = 32, store: PhotoStore = .covers) {
        self.symbol = symbol
        self.cover = cover
        self.store = store
        baseSide = size
        _scaledSide = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    private var side: CGFloat { min(scaledSide, baseSide * 1.5) }

    var body: some View {
        if let cover {
            CoverThumbnail(fileName: cover, store: store, side: side) { symbolView }
        } else {
            symbolView
        }
    }

    private var symbolView: some View {
        Image(systemName: symbol)
            .font(.system(size: side * 0.5, weight: .regular))
            .foregroundStyle(Ink.secondary)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// A group's cover photo cut to a square with photo corners. Shows `placeholder` until it has loaded,
/// or for good when the photo is not on this device.
struct CoverThumbnail<Placeholder: View>: View {
    let fileName: String
    let store: PhotoStore
    let side: CGFloat
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    init(fileName: String, store: PhotoStore, side: CGFloat, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.fileName = fileName
        self.store = store
        self.side = side
        self.placeholder = placeholder
        // a photo seen before shows at once, so scrolling back up never flickers through the symbol
        _image = State(initialValue: CoverImageCache.shared.image(for: fileName, store: store))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: Depth.thumbnailRadius, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                placeholder()
            }
        }
        .frame(width: side, height: side)
        .task(id: fileName) {
            if let cached = CoverImageCache.shared.image(for: fileName, store: store) {
                image = cached
                return
            }
            // the photo can arrive by sync after the row first shows, so look again for a while
            for _ in 0..<30 {
                if let loaded = await CoverImageCache.shared.load(fileName, store: store, pixels: side * displayScale) {
                    image = loaded
                    return
                }
                image = nil
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
            }
        }
    }
}

/// Decoded cover thumbnails by file name. A cover's name is new for every photo, so an entry never goes stale.
@MainActor
final class CoverImageCache {
    static let shared = CoverImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private func key(_ fileName: String, _ store: PhotoStore) -> NSString {
        store.url(for: fileName).path as NSString
    }

    func image(for fileName: String, store: PhotoStore) -> UIImage? {
        cache.object(forKey: key(fileName, store))
    }

    /// Reads and shrinks the thumbnail away from the main thread. Nil when the photo is not here.
    func load(_ fileName: String, store: PhotoStore, pixels: CGFloat) async -> UIImage? {
        let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = store.thumbnail(named: fileName), let full = UIImage(data: data) else { return nil }
            let shortest = min(full.size.width, full.size.height)
            guard shortest > pixels, shortest > 0 else { return full.preparingForDisplay() ?? full }
            let factor = pixels / shortest
            return full.preparingThumbnail(of: CGSize(width: full.size.width * factor, height: full.size.height * factor)) ?? full
        }.value
        if let loaded { cache.setObject(loaded, forKey: key(fileName, store)) }
        return loaded
    }
}
