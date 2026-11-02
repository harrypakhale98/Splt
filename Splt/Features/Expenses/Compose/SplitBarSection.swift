import SpltCore
import SwiftUI

struct PersonSelection: Identifiable {
    let id: PersonID
}

/// The method switcher, the Split Bar and a way to read it as a list.
struct SplitBarSection: View {
    @Bindable var model: ExpenseFormModel
    var onFineTune: (PersonID) -> Void
    var onInteract: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var listOverride: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Split").font(.headline)
                Spacer()
                if model.barData != nil {
                    Button {
                        listOverride = !showsList
                    } label: {
                        Label(showsList ? "Show Bar" : "Show List", systemImage: showsList ? "chart.bar.fill" : "list.bullet")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(showsList ? "Show bar" : "Show list")
                }
            }
            .padding(.horizontal, 0)

            SplitMethodSwitcher(selection: model.split.method) { method in
                onInteract()
                Motion.perform(.snappy) { model.selectMethod(method) }
            }
            .padding(.horizontal, typeSize.isAccessibilitySize ? -20 : 0)

            if let data = model.barData {
                let members = model.members.map(\.id)
                if showsList {
                    SplitShareList(data: data, members: members, currentPerson: model.me?.id) { person, increase in
                        model.adjustShare(of: person, increase: increase)
                    }
                } else {
                    SplitBarView(
                        data: data, members: members, currentPerson: model.me?.id, stepHint: model.barStepDescription,
                        onDrag: { divider, fraction in
                            onInteract()
                            return model.dragDivider(divider, toFraction: fraction)
                        },
                        onStep: { person, increase in model.adjustShare(of: person, increase: increase) },
                        onTap: onFineTune
                    )
                    caption(data)
                }
            } else {
                Text(model.split.method == .itemized
                     ? "Assign items to people and the bar fills in."
                     : "Choose at least one person to split with.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private var showsList: Bool {
        listOverride ?? (voiceOver || typeSize.isAccessibilitySize)
    }

    @ViewBuilder
    private func caption(_ data: SplitBarData) -> some View {
        if data.method == .itemized {
            Text("Assign each item to people and the bar fills in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if data.total == nil {
            Text("Enter an amount to see what everyone pays.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("Drag the dividers. Tap a person to fine tune.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
