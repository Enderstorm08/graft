import AppKit
import ApplicationServices

final class DockAIUsageOverlay {
    private struct Tile {
        let element: AXUIElement
        let provider: DockAIProvider
    }

    private var dockPID: pid_t?
    private var dockElement: AXUIElement?
    private var dockList: AXUIElement?
    private var tiles: [Tile] = []
    private var checkedTilesAt = -Double.infinity
    private var panels: [AXUIElement: NSPanel] = [:]

    func hide() {
        for panel in panels.values { panel.orderOut(nil) }
    }

    func stop() {
        hide()
        panels.removeAll()
        tiles.removeAll()
        dockElement = nil
        dockList = nil
        dockPID = nil
        checkedTilesAt = -Double.infinity
    }

    // Use the Dock's live geometry so position, display, magnification and autohide stay with the system.
    func update(_ windows: [DockAIProvider: DockAIUsageWindow], now: Date) -> Duration {
        guard !windows.isEmpty,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let mainTop = NSScreen.screens.first?.frame.maxY,
              isDockVisible(pid: dock.processIdentifier)
        else {
            hide()
            return .milliseconds(250)
        }

        let uptime = ProcessInfo.processInfo.systemUptime
        if dockPID != dock.processIdentifier {
            stop()
            dockPID = dock.processIdentifier
            let element = AXUIElementCreateApplication(dock.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.04)
            dockElement = element
        }
        if uptime - checkedTilesAt >= 2, let dockElement {
            checkedTilesAt = uptime
            let children = attribute(dockElement, kAXChildrenAttribute) as? [AXUIElement] ?? []
            dockList = children.first { attribute($0, kAXRoleAttribute) as? String == kAXListRole }
            tiles = dockList.map(findTiles) ?? []
            let currentTiles = Set(tiles.map(\.element))
            for element in Array(panels.keys) where !currentTiles.contains(element) {
                panels.removeValue(forKey: element)?.orderOut(nil)
            }
        }

        guard let dockList, let plate = elementFrame(dockList) else {
            hide()
            return .milliseconds(250)
        }
        let mouse = NSEvent.mouseLocation
        let closeToDock = plate.insetBy(dx: -90, dy: -90).contains(CGPoint(x: mouse.x, y: mainTop - mouse.y))
        for tile in tiles {
            guard let window = windows[tile.provider],
                  let frame = elementFrame(tile.element), frame.intersects(plate) else {
                panels[tile.element]?.orderOut(nil)
                continue
            }
            let appKitFrame = CGRect(x: frame.minX, y: mainTop - frame.maxY, width: frame.width, height: frame.height)
            guard NSScreen.screens.contains(where: { $0.frame.contains(appKitFrame) }) else {
                panels[tile.element]?.orderOut(nil)
                continue
            }
            let panel = panels[tile.element] ?? makePanel()
            panels[tile.element] = panel
            if panel.frame != appKitFrame { panel.setFrame(appKitFrame, display: false) }

            let meter = panel.contentView as? DockAIUsageMeterView
            let countdown = appKitFrame.contains(mouse) ? window.countdown(at: now) : nil
            meter?.update(provider: tile.provider, window: window, countdown: countdown)
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        return closeToDock ? .milliseconds(40) : .milliseconds(250)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        panel.contentView = DockAIUsageMeterView()
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        return panel
    }

    private func isDockVisible(pid: pid_t) -> Bool {
        let level = Int(CGWindowLevelForKey(.dockWindow))
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  window[kCGWindowLayer as String] as? Int == level,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  min(frame.width, frame.height) >= 16
            else { return false }
            return true
        }
    }

    private func findTiles(in list: AXUIElement) -> [Tile] {
        let items = attribute(list, kAXChildrenAttribute) as? [AXUIElement] ?? []
        return items.compactMap { item in
            guard let title = attribute(item, kAXTitleAttribute) as? String,
                  let provider = DockAIProvider.allCases.first(where: { $0.dockTitles.contains(title) }),
                  attribute(item, kAXSubroleAttribute) as? String == kAXApplicationDockItemSubrole
            else { return nil }
            let url = attribute(item, kAXURLAttribute) as? URL
            let bundleID = url.flatMap { $0.isFileURL ? Bundle(url: $0)?.bundleIdentifier : nil }
            if let bundleID, !provider.bundleIdentifiers.contains(bundleID) { return nil }
            return Tile(element: item, provider: provider)
        }
    }

    private func elementFrame(_ item: AXUIElement) -> CGRect? {
        if let rawFrame = attribute(item, "AXFrame"), CFGetTypeID(rawFrame) == AXValueGetTypeID() {
            var frame = CGRect.zero
            if AXValueGetValue(rawFrame as! AXValue, .cgRect, &frame), min(frame.width, frame.height) >= 16 {
                return frame
            }
        }
        guard let position = attribute(item, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(item, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              min(dimensions.width, dimensions.height) >= 16 else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    private func attribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
}
