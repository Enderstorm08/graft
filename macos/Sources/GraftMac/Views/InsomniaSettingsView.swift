import GraftCore
import SwiftUI

struct InsomniaSettingsRow: View {
    @Environment(GraftStore.self) private var store
    @State private var expanded = false

    private var service: ClosedLidSessionService { store.closedLid }
    private var busy: Bool { service.isStarting || service.isRestoring }

    var body: some View {
        VStack(spacing: 0) {
            GraftRow {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: GraftMetrics.chipGap) {
                        GraftRowLabel(
                            title: "Insomnia",
                            detail: service.detail == "Off" ? "Keep Codex running with your MacBook lid closed" : service.detail,
                            symbol: "moon.zzz.fill",
                            tint: .indigo
                        )
                        Circle()
                            .fill(service.isActive ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        GraftDisclosureChevron(isExpanded: expanded)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Insomnia settings")
                .accessibilityValue("\(service.isActive ? "On" : "Off"), \(expanded ? "expanded" : "collapsed")")

                if busy {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel(service.detail)
                }
                Toggle("Insomnia", isOn: Binding(
                    get: { service.isActive || service.isStarting },
                    set: { enabled in
                        if enabled {
                            let minutes = min(240, max(1, store.state.macSettings.insomniaMinutes))
                            service.start(until: Date().addingTimeInterval(TimeInterval(minutes * 60)))
                        } else {
                            service.stop()
                        }
                    }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .disabled(service.isRestoring)
            }

            if expanded {
                GraftSettingsSubGroup(
                    "Session",
                    footer: "Requires administrator approval. Works on battery and ends at 10% charge. Use a ventilated surface."
                ) {
                    GraftRow {
                        GraftRowLabel(title: "Duration", detail: "1 to 240 minutes")
                        TextField("Minutes", value: Binding(
                            get: { store.state.macSettings.insomniaMinutes },
                            set: { minutes in
                                var settings = store.state.macSettings
                                settings.insomniaMinutes = min(240, max(1, minutes))
                                store.setMacSettings(settings)
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 68)
                        Text("min").foregroundStyle(.secondary)
                    }
                    .disabled(service.isActive || busy)

                    if let deadline = service.deadline, service.isActive {
                        GraftRow {
                            Text("Time left")
                            Spacer()
                            Text(deadline, style: .timer)
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, GraftMetrics.labelInset)
                .padding(.trailing, GraftMetrics.rowHorizontalPadding)
                .padding(.bottom, GraftMetrics.rowVerticalPadding)
            }
        }
    }
}
