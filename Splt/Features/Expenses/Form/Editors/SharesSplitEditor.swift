import SwiftUI

struct SharesSplitEditor: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section {
            RaisedRows {
                ForEach(model.participantList) { person in
                    let name = model.displayName(for: person.id)
                    let count = model.shareCount(for: person.id)
                    Stepper(value: Binding(
                        get: { count },
                        set: { model.setShareCount($0, for: person.id) }
                    ), in: 0...100, step: 1) {
                        HStack {
                            AvatarView(person: person, members: model.members.map(\.id), size: 28)
                            VStack(alignment: .leading) {
                                Text(name)
                                Text("\(count, format: .number.precision(.fractionLength(0...2))) shares")
                                    .font(.subheadline)
                                    .foregroundStyle(Ink.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .accessibilityLabel(name)
                    .accessibilityValue("\(count.formatted(.number.precision(.fractionLength(0...2)))) shares")
                }
            }
        } header: {
            SectionHeader("Shares")
        }
        .raisedSection()
    }
}
