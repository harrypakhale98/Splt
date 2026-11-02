import Testing
@testable import Splt

@Suite("Smoke")
struct SmokeTests {
    @Test @MainActor func rootViewBuilds() {
        _ = RootView()
    }
}
