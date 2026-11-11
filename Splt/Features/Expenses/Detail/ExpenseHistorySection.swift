import SpltCore
import SwiftUI

struct ExpenseHistorySection: View {
    let model: ExpenseDetailModel
    @Environment(\.locale) private var locale

    var body: some View {
        if let details = model.details {
            Section {
                RaisedRows {
                    ForEach(model.historyLines(locale: locale)) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.text)
                            if let detail = line.detail {
                                Text(detail).font(.footnote).foregroundStyle(Ink.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    let creator = details.createdBy.map { $0 == model.me?.id ? String(localized: "you") : model.name(for: $0) }
                        ?? String(localized: "someone")
                    let created = details.createdAt.formatted(date: .abbreviated, time: .shortened)
                    Text("Added by \(creator) on \(created)")
                        .font(.subheadline)
                        .foregroundStyle(Ink.secondary)
                }
            } header: {
                SectionHeader("History")
            }
        }
    }
}

extension ExpenseField {
    var displayName: String {
        switch self {
        case .title: String(localized: "title")
        case .total: String(localized: "amount")
        case .date: String(localized: "date")
        case .category: String(localized: "category")
        case .payers: String(localized: "payers")
        case .split: String(localized: "split")
        case .note: String(localized: "notes")
        case .group: String(localized: "group")
        case .receipt: String(localized: "receipt")
        case .location: String(localized: "location")
        case .recurrence: String(localized: "repeat")
        }
    }
}
