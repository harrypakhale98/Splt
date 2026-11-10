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
    /// The drag hint shows until the first drag, then never again.
    @AppStorage("expenses.splitBarDragged") private var hasDragged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader("Split")
                Spacer()
                if model.barData != nil {
                    Button(showsList ? "Bar" : "List") {
                        Motion.perform(Motion.smooth) { listOverride = !showsList }
                    }
                    .font(.subheadline)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                    .accessibilityLabel(showsList ? "Show as Bar" : "Show as List")
                }
            }

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
                            if !hasDragged { Motion.perform(Motion.smooth) { hasDragged = true } }
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
                    .foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
        }
    }

    private var showsList: Bool {
        listOverride ?? (voiceOver || typeSize.isAccessibilitySize)
    }

    @ViewBuilder
    private func caption(_ data: SplitBarData) -> some View {
        // Itemized needs no caption: the items tray above already says what to do.
        if data.method == .itemized {
            EmptyView()
        } else if data.total == nil {
            Text("Enter an amount to see what everyone pays.")
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
        } else if data.canDrag, !hasDragged {
            Text("Drag the dividers. Tap a person to fine tune.")
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
                .motionTransition(.opacity)
        }
    }
}
