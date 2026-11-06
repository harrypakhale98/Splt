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

/// A compact banner: one icon, at most two lines of text and a single Undo button, whatever the text size.
/// The full sentence is always what VoiceOver reads.
struct SettleUndoBanner: View {
    let banner: SettleUndoCenter.Banner
    let center: SettleUndoCenter

    @Environment(\.dataServices) private var services

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Ink.text)
                .accessibilityHidden(true)
            Text(banner.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(banner.message)
            if case .recorded = banner, let services {
                Button("Undo") { center.undo(using: services.payments) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Ink.text)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .cardSurface()
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        if case .recorded = banner { return "checkmark.circle.fill" }
        return "arrow.uturn.backward.circle.fill"
    }
}
