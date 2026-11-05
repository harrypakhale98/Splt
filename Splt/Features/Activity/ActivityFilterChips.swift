import SpltCore
import SwiftUI

/// The feed filters as plain text: one per kind of event, and a menu for the group.
/// The selected one is set in ink, bolder and underlined.
struct ActivityFilterChips: View {
    @Bindable var model: ActivityModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(ActivityTypeFilter.allCases) { filter in
                    option(filter)
                }
                if model.filterGroups.count > 1 {
                    groupMenu
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .contain)
    }

    private func option(_ filter: ActivityTypeFilter) -> some View {
        let selected = model.typeFilter == filter
        return Button {
            model.typeFilter = filter
        } label: {
            label(filter.shortTitle, selected: selected)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            HStack(spacing: 4) {
                label(selected?.name ?? String(localized: "All Groups"), selected: selected != nil)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Ink.secondary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Group")
        .accessibilityValue(selected?.name ?? String(localized: "All Groups"))
    }

    private func label(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? Ink.text : Ink.secondary)
            .underline(selected, color: Ink.text)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
    }
}
