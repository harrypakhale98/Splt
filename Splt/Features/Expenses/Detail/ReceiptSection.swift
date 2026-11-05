import SwiftUI
import UIKit

struct ReceiptSection: View {
    let model: ExpenseDetailModel
    private let store = ReceiptStore.standard
    @State private var showsFullScreen = false

    var body: some View {
        if let fileName = model.receiptFileName {
            Section(header: Text("Receipt").foregroundStyle(Ink.secondary)) {
                if store.exists(fileName) {
                    Button {
                        showsFullScreen = true
                    } label: {
                        HStack {
                            ReceiptThumbnail(fileName: fileName, store: store, side: 88)
                            Text("View Receipt")
                            Spacer()
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .foregroundStyle(Ink.secondary)
                                .accessibilityHidden(true)
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
        }
    }
}

struct FullScreenReceiptView: View {
    let fileName: String
    let store: ReceiptStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            Group {
                if let data = store.image(named: fileName), let image = UIImage(data: data) {
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
                } else {
                    ContentUnavailableView("Receipt Unavailable", systemImage: "doc.text.image")
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
        let change = { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero }
        if reduceMotion { change() } else { withAnimation(.snappy, change) }
    }
}
