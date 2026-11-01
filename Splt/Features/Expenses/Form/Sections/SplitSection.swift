import SpltCore
import SwiftUI

struct SplitSection: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section {
            Picker("Split", selection: $model.split.method) {
                ForEach(SplitMethod.allCases) { method in
                    Label(method.title, systemImage: method.symbolName).tag(method)
                }
            }

            if model.split.method != .itemized {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Split with")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    PeopleChips(
                        people: model.members, selected: model.participants,
                        currentPerson: model.me?.id, toggle: model.toggleParticipant
                    )
                }
            }
        } header: {
            Text("Split")
        } footer: {
            Text(model.split.method.explanation)
        }

        editor
        SharePreviewSection(model: model)
    }

    @ViewBuilder
    private var editor: some View {
        switch model.split.method {
        case .equal:
            EmptyView()
        case .exact:
            ExactSplitEditor(model: model)
        case .percentage:
            PercentSplitEditor(model: model)
        case .shares:
            SharesSplitEditor(model: model)
        case .adjustment:
            AdjustmentSplitEditor(model: model)
        case .itemized:
            ItemizedSplitEditor(model: model)
        }
    }
}

/// What each person owes, as the calculator works it out right now.
struct SharePreviewSection: View {
    let model: ExpenseFormModel

    var body: some View {
        let rows = model.sharePreview
        if !rows.isEmpty {
            Section("Each Person Pays") {
                ForEach(rows, id: \.person.id) { row in
                    HStack {
                        AvatarView(name: row.person.name, size: 28)
                        Text(model.displayName(for: row.person.id))
                        Spacer(minLength: 8)
                        MoneyLabel(money: row.amount)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(model.displayName(for: row.person.id)) pays \(MoneyFormatting.magnitudeString(row.amount, locale: model.locale))"
                    )
                }
            }
        }
    }
}
