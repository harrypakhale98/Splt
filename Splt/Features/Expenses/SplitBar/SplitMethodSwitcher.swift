import SwiftUI

/// The segmented control above the bar: Equal, Percent, Shares, Exact, Adjust, Items.
/// It is the system control. At accessibility text sizes it becomes a scrolling row of plain
/// text buttons that never truncate.
struct SplitMethodSwitcher: View {
    let selection: SplitMethod
    var onSelect: @MainActor @Sendable (SplitMethod) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private let order = SplitMethod.allCases

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                scrolling
            } else {
                Picker("Split method", selection: Binding(get: { selection }, set: { select($0) })) {
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
    }

    /// The tick plays from the tap, so a method change made by dragging the bar only gets the bar's detent.
    private func select(_ method: SplitMethod) {
        guard method != selection else { return }
        Haptics.play(.tick)
        onSelect(method)
    }

    private var scrolling: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                ForEach(order) { method in
                    button(for: method)
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
        Button { select(method) } label: {
            Text(method.shortTitle)
                .font(.body.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Ink.text : Ink.secondary)
                .underline(isSelected)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(method.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
