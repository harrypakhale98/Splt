import SwiftUI

/// A QR code for `text` on its own white card. The card stays white in dark mode on purpose:
/// scanners need dark modules on a light ground with a quiet margin around them.
/// The code is drawn once per text, off the body, so typing nearby doesn't redraw it.
struct QRCard: View {
    let text: String
    var maxWidth: CGFloat = 240

    @State private var image: UIImage?
    @State private var cannotDraw = false

    var body: some View {
        // a ZStack stays in the tree when it is empty, so the task still runs for a new text
        ZStack {
            if !cannotDraw {
                card
            }
        }
        .task(id: text) {
            cannotDraw = false
            image = QRCodeImage.make(from: text)
            cannotDraw = image == nil
        }
    }

    private var card: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                // Holds the code's square while it is drawn, so nothing jumps when it appears.
                Color.clear.aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(maxWidth: maxWidth)
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: Depth.controlRadius, style: .continuous))
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    QRCard(text: "https://example.com/invite/abc123")
        .padding()
        .background(Ink.paper)
}
