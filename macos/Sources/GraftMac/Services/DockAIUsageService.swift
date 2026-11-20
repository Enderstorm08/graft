import AppKit
import ApplicationServices
import GraftCore
import Observation

@Observable
final class DockAIUsageService {
    private(set) var hasAccessibility = false
    private(set) var isRefreshing = false
    private var providers: Set<DockAIProvider> = []
    private var readings: [DockAIProvider: [DockAIUsageWindow]] = [:]
    private var messages: [DockAIProvider: String] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var overlayTask: Task<Void, Never>?
    @ObservationIgnored private let overlay = DockAIUsageOverlay()

    func apply(_ settings: MacSettings) {
        let selected = settings.dockAIUsageEnabled
            ? Set(DockAIProvider.allCases.filter { settings[keyPath: $0.setting] })
            : []
        guard selected != providers else { return }
        stop()
        providers = selected
        guard !selected.isEmpty else { return }

        hasAccessibility = AXIsProcessTrusted()
        refreshNow()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(180))
                guard !Task.isCancelled else { return }
                self?.refreshNow()
            }
        }
        overlayTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.updateOverlay() else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        pollingTask?.cancel()
        pollingTask = nil
        overlayTask?.cancel()
        overlayTask = nil
        isRefreshing = false
        providers = []
        readings = [:]
        messages = [:]
        overlay.stop()
    }

    func requestAccessibility() {
        let prompt = "AXTrustedCheckOptionPrompt" as CFString
        hasAccessibility = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        if !hasAccessibility,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func detail(for provider: DockAIProvider) -> String {
        if let window = DockAIUsageWindow.mostUsed(readings[provider] ?? [], at: Date()) {
            let usage = "\(window.percentageLabel) used"
            guard let date = window.resetsAt else { return usage }
            return "\(usage) · Resets \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        guard providers.contains(provider) else { return provider == .codex ? "Codex sign-in" : "Via CodexBar" }
        if isRefreshing { return "Checking usage…" }
        return messages[provider] ?? "Waiting for current quota"
    }

    func refreshNow() {
        guard !providers.isEmpty, refreshTask == nil else { return }
        let requested = providers
        let helper = codexBarExecutable()
        isRefreshing = true
        refreshTask = Task { [weak self] in
            await withTaskGroup(of: (DockAIProvider, Result<[DockAIUsageWindow], Error>).self) { group in
                for provider in requested {
                    group.addTask {
                        do {
                            return (provider, .success(try await DockAIUsageSource.read(provider, codexBar: helper)))
                        } catch {
                            return (provider, .failure(error))
                        }
                    }
                }
                for await (provider, result) in group where !Task.isCancelled {
                    self?.receive(result, for: provider)
                }
            }
            guard !Task.isCancelled else { return }
            self?.isRefreshing = false
            self?.refreshTask = nil
        }
    }

    private func receive(_ result: Result<[DockAIUsageWindow], Error>, for provider: DockAIProvider) {
        switch result {
        case .success(let windows):
            readings[provider] = windows
            messages[provider] = "Waiting for current quota"
        case .failure(let error):
            readings[provider] = nil
            switch error {
            case CodexResetError.signInRequired: messages[provider] = "Sign in to Codex"
            case DockAIUsageSource.Failure.needsCodexBar: messages[provider] = "Install CodexBar to connect"
            case DockAIUsageSource.Failure.noQuota: messages[provider] = "No current quota available"
            default: messages[provider] = provider == .codex
                ? "Couldn’t read Codex usage"
                : "Check \(provider.title) usage in CodexBar"
            }
        }
    }

    private func updateOverlay() -> Duration {
        let trusted = AXIsProcessTrusted()
        if trusted != hasAccessibility { hasAccessibility = trusted }
        guard trusted else {
            overlay.hide()
            return .seconds(1)
        }
        let now = Date()
        let current = readings.compactMapValues { DockAIUsageWindow.mostUsed($0, at: now) }
        return overlay.update(current, now: now)
    }

    private func codexBarExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.steipete.codexbar")
        let locations = [
            app?.appendingPathComponent("Contents/Helpers/CodexBarCLI"),
            URL(fileURLWithPath: "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI"),
            home.appendingPathComponent("Applications/CodexBar.app/Contents/Helpers/CodexBarCLI"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codexbar"),
            URL(fileURLWithPath: "/usr/local/bin/codexbar"),
        ]
        return locations.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
