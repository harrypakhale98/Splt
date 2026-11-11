import SpltCore
import SwiftUI

/// The group's Spending tab: your share over a range as the one figure, the group's total under it,
/// then your share by month, what each person paid for the whole group, and your share by category.
/// Each currency keeps its own charts, since amounts in different currencies are never added up.
struct GroupSpendingSection: View {
    let model: GroupDetailViewModel
    var onRecap: () -> Void = {}

    @State private var range: SpendingRange = .last12Months
    @Environment(\.locale) private var locale

    var body: some View {
        if model.expenses.isEmpty {
            Section {
                GroupPaperNote("Spending appears once the group has expenses.")
            }
        } else {
            let summary = model.spending(in: range)
            let buckets = summary.buckets
            let isMixed = buckets.count > 1
            Section {
                hero(summary)
                    .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if buckets.isEmpty {
                Section {
                    GroupPaperNote("Nothing was spent in this period.")
                }
            }
            ForEach(buckets) { bucket in
                monthSection(bucket, months: summary.months, isMixed: isMixed)
                paidSection(bucket, isMixed: isMixed)
                categorySection(bucket, isMixed: isMixed)
            }
            if model.recapStats != nil {
                recapSection
            }
        }
    }

    // MARK: Hero

    private func hero(_ summary: SpendingSummary) -> some View {
        let lead = summary.buckets.first
        let share = lead?.shareMoney ?? .zero(currencyCode: model.group?.currencyCode ?? "USD")
        return SpendingHero(range: $range, share: share) {
            if let lead {
                Text("Group total \(money(lead.totalMoney)) · \(range.phrase) · ^[\(lead.expenseCount) expense](inflect: true) in \(lead.currencyCode)")
            }
            ForEach(summary.buckets.dropFirst()) { other in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(money(other.shareMoney))
                        .font(Typeface.figure)
                        .foregroundStyle(Ink.text)
                    Text("your share · group total \(money(other.totalMoney)) · ^[\(other.expenseCount) expense](inflect: true) in \(other.currencyCode)")
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Charts

    private func monthSection(_ bucket: SpendingSummary.Bucket, months: [Date], isMixed: Bool) -> some View {
        Section {
            RaisedRows {
                MonthBars(months: months, amounts: months.indices.map { bucket.monthMoney($0) })
            }
        } header: {
            Group {
                if isMixed {
                    SectionHeader("By month in \(bucket.currencyCode) · your share")
                } else {
                    SectionHeader("By month · your share")
                }
            }
            .padding(.horizontal, Depth.pageMargin + 4)
        }
        .raisedSection()
    }

    @ViewBuilder
    private func paidSection(_ bucket: SpendingSummary.Bucket, isMixed: Bool) -> some View {
        let people = bucket.personRows(names: model.chartNames)
        if !people.isEmpty {
            Section {
                let _ = PersonColorRevision.shared.value
                let colors = OrbitColors(members: model.group?.memberIDs ?? [])
                let dates = model.dates(of: range)
                RaisedRows {
                    SpendingBarChart(
                        title: isMixed
                            ? String(localized: "Paid by person in \(bucket.currencyCode) · whole group")
                            : String(localized: "Paid by person · whole group"),
                        rows: people,
                        color: { row in row.personID.map { colors.color(for: $0) } },
                        onSelect: { row in if let person = row.personID { model.showExpenses(paidBy: person, during: dates) } }
                    )
                }
            } header: {
                Group {
                    if isMixed {
                        SectionHeader("Paid by person in \(bucket.currencyCode) · whole group")
                    } else {
                        SectionHeader("Paid by person · whole group")
                    }
                }
                .padding(.horizontal, Depth.pageMargin + 4)
            }
            .raisedSection()
        }
    }

    @ViewBuilder
    private func categorySection(_ bucket: SpendingSummary.Bucket, isMixed: Bool) -> some View {
        let categories = bucket.categoryRows
        if !categories.isEmpty {
            Section {
                let dates = model.dates(of: range)
                RaisedRows {
                    SpendingBarChart(
                        title: isMixed
                            ? String(localized: "By category in \(bucket.currencyCode) · your share")
                            : String(localized: "By category · your share"),
                        rows: categories,
                        // only the largest category speaks; the rest stay grey, as in the recap
                        color: { row in row.id == categories.first?.id ? Ink.text : Ink.tertiary },
                        onSelect: { row in if let category = row.category { model.showExpenses(in: category, during: dates) } }
                    )
                }
            } header: {
                Group {
                    if isMixed {
                        SectionHeader("By category in \(bucket.currencyCode) · your share")
                    } else {
                        SectionHeader("By category · your share")
                    }
                }
                .padding(.horizontal, Depth.pageMargin + 4)
            }
            .raisedSection()
        }
    }

    private var recapSection: some View {
        Section {
            Button(action: onRecap) {
                HStack {
                    Text("Watch the Recap")
                        .foregroundStyle(Ink.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Ink.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .raisedRow()
        }
        .raisedSection()
    }

    private func money(_ money: Money) -> String {
        MoneyFormatting.string(money, locale: locale, showsSign: money.minorUnits < 0)
    }
}
