import SwiftUI

extension View {
    /// Shows the undo banner above the tab bar and makes the center available to settle sheets.
    /// Apply to the app's TabView.
    func settleUndoBanner() -> some View {
        modifier(SettleUndoBannerModifier())
    }
}

private struct SettleUndoBannerModifier: ViewModifier {
    @State private var center = SettleUndoCenter()

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            // The system places the accessory just above the tab bar, whatever its size or state,
            // and gives it the bar's glass.
            content
                .environment(\.settleUndo, center)
                .tabViewBottomAccessory(isEnabled: center.banner != nil) {
                    if let banner = center.banner {
                        SettleUndoBanner(banner: banner, center: center, isAccessory: true)
                    }
                }
        } else {
            content
                .environment(\.settleUndo, center)
                .overlay(alignment: .bottom) {
                    if let banner = center.banner {
                        SettleUndoBanner(banner: banner, center: center, isAccessory: false)
                            .padding(.horizontal)
                            // iOS 26.0 has no way to sit above the tab bar, so clear its usual height.
                            .padding(.bottom, 96)
                            .ignoresSafeArea(.keyboard, edges: .bottom)
                            .motionTransition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .motion(Motion.settle, value: center.banner)
        }
    }
}

/// A compact banner: at most two lines of text and a single Undo button, whatever the text size.
/// The full sentence is always what VoiceOver reads.
struct SettleUndoBanner: View {
    let banner: SettleUndoCenter.Banner
    let center: SettleUndoCenter
    /// Inside the tab bar's accessory, which brings its own glass and has room for one line.
    var isAccessory = false

    @Environment(\.dataServices) private var services

    var body: some View {
        HStack(spacing: 12) {
            Text(banner.message)
                .font(.subheadline)
                .lineLimit(isAccessory ? 1 : 2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(banner.message)
            if case .recorded = banner, let services {
                Button("Undo") { center.undo(using: services.payments) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.text)
                    .fixedSize()
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isAccessory ? 0 : 2)
        .frame(minHeight: 44)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .modifier(BannerSurface(isOn: !isAccessory))
        .motion(Motion.smooth, value: banner)
        .accessibilityElement(children: .contain)
    }
}

/// The card the banner sits on when it floats over the content by itself.
private struct BannerSurface: ViewModifier {
    let isOn: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isOn { content.cardSurface() } else { content }
    }
}
