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
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
    }

    private func chip(_ filter: ActivityTypeFilter) -> some View {
        let selected = model.typeFilter == filter
        return Button {
            model.typeFilter = filter
        } label: {
            GlassPill(tint: selected ? .accentColor : nil, isInteractive: true) {
                Label(filter.shortTitle, systemImage: filter.symbol)
                    .font(.subheadline.weight(.medium))
                    .labelStyle(.titleOnly)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(.capsule)
        .accessibilityElement(children: .ignore)
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
            GlassPill(tint: selected == nil ? nil : .accentColor, isInteractive: true) {
                HStack(spacing: 6) {
                    Text(selected?.name ?? String(localized: "All Groups"))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
        }
        .contentShape(.capsule)
        .accessibilityLabel("Group")
        .accessibilityValue(selected?.name ?? String(localized: "All Groups"))
    }
}
