import AppKit
import GraftCore
import IOKit.pwr_mgt
import Observation

@Observable
final class KeepAwakeService: NSObject {
    static let codexBundleID = "com.openai.codex"

    private struct PowerAssertion {
        let id: IOPMAssertionID
        let keepsDisplayAwake: Bool
    }

    var isActive: Bool { assertion != nil }
    private(set) var detail = "Off"
    var onStopped: ((String, Bool) -> Void)?
    private var settings = MacSettings()
    private var assertion: PowerAssertion?
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let targetIsRunning: (MacSettings) -> Bool
    @ObservationIgnored private let createAssertion: (Bool) throws -> IOPMAssertionID
    @ObservationIgnored private let releaseAssertion: (IOPMAssertionID) -> Void
    @ObservationIgnored private let automaticallyMonitor: Bool

    init(
        now: @escaping () -> Date = Date.init,
        targetIsRunning: @escaping (MacSettings) -> Bool = { settings in
            guard let pid = settings.keepAwakeAppPID,
                  let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
                  app.bundleIdentifier == settings.keepAwakeAppBundleID else { return false }
            // ISO-8601 persistence has whole-second precision.
            if let expected = settings.keepAwakeAppLaunchDate, let actual = app.launchDate {
                return abs(expected.timeIntervalSince(actual)) < 1
            }
            return true
        },
        createAssertion: @escaping (Bool) throws -> IOPMAssertionID = { keepDisplayAwake in
            // Holding the display awake also prevents idle system sleep.
            let type = keepDisplayAwake
                ? kIOPMAssertionTypePreventUserIdleDisplaySleep
                : kIOPMAssertionTypePreventUserIdleSystemSleep
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Graft Caffeinate" as CFString, &id
            )
            guard result == kIOReturnSuccess else {
                throw NSError(domain: "Graft.KeepAwake", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "macOS could not start Caffeinate (\(result))."])
            }
            return id
        },
        releaseAssertion: @escaping (IOPMAssertionID) -> Void = { _ = IOPMAssertionRelease($0) },
        automaticallyMonitor: Bool = true
    ) {
        self.now = now
        self.targetIsRunning = targetIsRunning
        self.createAssertion = createAssertion
        self.releaseAssertion = releaseAssertion
        self.automaticallyMonitor = automaticallyMonitor
        super.init()
        if automaticallyMonitor {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        }
    }

    isolated deinit {
        monitor?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let assertion { releaseAssertion(assertion.id) }
    }

    func apply(_ settings: MacSettings) {
        let wasEnabled = self.settings.keepAwake
        self.settings = settings
        guard settings.keepAwake else {
            release()
            if wasEnabled { detail = "Off" }
            return
        }
        if let reason = stopReason() {
            stop(reason)
            return
        }
        if assertion?.keepsDisplayAwake != settings.keepAwakeDisplay {
            do {
                let id = try createAssertion(settings.keepAwakeDisplay)
                // Acquire the replacement before releasing the active assertion.
                if let assertion { releaseAssertion(assertion.id) }
                assertion = PowerAssertion(id: id, keepsDisplayAwake: settings.keepAwakeDisplay)
            } catch {
                stop(error.localizedDescription, failed: true)
                return
            }
        }
        switch settings.keepAwakeMode {
        case .untilTurnedOff: detail = "Awake until stopped"
        case .thirtyMinutes, .oneHour, .twoHours, .fourHours, .custom:
            let endTime = settings.keepAwakeDeadline?.formatted(date: .omitted, time: .shortened) ?? "the timer ends"
            detail = "Awake until \(endTime)"
        case .untilAppQuits:
            let app = settings.keepAwakeAppPID.flatMap { NSRunningApplication(processIdentifier: $0) }
            let name = app.map(Self.targetName(for:)) ?? settings.keepAwakeAppBundleID
            detail = "Awake until \(name) quits"
        }
        updateMonitor()
    }

    static func targetName(for app: NSRunningApplication) -> String {
        if app.bundleIdentifier == codexBundleID {
            return app.localizedName == "ChatGPT" ? "Codex (ChatGPT)" : "Codex"
        }
        return app.localizedName ?? app.bundleIdentifier ?? "Application"
    }

    func checkNow() {
        guard settings.keepAwake, let reason = stopReason() else { return }
        stop(reason)
    }

    func shutdown() {
        release()
        settings.keepAwake = false
        detail = "Off"
    }

    @objc private func appTerminated(_ notification: Notification) { checkNow() }

    private func stopReason() -> String? {
        switch settings.keepAwakeMode {
        case .thirtyMinutes, .oneHour, .twoHours, .fourHours, .custom:
            guard let deadline = settings.keepAwakeDeadline else { return "Choose a duration and start Caffeinate again." }
            return now() >= deadline ? "Caffeinate timer finished." : nil
        case .untilAppQuits:
            return targetIsRunning(settings) ? nil : "The chosen app is no longer running."
        case .untilTurnedOff: return nil
        }
    }

    private func stop(_ message: String, failed: Bool = false) {
        release()
        settings.keepAwake = false
        detail = message
        onStopped?(message, failed)
    }

    private func updateMonitor() {
        guard automaticallyMonitor else { return }
        guard settings.keepAwakeMode != .untilTurnedOff else {
            monitor?.cancel()
            monitor = nil
            return
        }
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.checkNow()
            }
        }
    }

    private func release() {
        monitor?.cancel()
        monitor = nil
        if let assertion {
            releaseAssertion(assertion.id)
            self.assertion = nil
        }
    }
}
