import SwiftUI

extension View {
    /// Shows the undo banner above the content and makes the center available to settle sheets.
    func settleUndoBanner() -> some View {
        modifier(SettleUndoBannerModifier())
    }
}

private struct SettleUndoBannerModifier: ViewModifier {
    @State private var center = SettleUndoCenter()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.settleUndo, center)
            .overlay(alignment: .bottom) {
                if let banner = center.banner {
                    SettleUndoBanner(banner: banner, center: center)
                        .padding(.horizontal)
                        .padding(.bottom, 96)
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                        .motionTransition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: center.banner)
    }
}

struct SettleUndoBanner: View {
    let banner: SettleUndoCenter.Banner
    let center: SettleUndoCenter

    @Environment(\.dataServices) private var services

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            Text(banner.message)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            if case .recorded = banner, let services {
                Button("Undo") { center.undo(using: services.payments) }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        if case .recorded = banner { return "checkmark.circle.fill" }
        return "arrow.uturn.backward.circle.fill"
    }

    private var iconColor: Color {
        if case .recorded = banner { return .green }
        return .secondary
    }
}
