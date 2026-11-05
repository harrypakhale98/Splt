import SpltCore
import SwiftUI

struct ExpenseHistorySection: View {
    let model: ExpenseDetailModel
    @Environment(\.locale) private var locale

    var body: some View {
        if let details = model.details {
            Section(header: Text("History").foregroundStyle(Ink.secondary)) {
                ForEach(details.history.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary(of: entry))
                        if let detail = previousValues(of: entry) {
                            Text(detail).font(.subheadline).foregroundStyle(Ink.secondary)
                        }
                        Text(entry.date, format: .dateTime.day().month().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(Ink.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                let creator = details.createdBy.map { model.name(for: $0) } ?? String(localized: "Someone")
                let created = details.createdAt.formatted(date: .abbreviated, time: .shortened)
                Text("Added by \(creator) on \(created)")
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
            }
        }
    }

    private func summary(of entry: ExpenseEditEntry) -> String {
        let who = entry.editor.map { model.name(for: $0) } ?? String(localized: "Someone")
        let fields = entry.changedFields.map(\.displayName).formatted(.list(type: .and))
        return String(localized: "\(who) changed the \(fields)")
    }

    private func previousValues(of entry: ExpenseEditEntry) -> String? {
        var parts: [String] = []
        if let title = entry.previousTitle { parts.append(String(localized: "Title was \(title)")) }
        if let total = entry.previousTotal {
            parts.append(String(localized: "Amount was \(MoneyFormatting.magnitudeString(total, locale: locale))"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
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
