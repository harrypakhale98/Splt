import SwiftUI
import UIKit

/// A small preview of a stored receipt photo, or of one still waiting to be saved.
struct ReceiptThumbnail: View {
    let fileName: String?
    var pendingImage: Data?
    let store: ReceiptStore
    var side: CGFloat = 56

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "doc.text.image")
                    .foregroundStyle(.legible)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("Receipt photo")
        .task(id: "\(fileName ?? "")-\(pendingImage?.count ?? 0)") {
            let data = pendingImage ?? fileName.flatMap { store.thumbnail(named: $0) }
            image = data.flatMap(UIImage.init(data:))
        }
    }
}
