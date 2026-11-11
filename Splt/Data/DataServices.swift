import Foundation
import SwiftData

/// Builds the repositories and stores on one container. The app creates one at launch and passes
/// the pieces to the views; tests and previews build their own on an in-memory container.
@MainActor
final class DataServices {
    let container: ModelContainer
    let environment: RepositoryContext

    let people: any PersonRepository
    let groups: any GroupRepository
    let expenses: any ExpenseRepository
    let payments: any PaymentRepository
    let comments: any CommentRepository
    let activity: any ActivityRepository
    let recurring: any RecurringExpenseRepository
    let claims: any ItemClaimRepository
    let search: any SearchRepository
    let rates: RatesService

    let groupsStore: GroupsStore
    let friendsStore: FriendsStore

    private var currencyObserver: ContainerChangeObserver?
    private var warmedCurrencies: Set<String> = []

    init(
        container: ModelContainer,
        rates: RatesService = .offline(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.container = container
        self.rates = rates
        let environment = RepositoryContext(container: container, now: now)
        self.environment = environment
        let people = SwiftDataPersonRepository(environment)
        let groups = SwiftDataGroupRepository(environment)
        let expenses = SwiftDataExpenseRepository(environment)
        let activity = SwiftDataActivityRepository(environment)
        self.people = people
        self.groups = groups
        self.expenses = expenses
        self.payments = SwiftDataPaymentRepository(environment)
        self.comments = SwiftDataCommentRepository(environment)
        self.activity = activity
        self.recurring = SwiftDataRecurringExpenseRepository(environment)
        self.claims = SwiftDataItemClaimRepository(environment, expenses: expenses)
        self.search = SwiftDataSearchRepository(environment)
        self.groupsStore = GroupsStore(groups: groups, people: people, activity: activity, container: container)
        self.friendsStore = FriendsStore(people: people, container: container)
        currencyObserver = ContainerChangeObserver(container: container) { [weak self] in self?.warmRatesIfNeeded() }
        warmRatesIfNeeded()
    }

    /// Services on the on-disk store.
    static func live() throws -> DataServices {
        DataServices(container: try ModelContainerFactory.make(), rates: .live())
    }

    /// Services on a throwaway in-memory store, for tests and previews.
    static func inMemory(
        rates: RatesService = .offline(), now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> DataServices {
        DataServices(container: try ModelContainerFactory.make(inMemory: true), rates: rates, now: now)
    }

    /// Rates for the expense form's seam: pinned group rate first, then the cached latest table.
    var expenseRates: ExpenseRates { .cached(by: rates) }

    private func warmRatesIfNeeded() {
        let currencies = Set(((try? groups.groups(includeArchived: false)) ?? []).map(\.currencyCode))
        guard currencies != warmedCurrencies else { return }
        warmedCurrencies = currencies
        Task { @MainActor [rates] in await rates.warmUp(currencies: currencies) }
    }

    /// A tracker on the main context for the sync engine, or on a context of its own for background work.
    func makeChangeTracker(context: ModelContext? = nil) -> ChangeTracker {
        ChangeTracker(context: context ?? container.mainContext, balanceCache: environment.balanceCache, now: environment.now)
    }
}
