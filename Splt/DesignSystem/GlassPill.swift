import SwiftUI

/// A glass capsule that holds chips, a short control or a line of text. Use it for floating
/// controls only. With Reduce Transparency on it becomes a solid capsule.
struct GlassPill<Content: View>: View {
    var tint: Color?
    var isInteractive = false
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .modifier(PillSurface(tint: tint, isInteractive: isInteractive, solid: reduceTransparency))
    }
}

private struct PillSurface: ViewModifier {
    let tint: Color?
    let isInteractive: Bool
    let solid: Bool

    func body(content: Content) -> some View {
        if solid {
            content.background(tint?.opacity(0.25) ?? Color(.secondarySystemFill), in: .capsule)
                .overlay(Capsule().strokeBorder(.separator))
        } else {
            let glass: Glass = {
                var glass = Glass.regular
                if let tint { glass = glass.tint(tint.opacity(0.35)) }
                return isInteractive ? glass.interactive() : glass
            }()
            content.glassEffect(glass, in: .capsule)
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.teal, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        VStack(spacing: 16) {
            GlassPill { Label("Dinner", systemImage: "fork.knife") }
            GlassPill(tint: .orange, isInteractive: true) { Text("Tonight") }
        }
    }
}
