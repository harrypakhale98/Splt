import SpltCore
import SwiftUI

struct RepeatSection: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section {
            RaisedRows {
                Picker("Repeat", selection: $model.repeatChoice.frequency) {
                    if !model.isEditingRecurring {
                        Text("Never").tag(RecurrenceFrequency?.none)
                    }
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.title).tag(Optional(frequency))
                    }
                }
                if model.repeatChoice.frequency != nil {
                    let earliest = RepeatChoice.earliestEnd(start: model.date, now: model.dependencies.now())
                    Toggle("End Date", isOn: Binding(
                        get: { model.repeatChoice.endDate != nil },
                        set: { model.repeatChoice.endDate = $0 ? RepeatChoice.defaultEnd(from: earliest) : nil }
                    ))
                    if let end = model.repeatChoice.endDate {
                        DatePicker(
                            "Ends", selection: Binding(get: { end }, set: { model.repeatChoice.endDate = RepeatChoice.lastMoment(of: $0) }),
                            in: earliest..., displayedComponents: .date
                        )
                    }
                }
            }
        } footer: {
            if let frequency = model.repeatChoice.frequency, !model.isEditingRecurring {
                Text("A new expense is added automatically \(frequency.footerPhrase), starting after this one.")
            }
        }
        .raisedSection()
    }
}

extension RepeatChoice {
    /// The first day an end date can be. A template being edited may have started long ago,
    /// and an end before today would finish it at once.
    static func earliestEnd(start: Date, now: Date) -> Date {
        max(start, now)
    }

    /// The end date offered first: a year after the earliest one, counting that whole day.
    static func defaultEnd(from earliest: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .year, value: 1, to: earliest).map { lastMoment(of: $0, calendar: calendar) }
    }

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
