import SpltCore
import SwiftUI

struct SplitSection: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section {
            RaisedRows {
                Picker("Split", selection: $model.split.method) {
                    ForEach(SplitMethod.allCases) { method in
                        Label(method.title, systemImage: method.symbolName).tag(method)
                    }
                }

                if model.split.method != .itemized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Split with")
                            .font(.subheadline)
                            .foregroundStyle(Ink.secondary)
                        PeopleChips(
                            people: model.members, selected: model.participants,
                            currentPerson: model.me?.id, toggle: model.toggleParticipant
                        )
                    }
                }
            }
        } header: {
            SectionHeader("Split")
        } footer: {
            Text(model.split.method.explanation).foregroundStyle(Ink.secondary)
        }
        .raisedSection()

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
            Section {
                RaisedRows {
                    ForEach(rows, id: \.person.id) { row in
                        HStack {
                            AvatarView(person: row.person, members: model.members.map(\.id), size: 28)
                            Text(model.displayName(for: row.person.id))
                            Spacer(minLength: 8)
                            MoneyLabel(money: row.amount).font(Typeface.figure)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "\(model.displayName(for: row.person.id)) pays \(MoneyFormatting.magnitudeString(row.amount, locale: model.locale))"
                        )
                    }
                }
            } header: {
                SectionHeader("Each person pays")
            }
            .raisedSection()
        }
    }
}
