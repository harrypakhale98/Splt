import SpltCore
import SwiftUI

struct RepeatSection: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section {
            Picker("Repeat", selection: $model.repeatChoice.frequency) {
                if !model.isEditingRecurring {
                    Text("Never").tag(RecurrenceFrequency?.none)
                }
                ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                    Text(frequency.title).tag(Optional(frequency))
                }
            }
            if model.repeatChoice.frequency != nil {
                Toggle("End Date", isOn: Binding(
                    get: { model.repeatChoice.endDate != nil },
                    set: { model.repeatChoice.endDate = $0 ? Calendar.current.date(byAdding: .year, value: 1, to: model.date).map { RepeatChoice.lastMoment(of: $0) } : nil }
                ))
                if let end = model.repeatChoice.endDate {
                    DatePicker(
                        "Ends", selection: Binding(get: { end }, set: { model.repeatChoice.endDate = RepeatChoice.lastMoment(of: $0) }),
                        in: model.date..., displayedComponents: .date
                    )
                }
            }
        } header: {
            Text("Repeat").foregroundStyle(.legible)
        } footer: {
            if let frequency = model.repeatChoice.frequency, !model.isEditingRecurring {
                Text("A new expense is added automatically \(frequency.footerPhrase), starting after this one.")
            }
        }
    }
}

extension RepeatChoice {
    /// The end date is picked as a day and that day counts, so an occurrence at any time on it is included.
    static func lastMoment(of day: Date, calendar: Calendar = .current) -> Date {
        let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))
        return next?.addingTimeInterval(-1) ?? day
    }
}

extension RecurrenceFrequency {
    var title: String {
        switch self {
        case .daily: String(localized: "Every Day")
        case .weekly: String(localized: "Every Week")
        case .biweekly: String(localized: "Every 2 Weeks")
        case .semiMonthly: String(localized: "Twice a Month")
        case .monthly: String(localized: "Every Month")
        case .quarterly: String(localized: "Every 3 Months")
        case .yearly: String(localized: "Every Year")
        }
    }

    var footerPhrase: String {
        switch self {
        case .daily: String(localized: "every day")
        case .weekly: String(localized: "every week")
        case .biweekly: String(localized: "every two weeks")
        case .semiMonthly: String(localized: "twice a month")
        case .monthly: String(localized: "every month")
        case .quarterly: String(localized: "every three months")
        case .yearly: String(localized: "every year")
        }
    }
}
