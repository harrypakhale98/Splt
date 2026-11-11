import SpltCore
import SwiftUI

/// How new expenses in a group start out split: equally between some people, by percentages or by
/// shares. The rows are the expense form's own editors; any expense can still be split differently.
struct DefaultSplitEditor: View {
    @Binding var draft: DefaultSplitDraft
    /// The members, in display order.
    let people: [Person]
    let me: PersonID?

    @Environment(\.locale) private var locale

    private var memberIDs: [PersonID] { people.map(\.id) }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Split method", selection: $draft.method) {
                        ForEach(DefaultSplit.Method.allCases, id: \.self) { method in
                            Text(method.splitMethod.shortTitle)
                                .accessibilityLabel(method.splitMethod.spokenShortTitle)
                                .tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    strip
                }
                .listRowInsets(EdgeInsets(top: 8, leading: Depth.pageMargin, bottom: 8, trailing: Depth.pageMargin))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                RaisedRows {
                    switch draft.method {
                    case .equal: equalRows
                    case .percentages: percentRows
                    case .shares: shareRows
                    }
                }
            } header: {
                SectionHeader(draft.method.header)
                    .padding(.horizontal, Depth.pageMargin + 4)
            } footer: {
                Text(footer)
                    .padding(.horizontal, Depth.pageMargin + 4)
            }
            .raisedSection()
        }
        .paperBackground()
        .navigationTitle("Default Split")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Each member's part as a strip of their colors, like the split bar on an expense.
    @ViewBuilder
    private var strip: some View {
        let weights = draft.weights(locale: locale) ?? [:]
        let inSplit = memberIDs.filter { weights[$0, default: 0] > 0 }
        if !inSplit.isEmpty {
            ShareStrip(
                people: inSplit, members: memberIDs, weights: inSplit.map { Double(weights[$0, default: 0]) }, height: 6
            )
            .frame(height: 6)
            .accessibilityHidden(true)
        }
    }

    private func name(_ person: Person) -> String {
        person.id == me ? String(localized: "You") : person.name
    }

    private var equalRows: some View {
        ForEach(people) { person in
            let isIn = draft.included.contains(person.id)
            Button {
                Haptics.play(.tick)
                if isIn { draft.included.remove(person.id) } else { draft.included.insert(person.id) }
            } label: {
                HStack(spacing: 12) {
                    AvatarView(person: person, members: memberIDs, size: 28)
                    Text(name(person))
                        .foregroundStyle(Ink.text)
                    Spacer()
                    if isIn {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Ink.text)
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityAddTraits(isIn ? .isSelected : [])
        }
    }

    @ViewBuilder
    private var percentRows: some View {
        ForEach(people) { person in
            PersonFieldRow(person: person, name: name(person), members: memberIDs, fieldWidth: 120) {
                HStack {
                    TextField("Percent", text: Binding(
                        get: { draft.percent[person.id, default: ""] },
                        set: { draft.percent[person.id] = $0 }
                    ), prompt: Text("0"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .accessibilityLabel("Percent for \(name(person))")
                    Text("%").foregroundStyle(Ink.secondary).accessibilityHidden(true)
                }
            }
        }
        let remaining = draft.percentRemaining(locale: locale)
        LabeledContent("Left to assign") {
            if remaining == 0 {
                Label {
                    Text("All assigned")
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            } else {
                Label {
                    Text((Double(remaining) / 10_000).formatted(.percent.locale(locale).precision(.fractionLength(0...2)))).monospacedDigit()
                } icon: {
                    Image(systemName: remaining < 0 ? "minus.circle.fill" : "exclamationmark.circle.fill")
                }
            }
        }
        .accessibilityElement(children: .combine)
        Button("Split Percentages Evenly") { draft.fillPercentagesEvenly(locale: locale) }
    }

    private var shareRows: some View {
        ForEach(people) { person in
            let count = draft.shareCount(for: person.id)
            Stepper(value: Binding(
                get: { count },
                set: { draft.setShareCount($0, for: person.id) }
            ), in: 0...100, step: 1) {
                HStack {
                    AvatarView(person: person, members: memberIDs, size: 28)
                    VStack(alignment: .leading) {
                        Text(name(person))
                        Text("\(count, format: .number.precision(.fractionLength(0...2))) shares")
                            .font(.subheadline)
                            .foregroundStyle(Ink.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .accessibilityLabel(name(person))
            .accessibilityValue("\(count.formatted(.number.precision(.fractionLength(0...2)))) shares")
        }
    }

    private var footer: String {
        let later = String(localized: "You can still split any expense differently.")
        switch draft.method {
        case .equal:
            return String(localized: "New expenses are split equally between the people ticked here. People who join later are included.")
                + " " + later
        case .percentages:
            var text = String(localized: "New expenses start with these percentages. People who join later start at 0%, so the others still add up to 100%.")
            if !draft.isValid(locale: locale) {
                text += " " + String(localized: "Until they add up to 100%, new expenses are split equally.")
            }
            return text + " " + later
        case .shares:
            return String(localized: "New expenses start with these shares. People who join later start with 1 share.")
                + " " + later
        }
    }
}

extension DefaultSplit.Method {
    /// The expense form's own method, for its titles.
    var splitMethod: SplitMethod {
        switch self {
        case .equal: .equal
        case .percentages: .percentage
        case .shares: .shares
        }
    }

    var title: String { splitMethod.title }

    fileprivate var header: LocalizedStringKey {
        switch self {
        case .equal: "Who's in"
        case .percentages: "Percentages"
        case .shares: "Shares"
        }
    }
}
