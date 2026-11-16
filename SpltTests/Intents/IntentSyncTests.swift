import Foundation
import Testing
@testable import Splt

@MainActor
@Suite("Intent sync")
struct IntentSyncTests {
    @Test func anIntentStartsSyncAndSendsWhatItSaved() async throws {
        let engine = FakeSyncEngine()
        let runtime = SyncRuntime(makeEngine: { _ in engine })
        let intents = IntentServices()
        intents.use(try DataServices.inMemory())

        await intents.sendChanges(runtime: runtime)
        #expect(engine.startCount == 1)
        #expect(engine.sendCount == 1)

        // sync that is already running is not started again
        await intents.sendChanges(runtime: runtime)
        #expect(engine.startCount == 1)
        #expect(engine.sendCount == 2)
    }
}
