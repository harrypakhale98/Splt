import SwiftUI
import UIKit

struct ReceiptSection: View {
    let model: ExpenseDetailModel
    private let store = ReceiptStore.standard
    @State private var showsFullScreen = false
    /// Whether the photo file is here, checked once per file rather than on every redraw.
    @State private var isOnDevice = true

    var body: some View {
        if let fileName = model.receiptFileName {
            Section {
                RaisedRows {
                    Group {
                        if isOnDevice {
                            Button {
                                showsFullScreen = true
                            } label: {
                                HStack {
                                    ReceiptThumbnail(fileName: fileName, store: store, side: 88)
                                    Text("View Receipt")
                                    Spacer()
                                }
                            }
                            .accessibilityHint("Opens the receipt photo full screen")
                            .fullScreenCover(isPresented: $showsFullScreen) {
                                FullScreenReceiptView(fileName: fileName, store: store)
                            }
                        } else {
                            Label("The receipt photo is not on this device.", systemImage: "icloud.slash")
                                .foregroundStyle(Ink.secondary)
                        }
                    }
                    .task(id: fileName) {
                        // the photo can arrive by sync while the expense is open, so look again until it does
                        while !Task.isCancelled {
                            isOnDevice = store.exists(fileName)
                            if isOnDevice { break }
                            try? await Task.sleep(for: .seconds(2))
                        }
                    }
                }
            } header: {
                SectionHeader("Receipt")
            }
        }
    }
}

struct FullScreenReceiptView: View {
    let fileName: String
    let store: ReceiptStore

    @Environment(\.dismiss) private var dismiss
    /// The photo, decoded once when the viewer opens rather than on every pinch.
    @State private var image: UIImage?
    @State private var didLoad = false
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(magnify)
                        .simultaneousGesture(pan)
                        .onTapGesture(count: 2, perform: reset)
                        .accessibilityLabel("Receipt photo")
                        .accessibilityHint("Double tap to reset the zoom")
                        .accessibilityAddTraits(.isImage)
                } else if didLoad {
                    EmptyStateView(
                        title: "Receipt Unavailable",
                        systemImage: "doc.text.image",
                        description: "The receipt photo could not be opened."
                    )
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", role: .close) { dismiss() }
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

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { scale = min(max(baseScale * $0.magnification, 1), 6) }
            .onEnded { _ in
                baseScale = scale
                if scale == 1 { offset = .zero; baseOffset = .zero }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: baseOffset.width + value.translation.width, height: baseOffset.height + value.translation.height)
            }
            .onEnded { _ in baseOffset = offset }
    }

    private func reset() {
        Motion.perform(Motion.snappy) { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero }
    }
}
