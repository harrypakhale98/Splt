import Foundation
import Testing
@testable import SpltCore

@Suite("Expense")
struct ExpenseTests {
    private let a = person(1), b = person(2), c = person(3)
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func dinner(total: Int64 = 9000, payers: [PersonID: Money]? = nil, split: SplitDefinition? = nil) -> Expense {
        Expense(
            title: "Dinner",
            total: usd(total),
            date: date,
            payers: payers ?? [a: usd(total)],
            split: split ?? .equal(participants: [a, b, c])
        )
    }

    @Test func netBalancesAreWhatYouPaidMinusWhatYouOwe() throws {
        let net = try dinner().netBalances()
        #expect(net == [a: usd(6000), b: usd(-3000), c: usd(-3000)])
    }

    @Test func netBalancesAddUpToZeroWithOddCents() throws {
        let net = try dinner(total: 1000).netBalances()
        #expect(net.values.reduce(0) { $0 + $1.minorUnits } == 0)
    }

    @Test func severalPayers() throws {
        let expense = dinner(total: 10_000, payers: [a: usd(6000), b: usd(4000)], split: .equal(participants: [a, b, c, person(4)]))
        let net = try expense.netBalances()
        #expect(net[a] == usd(3500))
        #expect(net[b] == usd(1500))
        #expect(net[c] == usd(-2500))
        #expect(net[person(4)] == usd(-2500))
    }

    @Test func aPayerWhoDoesNotParticipateIsOwedTheWholeShare() throws {
        let expense = dinner(total: 6000, payers: [a: usd(6000)], split: .equal(participants: [b, c]))
        #expect(try expense.netBalances() == [a: usd(6000), b: usd(-3000), c: usd(-3000)])
    }

    @Test func refundsFlowBackwards() throws {
        let refund = Expense(
            title: "Refund", total: usd(-3000), date: date,
            paidBy: a, split: .equal(participants: [a, b, c])
        )
        #expect(refund.isRefund)
        #expect(try refund.netBalances() == [a: usd(-2000), b: usd(1000), c: usd(1000)])
    }

    @Test func payersMustMatchTheTotal() {
        let expense = dinner(payers: [a: usd(5000)])
        #expect(throws: ExpenseError.payersDoNotMatchTotal(expected: usd(9000), actual: usd(5000))) {
            try expense.validate()
        }
    }

    @Test func needsAtLeastOnePayer() {
        #expect(throws: ExpenseError.noPayers) { try dinner(payers: [:]).validate() }
    }

    @Test func payerCurrencyMustMatch() {
        let expense = dinner(payers: [a: eur(9000)])
        #expect(throws: ExpenseError.currencyMismatch(expected: "USD", found: "EUR")) { try expense.validate() }
    }

    @Test func payerSignMustMatchTheDirectionOfTheExpense() {
        #expect(throws: ExpenseError.payerAmountPointsWrongWay(b)) {
            try dinner(payers: [a: usd(10_000), b: usd(-1000)]).validate()
        }
        let refund = Expense(
            title: "Refund", total: usd(-1000), date: date,
            payers: [a: usd(1500), b: usd(-2500)], split: .equal(participants: [a, b])
        )
        #expect(throws: ExpenseError.payerAmountPointsWrongWay(a)) { try refund.validate() }
    }

    @Test func invalidSplitsAreReported() {
        let expense = dinner(split: .percentages(basisPoints: [a: 5000]))
        #expect(throws: ExpenseError.invalidSplit(.percentagesDoNotSumToHundred(actualBasisPoints: 5000))) {
            try expense.validate()
        }
    }

    @Test func sharesComeFromTheSplit() throws {
        let result = try dinner(split: .shares(weights: [a: 1, b: 2])).shares()
        #expect(result.shares == [a: usd(3000), b: usd(6000)])
    }

    @Test func participantsIncludePayersAndSplitMembers() {
        let expense = dinner(payers: [a: usd(9000)], split: .equal(participants: [b, c]))
        #expect(expense.participants == [a, b, c])
    }

    @Test func deletedFlag() {
        var expense = dinner()
        #expect(!expense.isDeleted)
        expense.deletedAt = date
        #expect(expense.isDeleted)
    }

    @Test func codableRoundTrip() throws {
        let expense = Expense(
            groupID: GroupID(), title: "Taxi", total: eur(2350), date: date, category: .transport,
            payers: [a: eur(2350)], split: .exact(amounts: [a: eur(1000), b: eur(1350)]), note: "airport"
        )
        let data = try JSONEncoder().encode(expense)
        #expect(try JSONDecoder().decode(Expense.self, from: data) == expense)
    }

    @Test func unknownCategoriesDecodeAsOther() throws {
        #expect(try JSONDecoder().decode(ExpenseCategory.self, from: Data(#""spaceship""#.utf8)) == .other)
        #expect(try JSONDecoder().decode(ExpenseCategory.self, from: Data(#""rent""#.utf8)) == .rent)
        #expect(try JSONEncoder().encode(ExpenseCategory.dining) == Data(#""dining""#.utf8))
    }
}

@Suite("Payment")
struct PaymentTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func validPaymentPasses() throws {
        try Payment(payer: person(1), receiver: person(2), amount: usd(500), date: date).validate()
    }

    @Test func rejectsPaymentsToYourself() {
        #expect(throws: PaymentError.samePerson) {
            try Payment(payer: person(1), receiver: person(1), amount: usd(500), date: date).validate()
        }
    }

    @Test func rejectsZeroAndNegativeAmounts() {
        #expect(throws: PaymentError.nonPositiveAmount) {
            try Payment(payer: person(1), receiver: person(2), amount: usd(0), date: date).validate()
        }
        #expect(throws: PaymentError.nonPositiveAmount) {
            try Payment(payer: person(1), receiver: person(2), amount: usd(-5), date: date).validate()
        }
    }

    @Test func settlesADebt() {
        let debt = Debt(debtor: person(2), creditor: person(1), amount: usd(1250))
        let payment = Payment(settling: debt, date: date)
        #expect(payment.payer == person(2))
        #expect(payment.receiver == person(1))
        #expect(payment.amount == usd(1250))
    }

    @Test func codableRoundTrip() throws {
        let payment = Payment(groupID: GroupID(), payer: person(1), receiver: person(2), amount: usd(500), date: date, note: "cash")
        let data = try JSONEncoder().encode(payment)
        #expect(try JSONDecoder().decode(Payment.self, from: data) == payment)
    }
}
