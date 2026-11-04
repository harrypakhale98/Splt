import SwiftUI

/// The segmented control above the bar: Equal, Percent, Shares, Exact, Adjust, Items.
/// It is the system control, so it gets Liquid Glass for free. At accessibility text sizes it becomes
/// a scrolling row of glass buttons that never truncate.
struct SplitMethodSwitcher: View {
    let selection: SplitMethod
    var onSelect: @MainActor @Sendable (SplitMethod) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private let order: [SplitMethod] = [.equal, .percentage, .shares, .exact, .adjustment, .itemized]

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                scrolling
            } else {
                Picker("Split method", selection: Binding(get: { selection }, set: onSelect)) {
                    ForEach(order) { method in
                        Text(method.shortTitle)
                            .accessibilityLabel(method.spokenShortTitle)
                            .tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("split-method")
            }
        }
        .haptics(.tick, trigger: selection)
    }

    private var scrolling: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(order) { method in
                        button(for: method)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Split method")
    }

    @ViewBuilder
    private func button(for method: SplitMethod) -> some View {
        let isSelected = method == selection
        let action = { onSelect(method) }
        Group {
            if isSelected {
                Button(action: action) { Text(method.shortTitle).foregroundStyle(PersonPalette.onColor) }.buttonStyle(.glassProminent)
            } else {
                Button(action: action) { Text(method.shortTitle) }.buttonStyle(.glass)
            }
        }
        .accessibilityLabel(method.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
