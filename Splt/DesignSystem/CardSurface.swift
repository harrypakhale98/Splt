import SwiftUI

extension View {
    /// A content card: grouped background, continuous corners, the app's standard radius.
    func cardSurface(radius: CGFloat = 24) -> some View {
        background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
