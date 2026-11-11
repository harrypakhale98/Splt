import SpltCore
import SwiftUI

/// Your share of everything, in every group and with every friend, in your default currency.
/// Pushed with `Route.spending` from the top of Activity.
struct SpendingView: View {
    @Environment(\.dataServices) private var services

    var body: some View {
        Group {
            if let services {
                SpendingContent(services: services)
            } else {
                EmptyStateView.dataUnavailable
            }
        }
        .navigationTitle("Spending")
    }
}

private struct SpendingContent: View {
    @Environment(Router.self) private var router
    @Environment(\.locale) private var locale
    @State private var model: SpendingModel

    init(services: DataServices) {
        _model = State(initialValue: SpendingModel(services: services))
    }

    var body: some View {
        @Bindable var model = model

        List {
            Section {
                SpendingHero(range: $model.range, share: model.share) { heroLines }
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if model.didLoad, model.summary.isEmpty {
                Section {
                    GroupPaperNote("Nothing was spent in this period.")
                }
            }
            if let bucket = model.bucket {
                Section {
                    RaisedRows {
                        MonthBars(months: model.summary.months, amounts: model.summary.months.indices.map { bucket.monthMoney($0) })
                    }
                } header: {
                    header("By month · your share")
                }
                .raisedSection()

                let categories = bucket.categoryRows
                if !categories.isEmpty {
                    Section {
                        RaisedRows {
                            SpendingBarChart(
                                title: String(localized: "By category · your share"),
                                rows: categories,
                                color: { row in row.id == categories.first?.id ? Ink.text : Ink.tertiary }
                            )
                        }
                    } header: {
                        header("By category · your share")
                    }
                    .raisedSection()
                }
            }
            groupsSection
            friendsSection
            if let note = conversionNote {
                Section {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowInsets(EdgeInsets(top: 2, leading: Depth.pageMargin + 14, bottom: 24, trailing: Depth.pageMargin + 14))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .paperBackground()
    }

    // MARK: Hero

    @ViewBuilder
    private var heroLines: some View {
        if let count = countLine {
            Text(count)
        }
        let converted = model.convertedAmounts
        if !converted.isEmpty {
            Label {
                Text("Includes \(list(converted)), in \(currencyName(model.currencyCode))")
            } icon: {
                Image(systemName: "globe")
                    .imageScale(.small)
            }
            .labelStyle(SpendingNoteLabelStyle())
        }
        let left = model.notConvertedAmounts
        if !left.isEmpty {
            Label {
                if model.isLoadingRates {
                    Text("Getting exchange rates for \(list(left))")
                } else {
                    Text("Not included: \(list(left)), with no exchange rate yet")
                }
            } icon: {
                Image(systemName: "exclamationmark.circle")
                    .imageScale(.small)
            }
            .labelStyle(SpendingNoteLabelStyle())
        }
    }

    private var countLine: String? {
        let expenses = model.summary.yourExpenseCount
        guard expenses > 0 else { return nil }
        let groups = model.groupCount, friends = model.friendCount
        switch (groups > 0, friends > 0) {
        case (true, true):
            return String(localized: "^[\(expenses) expense](inflect: true) across ^[\(groups) group](inflect: true) and ^[\(friends) friend](inflect: true)")
        case (true, false):
            return String(localized: "^[\(expenses) expense](inflect: true) across ^[\(groups) group](inflect: true)")
        case (false, true):
            return String(localized: "^[\(expenses) expense](inflect: true) with ^[\(friends) friend](inflect: true)")
        case (false, false):
            return String(localized: "^[\(expenses) expense](inflect: true)")
        }
    }

    // MARK: Breakdown

    @ViewBuilder
    private var groupsSection: some View {
        let rows = model.groupRows
        if !rows.isEmpty {
            Section {
                RaisedRows {
                    SpendingBarChart(
                        title: String(localized: "By group"),
                        rows: rows.map(spendingRow),
                        color: { row in row.id == rows.first?.id.rawValue.uuidString ? Ink.text : Ink.tertiary },
                        onSelect: { row in
                            if let id = UUID(uuidString: row.id) { router.push(.group(id)) }
                        }
                    )
                }
            } header: {
                header("By group")
            }
            .raisedSection()
        }
    }

    @ViewBuilder
    private var friendsSection: some View {
        let rows = model.friendRows
        if !rows.isEmpty {
            Section {
                let _ = PersonColorRevision.shared.value
                RaisedRows {
                    SpendingBarChart(
                        title: String(localized: "With friends"),
                        rows: rows.map(spendingRow),
                        color: { row in row.personID.map { PersonPalette.color(for: $0) } },
                        onSelect: { row in
                            if let friend = row.personID { router.push(.friend(friend.rawValue)) }
                        }
                    )
                }
            } header: {
                header("With friends")
            }
            .raisedSection()
        }
    }

    private func spendingRow(_ row: SpendingModel.Row) -> SpendingRow {
        SpendingRow(id: row.id.rawValue.uuidString, label: row.label, money: row.share, personID: row.friend)
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        SectionHeader(title)
            .padding(.horizontal, Depth.pageMargin + 4)
    }

    // MARK: Conversion

    /// "Lisbon trip was in euros and Ski weekend in yen. Each expense is converted to US dollars at
    /// the reference rate on its date." Nil when nothing needed converting.
    private var conversionNote: String? {
        let groups = model.convertedGroups
        guard !groups.isEmpty else { return nil }
        let parts = groups.map { group in
            String(localized: "\(group.name) was in \(ListFormatter.localizedString(byJoining: group.currencies.map(currencyName)))")
        }
        let places = ListFormatter.localizedString(byJoining: parts)
        let target = currencyName(model.currencyCode)
        let how = model.usedPinnedRate
            ? String(localized: "Each expense is converted to \(target) at the reference rate on its date, or at the rate its group set.")
            : String(localized: "Each expense is converted to \(target) at the reference rate on its date.")
        return String(localized: "\(places). \(how)")
    }

    private func list(_ amounts: [Money]) -> String {
        ListFormatter.localizedString(byJoining: amounts.map { MoneyFormatting.string($0, locale: locale, showsSign: $0.minorUnits < 0) })
    }

    private func currencyName(_ code: String) -> String {
        CurrencyNames.plural(code, locale: locale)
    }
}

/// An icon and a line of text, with the icon in the quieter tertiary ink.
private struct SpendingNoteLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon
                .foregroundStyle(Ink.secondary)
                .accessibilityHidden(true)
            configuration.title
        }
        .font(.footnote)
    }
}

/// Currency names as they read in a sentence: "euros", "US dollars".
enum CurrencyNames {
    static func plural(_ code: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currencyPlural
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 0
        // "2 euros" without its number is the plural name; fall back to the code
        guard let text = formatter.string(from: 2) else { return code }
        let name = text.trimmingCharacters(in: CharacterSet.letters.inverted)
        return name.isEmpty ? code : name
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SpendingView()
    }
    .environment(Router())
    .environment(\.dataServices, SampleData.previewServices())
}
#endif
