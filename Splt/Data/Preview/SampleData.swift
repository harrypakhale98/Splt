#if DEBUG
import Foundation
import SpltCore

/// A believable trip with five friends, for previews and tests. Only built in debug.
enum SampleData {
    struct Trip {
        var me: Person
        var maya: Person
        var jonas: Person
        var priya: Person
        var diego: Person
        var hana: Person
        var trip: SplitGroup
        var flat: SplitGroup
        var friendGroup: SplitGroup
        var expenses: [String: ExpenseID]
        var payments: [PaymentID]

        var friends: [Person] { [maya, jonas, priya, diego, hana] }
    }

    /// Services on an in-memory store that already holds the sample data.
    @MainActor
    static func previewServices() -> DataServices {
        do {
            let services = try DataServices.inMemory(now: SampleClock().tick)
            _ = try populate(into: services)
            services.groupsStore.refresh()
            services.friendsStore.refresh()
            return services
        } catch {
            fatalError("Sample data failed to load: \(error)")
        }
    }

    @MainActor
    static func populate(into services: DataServices) throws -> Trip {
        let people = services.people
        let me = try people.ensureMe(name: "Jamie Rivera")
        let maya = Person(id: id(11), name: "Maya Chen", contactHint: "maya@example.com", avatarSeed: 1, createdAt: day(-30))
        let jonas = Person(id: id(12), name: "Jonas Weber", contactHint: "jonas@example.com", avatarSeed: 2, createdAt: day(-30))
        let priya = Person(id: id(13), name: "Priya Nair", avatarSeed: 3, createdAt: day(-30))
        let diego = Person(id: id(14), name: "Diego Alvarez", avatarSeed: 4, createdAt: day(-30))
        let hana = Person(id: id(15), name: "Hana Sato", kind: .placeholder, avatarSeed: 5, createdAt: day(-30))
        for friend in [maya, jonas, priya, diego, hana] {
            try people.add(friend)
        }

        let trip = SplitGroup(
            id: GroupID(rawValue: uuid(101)), name: "Lisbon Trip", symbol: "airplane", currencyCode: "USD",
            kind: .trip, memberIDs: [me.id, maya.id, jonas.id, priya.id, diego.id, hana.id],
            tripStart: day(0), tripEnd: day(6), createdAt: day(-20)
        )
        let flat = SplitGroup(
            id: GroupID(rawValue: uuid(102)), name: "Flat 4B", symbol: "house.fill", currencyCode: "USD",
            memberIDs: [me.id, maya.id], createdAt: day(-90)
        )
        let friendGroup = SplitGroup(
            id: GroupID(rawValue: uuid(103)), name: "Priya", symbol: "person.fill", currencyCode: "USD",
            kind: .friend, memberIDs: [me.id, priya.id], createdAt: day(-60)
        )
        for group in [trip, flat, friendGroup] {
            try services.groups.create(group)
        }

        let all = Set(trip.memberIDs)
        var expenses: [String: ExpenseID] = [:]
        func add(_ key: String, _ title: String, _ cents: Int64, _ dayOffset: Int, _ category: ExpenseCategory,
                 payers: [PersonID: Int64], split: SplitDefinition, in group: SplitGroup? = nil) throws {
            let expense = Expense(
                id: ExpenseID(rawValue: uuid(200 + expenses.count)),
                groupID: (group ?? trip).id, title: title, total: usd(payers.values.reduce(0, +)),
                date: day(dayOffset), category: category, payers: payers.mapValues(usd), split: split
            )
            precondition(expense.total.minorUnits == cents, "payers must add up to the total of \(title)")
            try services.expenses.add(expense)
            expenses[key] = expense.id
        }

        try add("airbnb", "Airbnb in Alfama", 84_000, 0, .lodging, payers: [maya.id: 84_000], split: .equal(participants: all))
        try add("dinner", "Welcome dinner at Time Out Market", 12_640, 0, .dining, payers: [me.id: 12_640], split: .equal(participants: all))
        try add("taxi", "Taxi from the airport", 3_250, 0, .transport, payers: [priya.id: 3_250],
                split: .equal(participants: [priya.id, diego.id, hana.id]))
        try add("pasteis", "Pasteis de nata", 1_480, 1, .dining, payers: [diego.id: 1_480], split: .equal(participants: all))
        try add("groceries", "Groceries at Pingo Doce", 5_837, 1, .groceries, payers: [hana.id: 5_837],
                split: .shares(weights: [me.id: 2, maya.id: 2, jonas.id: 1, priya.id: 1, diego.id: 1, hana.id: 1]))
        try add("car", "Rental car for Sintra", 21_000, 2, .transport, payers: [jonas.id: 21_000],
                split: .exact(amounts: [me.id: usd(7_000), jonas.id: usd(7_000), priya.id: usd(7_000)]))
        try add("seafood", "Seafood dinner", 17_000, 3, .dining, payers: [diego.id: 17_000], split: .itemized(ItemizedSplit(
            items: [
                SplitItem(id: uuid(301), name: "Grilled sea bass", amount: usd(4_200), assignees: [me.id]),
                SplitItem(id: uuid(302), name: "Cataplana for three", amount: usd(7_800), assignees: [maya.id, jonas.id, priya.id]),
                SplitItem(id: uuid(303), name: "Vinho verde", amount: usd(3_200), assignees: all)
            ],
            tip: usd(1_800)
        )))
        try add("fado", "Fado night", 9_000, 4, .entertainment, payers: [me.id: 9_000],
                split: .percentages(basisPoints: [me.id: 2_500, maya.id: 2_500, jonas.id: 2_500, priya.id: 2_500]))
        try add("brunch", "Brunch in Principe Real", 7_200, 5, .dining, payers: [maya.id: 7_200],
                split: .adjustments(participants: all, adjustments: [hana.id: usd(600)]))
        try add("beachbar", "Beach bar in Cascais", 6_000, 5, .drinks, payers: [me.id: 4_000, jonas.id: 2_000],
                split: .equal(participants: all))
        try add("refund", "Museum tickets refund", -2_400, 5, .entertainment, payers: [priya.id: -2_400],
                split: .equal(participants: [maya.id, jonas.id, priya.id, diego.id]))
        try add("rent", "Rent", 120_000, 0, .rent, payers: [me.id: 120_000], split: .equal(participants: [me.id, maya.id]), in: flat)
        try add("coffee", "Coffee with Priya", 640, 2, .drinks, payers: [priya.id: 640],
                split: .equal(participants: [me.id, priya.id]), in: friendGroup)

        try add("mistake", "Airbnb cleaning fee (entered twice)", 4_000, 0, .lodging, payers: [maya.id: 4_000], split: .equal(participants: all))
        try services.expenses.delete(id: expenses["mistake"]!)

        let payment = Payment(
            id: PaymentID(rawValue: uuid(400)), groupID: trip.id, payer: jonas.id, receiver: maya.id,
            amount: usd(10_000), date: day(6), note: "Bank transfer"
        )
        try services.payments.record(payment)

        try services.comments.add(ExpenseComment(
            id: uuid(500), groupID: trip.id, expenseID: expenses["airbnb"], authorID: maya.id,
            text: "The booking confirmation is in our shared album.", createdAt: day(1)
        ))
        try services.comments.toggleReaction("\u{1F44D}", by: me.id, on: uuid(500))

        services.groupsStore.refresh()
        services.friendsStore.refresh()
        return Trip(
            me: me, maya: maya, jonas: jonas, priya: priya, diego: diego, hana: hana,
            trip: trip, flat: flat, friendGroup: friendGroup, expenses: expenses, payments: [payment.id]
        )
    }

    private static func usd(_ cents: Int64) -> Money {
        Money(minorUnits: cents, currencyCode: "USD")
    }

    private static func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012ld", number))!
    }

    private static func id(_ number: Int) -> PersonID {
        PersonID(rawValue: uuid(number))
    }

    /// The trip starts on 8 May 2026; other dates are counted from it.
    private static func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_778_241_600 + TimeInterval(offset) * 86_400)
    }
}

/// A clock that moves forward a second per reading, so previews get a plausible activity order.
final class SampleClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_778_241_600 + 7 * 86_400)

    @Sendable func tick() -> Date {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(30)
        return current
    }
}
#endif
