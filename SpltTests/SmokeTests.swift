import Testing
@testable import Splt

@Suite("Smoke")
struct SmokeTests {
    @Test func rootViewBuilds() {
        _ = RootView()
    }
}
