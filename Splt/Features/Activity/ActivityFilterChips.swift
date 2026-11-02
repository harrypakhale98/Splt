import SpltCore
import SwiftUI

/// The feed filters as a row of glass chips: one per kind of event, and a menu for the group.
struct ActivityFilterChips: View {
    @Bindable var model: ActivityModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(ActivityTypeFilter.allCases) { filter in
                        chip(filter)
                    }
                    if model.filterGroups.count > 1 {
                        groupMenu
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .mask {
            // the last chips fade out at the edge, a hint that the row scrolls
            LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.93), .init(color: .clear, location: 1)],
                startPoint: .leading, endPoint: .trailing
            )
        }
        .accessibilityElement(children: .contain)
    }

    private func chip(_ filter: ActivityTypeFilter) -> some View {
        let selected = model.typeFilter == filter
        return Button {
            model.typeFilter = filter
        } label: {
            Text(filter.shortTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 32)
        }
        .chipStyle(selected: selected)
        .accessibilityLabel(filter.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .haptics(.tick, trigger: selected)
    }

    private var groupMenu: some View {
        let selected = model.groupFilter.flatMap { id in model.filterGroups.first { $0.id == id } }
        return Menu {
            Picker("Group", selection: $model.groupFilter) {
                Text("All Groups").tag(GroupID?.none)
                ForEach(model.filterGroups) { group in
                    Label(group.name, systemImage: group.symbol).tag(Optional(group.id))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selected?.name ?? String(localized: "All Groups"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 32)
        }
        .chipStyle(selected: selected != nil)
        .accessibilityLabel("Group")
        .accessibilityValue(selected?.name ?? String(localized: "All Groups"))
    }
}

private extension View {
    /// A selected chip is solid accent with white text, the others are plain glass, so the choice reads at a glance.
    @ViewBuilder
    func chipStyle(selected: Bool) -> some View {
        if selected {
            buttonStyle(.glassProminent).buttonBorderShape(.capsule)
        } else {
            buttonStyle(.glass).buttonBorderShape(.capsule)
        }
    }
}
