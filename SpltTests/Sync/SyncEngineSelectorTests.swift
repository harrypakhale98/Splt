import Testing
@testable import Splt

@Suite("Sync engine selection")
struct SyncEngineSelectorTests {
    @Test func signedDeviceWithAnAccountUsesCloudKit() {
        let choice = SyncEngineSelector.decide(.signedDevice(), account: .available)
        #expect(choice == .cloudKit(containerIdentifier: "iCloud.com.example.app"))
    }

    @Test func simulatorPreviewsAndTestsNeverUseCloudKit() {
        var simulator = SyncEnvironment.signedDevice()
        simulator.isSimulator = true
        var preview = SyncEnvironment.signedDevice()
        preview.isPreview = true
        var testing = SyncEnvironment.signedDevice()
        testing.isTesting = true
        #expect(SyncEngineSelector.decide(simulator, account: .available) == .noOp(.simulator))
        #expect(SyncEngineSelector.decide(preview, account: .available) == .noOp(.preview))
        #expect(SyncEngineSelector.decide(testing, account: .available) == .noOp(.testing))
    }

    @Test func missingEntitlementNeverReachesTheAccountCheck() {
        let environment = SyncEnvironment.signedDevice(entitlements: .none)
        #expect(SyncEngineSelector.preflight(environment) == .missingEntitlement)
        #expect(SyncEngineSelector.decide(environment, account: .available) == .noOp(.missingEntitlement))
    }

    @Test func signedOutUsersGetTheNoAccountStatus() {
        let environment = SyncEnvironment.signedDevice(hasIdentityToken: false)
        #expect(SyncEngineSelector.decide(environment, account: .available) == .noOp(.noAccount))
        #expect(NoOpReason.noAccount.status == .noAccount)
    }

    @Test(arguments: [
        (AccountAvailability.noAccount, NoOpReason.noAccount),
        (.restricted, .restricted),
        (.unknown, .accountUnavailable),
    ])
    func accountStatesMapToReasons(account: AccountAvailability, reason: NoOpReason) {
        #expect(SyncEngineSelector.decide(.signedDevice(), account: account) == .noOp(reason))
    }

    @Test func buildsWithoutSyncReportUnavailable() {
        #expect(NoOpReason.simulator.status == .unavailable)
        #expect(NoOpReason.missingEntitlement.status == .unavailable)
        #expect(NoOpReason.restricted.status == .restricted)
    }
}
