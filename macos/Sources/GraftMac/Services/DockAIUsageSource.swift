import Foundation
import GraftCore

nonisolated enum DockAIProvider: String, CaseIterable, Identifiable, Sendable {
    case codex, claude, cursor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: "ChatGPT / Codex"
        case .claude: "Claude"
        case .cursor: "Cursor"
        }
    }

    var dockTitles: [String] {
        switch self {
        case .codex: ["ChatGPT", "Codex"]
        case .claude: ["Claude"]
        case .cursor: ["Cursor"]
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .codex: ["com.openai.chat", "com.openai.codex"]
        case .claude: ["com.anthropic.claudefordesktop"]
        case .cursor: ["com.todesktop.230313mzl4w4u92"]
        }
    }

    var setting: WritableKeyPath<MacSettings, Bool> {
        switch self {
        case .codex: \.dockAIUsageCodex
        case .claude: \.dockAIUsageClaude
        case .cursor: \.dockAIUsageCursor
        }
    }
}

nonisolated struct DockAIUsageWindow: Equatable, Sendable {
    let percentUsed: Double
    let resetsAt: Date?

    var percentageLabel: String {
        "\(Int(min(100, percentUsed).rounded()))%"
    }

    func countdown(at now: Date) -> String? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0, seconds / 60 < Double(Int.max) else { return nil }
        if seconds < 60 { return "<1m" }
        let minutes = Int(seconds / 60)
        if minutes >= 1440 { return "\(minutes / 1440)d \(minutes % 1440 / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    static func mostUsed(_ windows: [Self], at now: Date) -> Self? {
        windows.filter { window in
            window.percentUsed.isFinite && window.percentUsed >= 0
                && (window.resetsAt.map { $0 > now } ?? true)
        }.max { $0.percentUsed < $1.percentUsed }
    }
}

nonisolated enum DockAIUsageSource {
    enum Failure: Error {
        case needsCodexBar, noQuota, commandFailed
    }

    static func read(_ provider: DockAIProvider, codexBar: URL?) async throws -> [DockAIUsageWindow] {
        if provider == .codex {
            let usage = try await CodexAccountUsage.read()
            let windows = [usage.rateLimit?.primary, usage.rateLimit?.secondary].compactMap { $0 }
            return windows.map { window in
                DockAIUsageWindow(
                    percentUsed: window.usedPercent,
                    resetsAt: window.resetAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
                )
            }
        }
        guard let codexBar else { throw Failure.needsCodexBar }
        let data = try await codexBarUsage(codexBar, provider: provider)
        return try decodeCodexBar(data, provider: provider)
    }

    static func decodeCodexBar(_ data: Data, provider: DockAIProvider) throws -> [DockAIUsageWindow] {
        struct Payload: Decodable {
            struct Usage: Decodable {
                struct Window: Decodable {
                    let usedPercent: Double
                    let resetsAt: Date?
                }
                let primary: Window?
                let secondary: Window?
            }
            let provider: String
            let usage: Usage?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: raw) else { throw Failure.noQuota }
            return date
        }
        let payloads = try (try? decoder.decode([Payload].self, from: data))
            ?? [try decoder.decode(Payload.self, from: data)]
        guard let usage = payloads.first(where: { $0.provider == provider.rawValue })?.usage else {
            throw Failure.noQuota
        }
        // Cursor's primary limit is included usage. Other slots can represent spend or a different pool.
        return [usage.primary, provider == .claude ? usage.secondary : nil].compactMap { window in
            guard let window, let reset = window.resetsAt else { return nil }
            return .init(percentUsed: window.usedPercent, resetsAt: reset)
        }
    }

    private static func codexBarUsage(_ executable: URL, provider: DockAIProvider) async throws -> Data {
        try Task.checkCancellation()
        let files = FileManager.default
        let outputURL = files.temporaryDirectory.appendingPathComponent("graft-usage-\(UUID().uuidString)")
        guard files.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw Failure.commandFailed
        }
        let output: FileHandle
        do {
            output = try FileHandle(forUpdating: outputURL)
        } catch {
            try? files.removeItem(at: outputURL)
            throw error
        }
        defer { try? output.close() }
        // Keep the CLI output in an anonymous file so account metadata can't outlive the process.
        try files.removeItem(at: outputURL)

        let process = Process()
        process.executableURL = executable
        process.arguments = ["usage", "--provider", provider.rawValue, "--format", "json", "--json-only"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(25))
        while process.isRunning && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard !process.isRunning, process.terminationStatus == 0 else { throw Failure.commandFailed }
        try output.seek(toOffset: 0)
        guard let data = try output.read(upToCount: 256_001), data.count <= 256_000 else {
            throw Failure.commandFailed
        }
        return data
    }
}
