import PhotosUI
import SwiftUI

/// Scan with the document camera or pick a photo. Each button only appears where it can work.
struct ReceiptActions: View {
    @Bindable var model: ExpenseFormModel
    @State private var showsScanner = false
    @State private var pickedPhoto: PhotosPickerItem?

    var body: some View {
        Group {
            if DocumentCameraView.isSupported {
                Button {
                    showsScanner = true
                } label: {
                    Label("Scan Receipt", systemImage: "doc.viewfinder")
                }
            }
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Label("Choose Receipt Photo", systemImage: "photo.on.rectangle")
            }
        }
        .disabled(model.isScanning)
        .fullScreenCover(isPresented: $showsScanner) {
            DocumentCameraView(
                onFinish: { pages in
                    showsScanner = false
                    Task { await model.importReceipt(pages: pages) }
                },
                onCancel: { showsScanner = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await model.importReceipt(imageData: data)
                } else {
                    model.scanNotice = String(localized: "That photo could not be loaded.")
                }
            }
        }
    }
}
