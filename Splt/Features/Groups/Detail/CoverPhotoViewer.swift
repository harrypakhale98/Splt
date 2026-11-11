import SwiftUI
import UIKit

/// A group's cover photo, whole, on black. Done closes it.
struct CoverPhotoViewer: View {
    let fileName: String
    var store: PhotoStore = .covers

    @Environment(\.dismiss) private var dismiss
    /// The photo, decoded once when the viewer opens.
    @State private var image: UIImage?
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Cover photo")
                        .accessibilityAddTraits(.isImage)
                } else if didLoad {
                    EmptyStateView(
                        title: "Photo Unavailable",
                        systemImage: "photo",
                        description: "The cover photo could not be opened."
                    )
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task(id: fileName) {
            let store = store, fileName = fileName
            image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let data = store.image(named: fileName), let image = UIImage(data: data) else { return nil }
                return image.preparingForDisplay() ?? image
            }.value
            didLoad = true
        }
    }
}
