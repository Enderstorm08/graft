import Foundation
import GraftCore
import Testing
@testable import GraftMac

struct DockAIUsageTests {
    @Test func olderSettingsKeepDockMetersOffUntilEnabled() throws {
        let settings = try JSONDecoder().decode(MacSettings.self, from: Data("{}".utf8))
        #expect(!settings.dockAIUsageEnabled)
        #expect(DockAIProvider.allCases.allSatisfy { settings[keyPath: $0.setting] })
    }

    @Test func countdownComesFromTheSameActiveWindowAsTheMeter() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expired = DockAIUsageWindow(percentUsed: 96, resetsAt: now)
        let session = DockAIUsageWindow(percentUsed: 28, resetsAt: now.addingTimeInterval(50))
        let weekly = DockAIUsageWindow(percentUsed: 59, resetsAt: now.addingTimeInterval(28 * 3_600))
        let selected = try #require(DockAIUsageWindow.mostUsed([expired, session, weekly], at: now))
        #expect(selected.percentageLabel == "59%")
        #expect(selected.countdown(at: now) == "1d 4h")
        #expect(session.countdown(at: now) == "<1m")
        #expect(expired.countdown(at: now) == nil)
        #expect(DockAIUsageWindow.mostUsed([expired], at: now) == nil)
    }

    @Test func codexDecodesAccountWindowUsage() throws {
        let response = Data("""
            {"rate_limit":{"primary_window":{"used_percent":37,"reset_at":1800000300},"secondary_window":null}}
            """.utf8)
        let usage = try JSONDecoder().decode(CodexAccountUsage.self, from: response)
        #expect(usage.rateLimit?.primary?.usedPercent == 37)
        #expect(usage.rateLimit?.primary?.resetAt == 1_800_000_300)
        #expect(usage.rateLimit?.secondary == nil)
    }

    @Test func cursorUsesTheIncludedQuotaFromCodexBar() throws {
        let response = Data("""
            [{"provider":"cursor","usage":{
                "primary":{"usedPercent":57,"resetsAt":"2027-01-01T09:00:00Z"},
                "secondary":{"usedPercent":91,"resetsAt":"2027-01-01T09:00:00.500Z"}
            }}]
            """.utf8)
        let windows = try DockAIUsageSource.decodeCodexBar(response, provider: .cursor)
        #expect(windows.map(\.percentUsed) == [57])
    }

    @Test func claudeOmitsThePlaceholderAndKeepsTheWeeklyWindow() throws {
        let response = Data("""
            {"provider":"claude","usage":{
                "primary":{"usedPercent":0},
                "secondary":{"usedPercent":42,"resetsAt":"2027-01-01T09:00:00.500Z"}
            }}
            """.utf8)
        let windows = try DockAIUsageSource.decodeCodexBar(response, provider: .claude)
        let window = try #require(windows.first)
        #expect(windows.count == 1)
        #expect(window.percentUsed == 42)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_798_794_000.5))
    }

    @Test func readsTheSelectedCodexBarProviderFromTheLocalCLI() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codexbar")
        try """
            #!/bin/sh
            [ "$*" = "usage --provider cursor --format json --json-only" ] || exit 1
            printf '%s' '[{"provider":"cursor","usage":{"primary":{"usedPercent":0,"resetsAt":"2027-01-01T09:00:00Z"}}}]'
            """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let windows = try await DockAIUsageSource.read(.cursor, codexBar: executable)
        #expect(windows.map(\.percentageLabel) == ["0%"])
    }
}
