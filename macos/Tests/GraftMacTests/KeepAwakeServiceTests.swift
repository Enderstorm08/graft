import Foundation
import GraftCore
import Testing
@testable import GraftMac

@MainActor
struct KeepAwakeServiceTests {
    @Test(arguments: [KeepAwakeMode.thirtyMinutes, .oneHour, .twoHours, .fourHours, .custom])
    func timedSessionsExpireAtOriginalDeadlineWithoutRestarting(mode: KeepAwakeMode) throws {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var created = 0
        var released: [UInt32] = []
        var stopped = 0
        let service = KeepAwakeService(now: { now }, createAssertion: { _ in created += 1; return 42 }, releaseAssertion: { released.append($0) }, automaticallyMonitor: false)
        service.onStopped = { _, _ in stopped += 1 }
        var settings = MacSettings()
        settings.keepAwake = true
        settings.keepAwakeMode = mode
        settings.keepAwakeDeadline = now.addingTimeInterval(try #require(settings.keepAwakeDuration))
        service.apply(settings)
        #expect(service.isActive)
        now = try #require(settings.keepAwakeDeadline).addingTimeInterval(-1)
        service.apply(settings)
        service.checkNow()
        #expect(created == 1)
        #expect(released.isEmpty)
        now = try #require(settings.keepAwakeDeadline)
        service.checkNow()
        service.checkNow()
        #expect(!service.isActive)
        #expect(released == [42])
        #expect(stopped == 1)
    }

    @Test func appBoundSessionEndsWhenChosenProcessExits() {
        var running = true
        var released = 0
        let service = KeepAwakeService(targetIsRunning: { settings in
            #expect(settings.keepAwakeAppPID == 123)
            return running
        }, createAssertion: { _ in 11 }, releaseAssertion: { _ in released += 1 }, automaticallyMonitor: false)
        var settings = MacSettings()
        settings.keepAwake = true
        settings.keepAwakeMode = .untilAppQuits
        settings.keepAwakeAppBundleID = "test.app"
        settings.keepAwakeAppPID = 123
        service.apply(settings)
        #expect(service.isActive)
        running = false
        service.checkNow()
        #expect(!service.isActive)
        #expect(released == 1)
    }

    @Test func shutdownReleasesExactlyOnceAndExpiredSessionsDoNotStart() {
        var created = 0
        var released = 0
        let service = KeepAwakeService(createAssertion: { _ in created += 1; return 7 }, releaseAssertion: { _ in released += 1 }, automaticallyMonitor: false)
        var settings = MacSettings()
        settings.keepAwake = true
        settings.keepAwakeMode = .thirtyMinutes
        settings.keepAwakeDeadline = Date.distantPast
        service.apply(settings)
        #expect(created == 0)
        settings.keepAwakeMode = .untilTurnedOff
        service.apply(settings)
        #expect(service.isActive)
        service.shutdown()
        service.shutdown()
        #expect(!service.isActive)
        #expect(released == 1)
    }

    @Test func deniedPowerAssertionDoesNotClaimActive() {
        let service = KeepAwakeService(createAssertion: { _ in throw CocoaError(.featureUnsupported) }, automaticallyMonitor: false)
        var failed = false
        service.onStopped = { _, wasFailure in failed = wasFailure }
        var settings = MacSettings()
        settings.keepAwake = true
        settings.keepAwakeMode = .untilTurnedOff
        service.apply(settings)
        #expect(!service.isActive)
        #expect(failed)
    }

    @Test func changingDisplayPreferenceAndExtendingAnActiveSession() throws {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var events: [String] = []
        let service = KeepAwakeService(
            now: { now },
            createAssertion: { keepsDisplayAwake in
                events.append(keepsDisplayAwake ? "display on" : "system on")
                return keepsDisplayAwake ? 22 : 11
            },
            releaseAssertion: { events.append("release \($0)") },
            automaticallyMonitor: false
        )
        var settings = MacSettings()
        settings.keepAwake = true
        settings.keepAwakeDeadline = now.addingTimeInterval(3600)
        service.apply(settings)
        let originalDeadline = try #require(settings.keepAwakeDeadline)

        settings.keepAwakeDisplay = true
        service.apply(settings)
        #expect(service.isActive)
        #expect(events == ["system on", "display on", "release 11"])

        settings.keepAwakeDeadline = originalDeadline.addingTimeInterval(1800)
        service.apply(settings)
        now = originalDeadline
        service.checkNow()
        #expect(service.isActive)
        #expect(events == ["system on", "display on", "release 11"])

        now = try #require(settings.keepAwakeDeadline)
        service.checkNow()
        #expect(!service.isActive)
        #expect(events == ["system on", "display on", "release 11", "release 22"])
    }

    @Test(arguments: [false, true])
    func realPowerAssertionStartsAndReleases(keepsDisplayAwake: Bool) {
        let service = KeepAwakeService(automaticallyMonitor: false)
        var settings = MacSettings()
        settings.keepAwake = true
        settings.keepAwakeMode = .untilTurnedOff
        settings.keepAwakeDisplay = keepsDisplayAwake
        service.apply(settings)
        #expect(service.isActive)
        service.shutdown()
        #expect(!service.isActive)
    }
}
