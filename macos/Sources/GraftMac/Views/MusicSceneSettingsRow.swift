import SwiftUI

struct MusicSceneSettingsRow: View {
    @Environment(GraftStore.self) private var store
    @State private var expanded = false

    var body: some View {
        @Bindable var scene = store.musicScene
        @Bindable var session = scene.session
        VStack(spacing: 0) {
            GraftRow {
                GraftRowLabel(title: "Music Scene", detail: "Album-colored light, artwork and timed lyrics",
                              symbol: "music.note.list", tint: .pink)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: { GraftDisclosureChevron(isExpanded: expanded) }
                .buttonStyle(.plain)
                .accessibilityLabel("Music Scene options")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                Button("Open Player") { scene.openPlayer() }.controlSize(.small)
            }
            if expanded {
                GraftSettingsSubGroup("Listening room",
                    footer: "Spotify and Apple Music use macOS Automation. When an Apple Music stream has no cover, Graft can look up the song, artist and release with Apple. Expanding a low-resolution sleeve can look up a sharper cover. Opening lyrics looks up the song on LRCLIB. Imported LRC and TXT files stay on this Mac.") {
                    GraftPickerRow(title: "Follow player", selection: $session.preferredSource) {
                        Text("Automatic").tag(MusicSceneSource?.none)
                        ForEach(MusicSceneSource.allCases) { source in Text(source.title).tag(Optional(source)) }
                    }
                    GraftRow {
                        GraftRowLabel(title: "Artwork window", detail: "Opens on a second display when connected")
                        Button("Open Artwork") { scene.openArtwork() }.controlSize(.small)
                    }
                    GraftToggleRow(title: "Desktop edge light", detail: "Keep light around your display while using other apps",
                                   isOn: $scene.desktopLight)
                    GraftPickerRow(title: "Display", selection: $scene.displayID) {
                        Text("Main display").tag("")
                        ForEach(scene.screenOptions) { Text($0.title).tag($0.id) }
                        if !scene.displayID.isEmpty && !scene.screenOptions.contains(where: { $0.id == scene.displayID }) {
                            Text("Disconnected display").tag(scene.displayID)
                        }
                    }
                    GraftPickerRow(title: "Light palette", selection: $session.paletteMode) {
                        ForEach(MusicScenePaletteMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    GraftRow {
                        GraftRowLabel(title: "Glow")
                        Slider(value: $session.lightIntensity, in: 0...1).frame(maxWidth: 120).accessibilityLabel("Edge glow")
                        Text(session.lightIntensity, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit()).frame(width: 34, alignment: .trailing)
                    }
                    GraftRow {
                        GraftRowLabel(title: "Edge width")
                        Slider(value: $session.lightWidth, in: 1...16, step: 1).frame(maxWidth: 120).accessibilityLabel("Edge width")
                        Text("\(Int(session.lightWidth)) pt").font(.caption.monospacedDigit()).frame(width: 34, alignment: .trailing)
                    }
                    GraftToggleRow(title: "Animate light", detail: "Move light clockwise around the edge",
                                   isOn: $session.animateLight)
                    GraftToggleRow(title: "Sync light to the beat", detail: session.beatStatus, isOn: $session.beatSync)
                    GraftToggleRow(title: "React to system audio",
                                   detail: session.meterStatus ?? "Pulse with sound playing on this Mac. Uses system audio access.",
                                   isOn: $session.reactive)
                    GraftRow {
                        GraftRowLabel(title: "Try the scene", detail: "A silent preview with original art and lyrics")
                        Button("Preview") { scene.openPlayer(preview: true) }.controlSize(.small)
                    }
                }
                .padding(.leading, GraftMetrics.labelInset)
                .padding(.trailing, GraftMetrics.rowHorizontalPadding)
                .padding(.bottom, GraftMetrics.rowVerticalPadding)
            }
        }
    }
}
