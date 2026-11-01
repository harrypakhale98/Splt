#if DEBUG
import SpltCore

/// The sample trip on an in-memory store, with the ids previews need.
@MainActor
enum ExpensePreviewSupport {
    struct Scene {
        let services: DataServices
        let trip: SampleData.Trip

        func expense(_ key: String) -> ExpenseID {
            trip.expenses[key] ?? ExpenseID()
        }
    }

    static func scene() -> Scene {
        do {
            let services = try DataServices.inMemory(now: SampleClock().tick)
            let trip = try SampleData.populate(into: services)
            return Scene(services: services, trip: trip)
        } catch {
            fatalError("Sample data failed to load: \(error)")
        }
    }
}
#endif
