import SwiftUI

extension View {
    /// The rare raised surface: a sheet of paper with gentle corners.
    func cardSurface(radius: CGFloat = 14) -> some View {
        background(Ink.sheet, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
