import AppKit
import GraftCore
import SwiftUI

struct CaffeinateSettingsRow: View {
    @Environment(GraftStore.self) private var store
    @State private var expanded = false
    @State private var runningApps: [NSRunningApplication] = []

    private var settings: MacSettings { store.state.macSettings }
    private var isActive: Bool { store.keepAwake.isActive }
    private var needsAnApp: Bool {
        settings.keepAwakeMode == .untilAppQuits
            && !runningApps.contains { $0.bundleIdentifier == settings.keepAwakeAppBundleID }
    }

    var body: some View {
        VStack(spacing: 0) {
            GraftRow {
                Button {
                    refreshApps()
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: GraftMetrics.chipGap) {
                        GraftRowLabel(title: "Caffeinate", detail: summary, symbol: "cup.and.saucer.fill", tint: .green)
                        Circle().fill(isActive ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        GraftDisclosureChevron(isExpanded: expanded)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Caffeinate settings")
                .accessibilityValue("\(isActive ? "On" : "Off"), \(expanded ? "expanded" : "collapsed")")
                Toggle("Caffeinate", isOn: store.macToggle(\.keepAwake))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(!isActive && needsAnApp)
            }

            if expanded {
                VStack(alignment: .leading, spacing: GraftMetrics.chipGap) {
                    sessionSettings
                }
                .padding(.leading, GraftMetrics.labelInset)
                .padding(.trailing, GraftMetrics.rowHorizontalPadding)
                .padding(.bottom, GraftMetrics.rowVerticalPadding)
            }
        }
        .onAppear { refreshApps() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in refreshApps() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in refreshApps() }
    }

    private var summary: String {
        if isActive || store.keepAwake.detail != "Off" { return store.keepAwake.detail }
        return "Keep Codex and other local tasks running when your Mac is idle"
    }

    private var sessionSettings: some View {
        GraftSettingsSubGroup("Session", footer: "Keep Graft running for the session. Turn off Caffeinate to end it early.") {
            GraftPickerRow(title: "Keep awake for", selection: setting(\.keepAwakeMode)) {
                ForEach(KeepAwakeMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .disabled(isActive)

            if settings.keepAwakeMode == .custom {
                GraftRow {
                    GraftRowLabel(title: "Minutes", detail: "1 to 240 minutes")
                    TextField("Minutes", value: Binding(
                        get: { settings.keepAwakeCustomMinutes },
                        set: { minutes in
                            let range = MacSettings.keepAwakeCustomMinuteRange
                            update(\.keepAwakeCustomMinutes, min(range.upperBound, max(range.lowerBound, minutes)))
                        }
                    ), format: .number)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 68)
                }
                .disabled(isActive)
            }

            if settings.keepAwakeMode == .untilAppQuits { appPicker.disabled(isActive) }

            GraftToggleRow(
                title: "Keep the screen on",
                detail: "Useful for Codex Computer Use, which needs an unlocked desktop.",
                isOn: store.macToggle(\.keepAwakeDisplay)
            )

            if isActive, let deadline = settings.keepAwakeDeadline {
                GraftRow {
                    Text("Time left")
                    Spacer()
                    Text(deadline, style: .timer).monospacedDigit().foregroundStyle(.secondary)
                    if store.canExtendStayAwake {
                        Button("Add 30 min") { store.extendStayAwake(by: 30) }
                    }
                }
            }
        }
    }

    private var appPicker: some View {
        GraftPickerRow(
            title: "Application",
            detail: needsAnApp ? "Open the app first, then select it to start." : nil,
            selection: setting(\.keepAwakeAppBundleID)
        ) {
            let codexID = KeepAwakeService.codexBundleID
            let codex = runningApps.first { $0.bundleIdentifier == codexID }
            Text("Choose an app").tag("")
            Text(codex.map(KeepAwakeService.targetName(for:)) ?? "Codex (open first)").tag(codexID)
            ForEach(runningApps.filter { $0.bundleIdentifier != codexID }, id: \.processIdentifier) { app in
                Text(KeepAwakeService.targetName(for: app)).tag(app.bundleIdentifier ?? "")
            }
            let selected = settings.keepAwakeAppBundleID
            if !selected.isEmpty && selected != codexID && needsAnApp {
                Text("Previously selected app (closed)").tag(selected)
            }
        }
    }

    private func setting<Value>(_ path: WritableKeyPath<MacSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: path] }, set: { update(path, $0) })
    }

    private func update<Value>(_ path: WritableKeyPath<MacSettings, Value>, _ value: Value) {
        var newSettings = settings
        newSettings[keyPath: path] = value
        store.setMacSettings(newSettings)
    }

    private func refreshApps() {
        var seen = Set<String>()
        runningApps = NSWorkspace.shared.runningApplications.filter {
            guard $0.activationPolicy == .regular, !$0.isTerminated, $0.processIdentifier != getpid(),
                  let id = $0.bundleIdentifier else { return false }
            return seen.insert(id).inserted
        }.sorted { KeepAwakeService.targetName(for: $0).localizedStandardCompare(KeepAwakeService.targetName(for: $1)) == .orderedAscending }
    }
}
