import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics
import IOKit.pwr_mgt
import Observation
import SystemConfiguration

@Observable
final class ClosedLidSessionService {
    let isSupported = deviceSupportsClosedLid()
    private(set) var isActive = false
    private(set) var isStarting = false
    private(set) var isRestoring = false
    private(set) var detail = "Off"

    var deadline: Date? { session?.deadline }

    var canStart: Bool { isSupported && !isActive && !isStarting && !isRestoring }

    @ObservationIgnored private var session: Session?
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var sleepAfterExpiry: Task<Void, Never>?

    private struct Session {
        let token: UUID
        let deadline: Date
        var activationTimeout: ContinuousClock.Instant?
        var reachedActive = false
        var stopRequested = false
        var stopDetail = "Off"

        var marker: String { ClosedLidPowerScripts.releaseMarker(for: token) }
    }

    init() {
        guard isSupported else { return }
        refresh()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    isolated deinit {
        monitor?.cancel()
        sleepAfterExpiry?.cancel()
        if let session { _ = rmdir(session.marker) }
    }

    func start(until deadline: Date) {
        refresh()
        guard canStart else { return }
        let remaining = deadline.timeIntervalSinceNow
        guard remaining >= 1, remaining <= ClosedLidPowerScripts.maximumDuration else {
            detail = "Start a timed session of up to four hours first."
            return
        }
        guard ProcessInfo.processInfo.thermalState != .critical else {
            detail = "Let your MacBook cool down before starting."
            return
        }

        sleepAfterExpiry?.cancel()
        sleepAfterExpiry = nil
        let deadlineSeconds = Int64(deadline.timeIntervalSince1970.rounded(.down))
        let request = Session(token: UUID(), deadline: Date(timeIntervalSince1970: TimeInterval(deadlineSeconds)))
        guard mkdir(request.marker, 0o700) == 0 else {
            detail = "Graft could not prepare closed-lid mode."
            return
        }
        let arguments: [String]
        do {
            arguments = try ClosedLidPowerScripts.installArguments(
                token: request.token,
                owner: getpid(),
                deadline: deadlineSeconds
            )
        } catch {
            _ = rmdir(request.marker)
            detail = "Graft could not prepare closed-lid mode."
            return
        }
        session = request
        isStarting = true
        detail = "Waiting for administrator approval…"
        let token = request.token
        let script = ClosedLidPowerScripts.authorization
        Task { [weak self] in
            let result = await Task.detached {
                Self.authorize(script: script, arguments: arguments)
            }.value
            self?.authorizationFinished(for: token, error: result)
        }
    }

    func stop() {
        sleepAfterExpiry?.cancel()
        sleepAfterExpiry = nil
        release(detail: "Off")
    }

    private func release(detail stopDetail: String) {
        guard var session, !session.stopRequested else { return }
        session.stopRequested = true
        session.stopDetail = stopDetail
        self.session = session

        // Removing this empty directory can only shorten the authorized lease.
        // The root worker verifies its identity and Graft's process separately.
        _ = rmdir(session.marker)
        isRestoring = true
        detail = "Ending closed-lid mode…"
        refresh()
    }

    private func authorizationFinished(for token: UUID, error: String?) {
        guard var session, session.token == token else { return }
        if let error {
            finish(session.stopRequested ? session.stopDetail : error)
            return
        }
        session.activationTimeout = .now.advanced(by: .seconds(25))
        self.session = session
        if !session.stopRequested { detail = "Starting closed-lid mode…" }
        refresh()
    }

    private func refresh() {
        guard isSupported else { return }
        let journalExists = FileManager.default.fileExists(atPath: ClosedLidPowerScripts.journalPath)
        let status = Self.watchdogStatus()
        guard var session else {
            if journalExists {
                isRestoring = true
                detail = status?.phase == "restore-failed"
                    ? "Normal sleep could not be restored. Graft is retrying."
                    : "Restoring normal sleep from a previous session…"
            } else if isRestoring {
                isRestoring = false
                detail = "Off"
            }
            return
        }

        if !session.stopRequested && ProcessInfo.processInfo.thermalState == .critical {
            release(detail: "Closed-lid mode ended because the MacBook got too hot.")
            return
        }

        let phase = status?.token == session.token.uuidString ? status?.phase : nil
        switch phase {
        case "active":
            if !session.reachedActive {
                session.reachedActive = true
                self.session = session
            }
            isStarting = false
            isActive = true
            if !session.stopRequested { detail = "Active until the timer ends" }
        case "restoring", "restore-failed":
            isStarting = false
            isActive = false
            isRestoring = true
            detail = phase == "restore-failed"
                ? "Normal sleep could not be restored. Graft is retrying."
                : "Restoring normal sleep…"
        case "expired":
            finish(session.stopRequested ? session.stopDetail : "Off")
            if session.reachedActive && !session.stopRequested && !journalExists {
                requestSleepAfterExpiry(of: session.token)
            }
        case "stopped", "cancelled":
            finish(session.stopRequested ? session.stopDetail : "Off")
        case "power":
            finish("Graft could not verify the MacBook’s power status.")
        case "battery":
            finish("Closed-lid mode needs more than 10% battery.")
        case "settings":
            finish("Graft could not verify the Mac’s sleep settings.")
        case "setup":
            finish("Graft could not start closed-lid mode.")
        default:
            if let timeout = session.activationTimeout, .now >= timeout {
                finish(session.stopRequested ? session.stopDetail : "Graft could not start its sleep recovery service.")
            }
        }
    }

    private func finish(_ message: String) {
        if let session { _ = rmdir(session.marker) }
        session = nil
        isActive = false
        isStarting = false
        isRestoring = false
        detail = message
    }

    private func requestSleepAfterExpiry(of token: UUID) {
        guard Self.shouldSleepAfterExpiry(of: token) else { return }
        sleepAfterExpiry = Task { [weak self] in
            // Allow macOS a moment to respond naturally to the restored policy.
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self else { return }
            sleepAfterExpiry = nil
            guard session == nil, Self.shouldSleepAfterExpiry(of: token) else { return }
            let connection = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
            guard connection != IO_OBJECT_NULL else {
                detail = "Normal sleep was restored. macOS could not sleep automatically."
                return
            }
            defer { IOServiceClose(connection) }
            if IOPMSleepSystem(connection) != kIOReturnSuccess {
                detail = "Normal sleep was restored. macOS could not sleep automatically."
            }
        }
    }

    private static func shouldSleepAfterExpiry(of token: UUID) -> Bool {
        guard let status = watchdogStatus(), status.token == token.uuidString, status.phase == "expired" else {
            return false
        }
        var journal = stat()
        guard lstat(ClosedLidPowerScripts.journalPath, &journal) == -1, errno == ENOENT else { return false }

        var consoleUID: uid_t = 0
        guard SCDynamicStoreCopyConsoleUser(nil, &consoleUID, nil) != nil,
              consoleUID != 0, consoleUID == getuid(), !hasOnlineExternalDisplay() else { return false }

        let flags = powerFlags(["AppleClamshellState", "AppleClamshellCausesSleep", "SleepDisabled"])
        return flags == [true, true, false]
    }

    private static func hasOnlineExternalDisplay() -> Bool {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success else { return true }
        if displayCount == 0 { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetOnlineDisplayList(displayCount, &displays, &displayCount) == .success else { return true }
        return displays.prefix(Int(displayCount)).contains { display in
            CGDisplayIsBuiltin(display) == 0 && CGDisplayVendorNumber(display) != UInt32(kDisplayVendorIDUnknown)
        }
    }

    private static func watchdogStatus() -> (token: String, phase: String)? {
        guard let contents = try? String(contentsOfFile: ClosedLidPowerScripts.statusPath, encoding: .utf8) else {
            return nil
        }
        let parts = contents.split(separator: "\n", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.last?.isEmpty == true else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private static func deviceSupportsClosedLid() -> Bool {
        #if arch(arm64)
        guard #available(macOS 26.0, *) else { return false }
        return powerFlags(["AppleClamshellState", "SleepDisabled"]) != nil
        #else
        return false
        #endif
    }

    private static func powerFlags(_ keys: [String]) -> [Bool]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var flags: [Bool] = []
        for key in keys {
            guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue(), CFGetTypeID(value) == CFBooleanGetTypeID(),
                  let flag = value as? Bool else { return nil }
            flags.append(flag)
        }
        return flags
    }

    private nonisolated static func authorize(script: String, arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", script, "--"] + arguments
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            return "Graft could not request administrator approval."
        }
        let message = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        if process.terminationStatus == 0 { return nil }
        if message.contains("(-128)") || message.contains("GRAFT_cancelled") { return "Closed-lid mode was cancelled." }
        if message.contains("GRAFT_power") { return "Graft could not verify the MacBook’s power status." }
        if message.contains("GRAFT_battery") { return "Charge your MacBook above 10% first." }
        if message.contains("GRAFT_expired") { return "Start a new timed session first." }
        if message.contains("GRAFT_settings") { return "Close other apps that disable sleep, then try again." }
        if message.contains("GRAFT_busy") || message.contains("GRAFT_restoring") {
            return "Another closed-lid session is still running or restoring sleep."
        }
        return "Graft could not start closed-lid mode. Administrator approval is required."
    }
}
