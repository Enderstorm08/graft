import SwiftUI

struct DockAIUsageSettingsRow: View {
    @Environment(GraftStore.self) private var store
    @State private var expanded = false

    private var service: DockAIUsageService { store.dockAIUsage }
    private var isEnabled: Bool { store.state.macSettings.dockAIUsageEnabled }
    private var hasSelectedProvider: Bool {
        DockAIProvider.allCases.contains { store.state.macSettings[keyPath: $0.setting] }
    }

    var body: some View {
        VStack(spacing: 0) {
            GraftRow {
                GraftRowLabel(
                    title: "Dock AI Usage",
                    detail: "Show usage meters and hover for reset times",
                    symbol: "dock.rectangle",
                    tint: .cyan
                )
                if isEnabled && hasSelectedProvider && !service.hasAccessibility {
                    Text("Needs Accessibility").font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    GraftDisclosureChevron(isExpanded: expanded)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dock AI Usage options")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                Toggle("Dock AI Usage", isOn: Binding(
                    get: { isEnabled },
                    set: { enabled in
                        store.macToggle(\.dockAIUsageEnabled).wrappedValue = enabled
                        if enabled && hasSelectedProvider && !service.hasAccessibility { expanded = true }
                    }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            if expanded {
                GraftSettingsSubGroup(
                    "Dock meters",
                    footer: "Pin or open the apps in your Dock. Graft shows the most-used active limit for ChatGPT / Codex and Claude, and included usage for Cursor."
                ) {
                    if hasSelectedProvider && !service.hasAccessibility {
                        GraftRow {
                            Text("Allow Accessibility so Graft can locate the Dock icons.")
                                .font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("Open Accessibility") { service.requestAccessibility() }
                                .controlSize(.small)
                        }
                    }
                    ForEach(DockAIProvider.allCases) { provider in
                        GraftToggleRow(
                            title: provider.title,
                            detail: service.detail(for: provider),
                            isOn: store.macToggle(provider.setting)
                        )
                    }
                    GraftRow {
                        Link("Set up Claude and Cursor in CodexBar", destination: URL(string: "https://github.com/steipete/CodexBar")!)
                            .font(.callout)
                        Spacer()
                        Button("Refresh Usage") { service.refreshNow() }
                            .controlSize(.small)
                            .disabled(!hasSelectedProvider || service.isRefreshing)
                    }
                }
                .disabled(!isEnabled)
                .padding(.leading, GraftMetrics.labelInset)
                .padding(.trailing, GraftMetrics.rowHorizontalPadding)
                .padding(.bottom, GraftMetrics.rowVerticalPadding)
            }
        }
    }
}
