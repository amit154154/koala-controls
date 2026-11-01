import AppKit
import ApplicationServices

enum MobileSpacePlan {
    /// Sidecar is a media display, not a desk monitor. A closed-lid desk is not mobile.
    static func displayID(in displays: [MediaDisplay]) -> CGDirectDisplayID? {
        guard !displays.contains(where: { !$0.builtIn && !$0.isIPad }) else { return nil }
        return displays.first(where: \.builtIn)?.id
    }

    static func isSplit(left: CGRect, right: CGRect, screen: CGRect) -> Bool {
        let tolerance: CGFloat = 32
        return abs(left.minX - screen.minX) < tolerance
            && abs(right.maxX - screen.maxX) < tolerance
            && abs(left.maxX - right.minX) < tolerance
            // Chromium reports its toolbar/content inset in AXPosition in Split View.
            // Bottom edges align even when the two reported top edges differ.
            && abs(left.maxY - right.maxY) < tolerance
            && left.minY >= screen.minY - tolerance && right.minY >= screen.minY - tolerance
            && left.maxY <= screen.maxY + tolerance && right.maxY <= screen.maxY + tolerance
            && left.height > screen.height * 0.85 && right.height > screen.height * 0.85
            && left.width > screen.width * 0.2 && right.width > screen.width * 0.2
    }
}

/// Native macOS Spaces, using the same Full Screen Tile command as the green button.
/// No window-manager driver or private Spaces API is needed.
@MainActor enum MobileSpaces {
    typealias AppWindow = (NSRunningApplication, AXUIElement)

    /// Search every window, including windows in other Spaces. The focused Chrome
    /// window may be a normal browser window even when Build & browse already exists.
    static func reuseExistingSpace(for applications: [NSRunningApplication], on screen: NSScreen) async throws -> Bool {
        let bounds = WindowSnapper.shared.flip(screen.frame)
        let candidates = applications.map { app -> [AppWindow] in
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 1)
            return (value(element, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
                fullScreen($0) && value($0, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole
            }.map { (app, $0) }
        }
        if candidates.count == 1,
           let existing = candidates[0].first(where: { pair in
               guard let frame = WindowSnapper.shared.frame(of: pair.1) else { return false }
               return frame.intersection(bounds).width > bounds.width * 0.9
                   && frame.height > bounds.height * 0.85
           }) {
            try await switchToExisting([existing])
            return true
        }
        if candidates.count == 2 {
            for left in candidates[0] {
                for right in candidates[1] where splitIsReady([left, right], bounds: bounds) {
                    try await switchToExisting([left, right])
                    return true
                }
            }
        }
        return false
    }

    private static func switchToExisting(_ windows: [AppWindow]) async throws {
        for pair in windows { pair.0.unhide() }
        let first = windows[0]
        activate(first)
        try await pause(0.7)
        if !bothAreVisible(windows), let url = first.0.bundleURL {
            // Workspace's normal open/activate handoff also works from a menu-bar
            // utility while another application owns a native Full Screen Space.
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            try await pause(0.4)
            activate(first)
        }
        // Switching Spaces is animated. Never dismantle a valid pair merely because
        // its windows are not on-screen during the first frames of that transition.
        do {
            try await waitUntil("The workspace already exists, but macOS did not switch to it. Swipe to its Space and try again.") {
                bothAreVisible(windows)
            }
        } catch {
            probe("Existing Space activation incomplete", windows: windows)
            throw error
        }
        probe("Reused existing Space", windows: windows)
    }

    static func arrange(_ windows: [AppWindow], names: [String], on screen: NSScreen,
                        actions: GroveActions) async throws {
        guard let first = windows.first else { return }
        probe("Preparing", windows: windows)
        let bounds = WindowSnapper.shared.flip(screen.frame)
        if windows.count == 1, fullScreen(first.1),
           let frame = WindowSnapper.shared.frame(of: first.1), frame.intersection(bounds).width > bounds.width * 0.9 {
            try await switchToExisting(windows)
            return
        }
        if windows.count == 2, splitIsReady(windows, bounds: bounds) {
            try await switchToExisting(windows)
            return
        }

        // Capture the target before activation. In mobile mode this is always the MacBook.
        for (index, pair) in windows.enumerated() {
            activate(pair)
            try await pause(0.4)
            do { try await actions.place(pair.1, app: pair.0, name: names[index], frame: screen.visibleFrame) }
            catch {
                // Zed updates its AX size asynchronously when crossing displays.
                try await pause(0.6)
                try await actions.place(pair.1, app: pair.0, name: names[index], frame: screen.visibleFrame)
            }
        }
        if windows.count == 1 {
            activate(first)
            try await pause(0.25)
            guard AXUIElementSetAttributeValue(first.1, "AXFullScreen" as CFString, kCFBooleanTrue) == .success else {
                throw GroveError.message("\(names[0]) could not enter macOS Full Screen.")
            }
            try await waitUntil("\(names[0]) did not finish entering Full Screen.") {
                fullScreen(first.1) && (WindowSnapper.shared.frame(of: first.1)?.width ?? 0) > bounds.width * 0.9
            }
            return
        }

        guard windows.count == 2 else { return }
        let pointer = NSEvent.mouseLocation
        var hidden: [NSRunningApplication] = []
        var minimized: [AXUIElement] = []
        var chooserStarted = false
        var completed = false
        defer {
            probe(completed ? "Split View complete" : "Split View incomplete", windows: windows)
            // Only undo temporary changes made here; leave previously hidden/minimized apps alone.
            for window in minimized { _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
            for app in hidden where !app.isTerminated { app.unhide() }
            if chooserStarted && !completed {
                _ = AXUIElementSetAttributeValue(first.1, "AXFullScreen" as CFString, kCFBooleanFalse)
            }
            // Menu navigation may have moved the pointer; restore its original location.
            CGWarpMouseCursorPosition(cgPoint(pointer))
        }

        // The native Split View picker does not consistently expose its thumbnails to AX.
        // Make the requested partner its only candidate, then select the centre of that half.
        // Existing documents are kept open, and all temporary visibility changes are restored.
        for pair in windows {
            let appElement = AXUIElementCreateApplication(pair.0.processIdentifier)
            for window in value(appElement, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                guard !CFEqual(window, pair.1), value(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
                      value(window, kAXMinimizedAttribute) as? Bool != true, !fullScreen(window) else { continue }
                guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success else {
                    throw GroveError.message("An extra \(pair.0.localizedName ?? "app") window could not be tucked away for Split View.")
                }
                minimized.append(window)
            }
        }
        let pids = Set(windows.map { $0.0.processIdentifier })
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isHidden && !pids.contains(app.processIdentifier) {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            let ordinary = (value(element, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
                value($0, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole
                    && value($0, kAXMinimizedAttribute) as? Bool != true && !fullScreen($0)
            }
            // Finder's desktop and apps without ordinary windows are not picker candidates.
            if ordinary.isEmpty { continue }
            if app.hide() { hidden.append(app) }
            else {
                for window in ordinary {
                    guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success else {
                        throw GroveError.message("\(app.localizedName ?? "An app") has a window that cannot be tucked away for Split View.")
                    }
                    minimized.append(window)
                }
            }
        }
        activate(windows[1])
        try await pause(0.35)
        activate(first)
        try await pause(0.35)
        guard bothAreVisible(windows) else {
            throw GroveError.message("Bring both apps onto the same desktop once, then press this shortcut to create their Split View Space.")
        }
        // Re-check hot-plug state before entering a Space.
        guard MobileSpacePlan.displayID(in: MediaScreens.displays()) == MediaScreens.id(screen) else {
            throw GroveError.message("Your displays changed. Press the shortcut again to use the new layout.")
        }
        chooserStarted = true
        probe("Opening Full Screen Tile menu", windows: windows)
        try await tileLeft(app: first.0, window: first.1)
        probe("Waiting for partner chooser", windows: windows)
        try await waitUntil("macOS did not open the Split View chooser. Check that Displays have separate Spaces is enabled.") {
            guard let frame = WindowSnapper.shared.frame(of: first.1) else { return false }
            return fullScreen(first.1) && abs(frame.minX - bounds.minX) < 32
                && frame.width < bounds.width * 0.75 && frame.height > bounds.height * 0.85
        }
        try await pause(0.65)
        // Abort rather than click into an unrelated app if the user changes focus mid-transition.
        let front = NSWorkspace.shared.frontmostApplication
        // macOS may focus the sole partner while presenting its chooser thumbnail.
        guard front.map({ pids.contains($0.processIdentifier) }) == true || ["com.apple.dock", "com.apple.WindowManager"].contains(front?.bundleIdentifier ?? "") else {
            throw GroveError.message("Split View was interrupted. Press the shortcut again.")
        }
        guard windows[1].0.isHidden == false, value(windows[1].1, kAXMinimizedAttribute) as? Bool != true else {
            throw GroveError.message("The Split View partner is no longer available. Press the shortcut again.")
        }
        // The user (or macOS) may already have completed the pairing during the transition.
        // In that case another click would land inside the app's actual content.
        if splitIsReady(windows, bounds: bounds) {
            completed = true
            activate(first)
            return
        }
        guard fullScreen(first.1), !fullScreen(windows[1].1),
              let frame = WindowSnapper.shared.frame(of: first.1),
              abs(frame.minX - bounds.minX) < 32, frame.width < bounds.width * 0.75 else {
            throw GroveError.message("The Split View chooser was closed. Press the shortcut again.")
        }
        let point = CGPoint(x: bounds.minX + bounds.width * 0.75, y: bounds.midY)
        probe("Selecting partner", windows: windows)
        click(point)
        try await waitUntil("macOS could not pair \(names[0]) with \(names[1]). Try the shortcut again after closing any dialog in those apps.") {
            splitIsReady(windows, bounds: bounds)
        }
        completed = true
        activate(first)
    }

    private static func activate(_ pair: AppWindow) {
        pair.0.unhide()
        // Select the exact document window before activating its application.
        _ = AXUIElementSetAttributeValue(pair.1, kAXMainAttribute as CFString, kCFBooleanTrue)
        if #available(macOS 14, *), NSApp.isActive { NSApp.yieldActivation(to: pair.0) }
        pair.0.activate(options: [.activateIgnoringOtherApps])
        let application = AXUIElementCreateApplication(pair.0.processIdentifier)
        _ = AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementPerformAction(pair.1, kAXRaiseAction as CFString)
    }

    private static func probe(_ stage: String, windows: [AppWindow]) {
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let data: [String: Any] = ["stage": stage, "date": ISO8601DateFormatter().string(from: Date()),
            "frontmost": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "",
            "onScreenFrames": windows.map { pair in ["app": pair.0.bundleIdentifier ?? "",
                "frames": onScreen.compactMap { info -> String? in
                    guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pair.0.processIdentifier,
                          let raw = info[kCGWindowBounds as String] as? NSDictionary,
                          let frame = CGRect(dictionaryRepresentation: raw) else { return nil }
                    return NSStringFromRect(frame)
                }] as [String: Any] },
            "windows": windows.map { pair in ["app": pair.0.bundleIdentifier ?? "",
                "fullScreen": fullScreen(pair.1), "hidden": pair.0.isHidden,
                "frame": WindowSnapper.shared.frame(of: pair.1).map { NSStringFromRect($0) } ?? "unavailable"] as [String: Any] }]
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Mini Keyboard/mobile-space-status.json")
        if let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) { try? json.write(to: path, options: .atomic) }
    }

    private static func fullScreen(_ window: AXUIElement) -> Bool { value(window, "AXFullScreen") as? Bool == true }
    private static func splitIsReady(_ windows: [AppWindow], bounds: CGRect) -> Bool {
        guard windows.count == 2, windows.allSatisfy({ fullScreen($0.1) }),
              let left = WindowSnapper.shared.frame(of: windows[0].1),
              let right = WindowSnapper.shared.frame(of: windows[1].1) else { return false }
        return MobileSpacePlan.isSplit(left: left, right: right, screen: bounds)
    }
    private static func bothAreVisible(_ windows: [AppWindow]) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.allSatisfy { pair in
            guard let target = WindowSnapper.shared.frame(of: pair.1) else { return false }
            return list.contains { info in
                guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pair.0.processIdentifier,
                      let raw = info[kCGWindowBounds as String] as? NSDictionary,
                      let frame = CGRect(dictionaryRepresentation: raw) else { return false }
                return abs(frame.minX - target.minX) < 8 && abs(frame.width - target.width) < 8
            }
        }
    }

    private static func tileLeft(app: NSRunningApplication, window: AXUIElement) async throws {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        guard let bar = value(application, kAXMenuBarAttribute) else { throw GroveError.message("The app’s Window menu is unavailable.") }
        let menuBar = bar as! AXUIElement
        guard let windowItem = children(menuBar).first(where: { title($0) == "Window" }) else {
            throw GroveError.message("The app’s Window menu is unavailable. Native Split View currently needs English macOS menus.")
        }
        defer { _ = AXUIElementPerformAction(windowItem, kAXCancelAction as CFString) }
        _ = AXUIElementPerformAction(windowItem, kAXPressAction as CFString)
        try await pause(0.15)
        // The system regenerates these menu objects. Always resolve the final item afresh.
        for _ in 0..<4 {
            if let direct = find(windowItem, titles: ["Tile Window to Left of Screen"], depth: 2),
               press(direct) { return }
            if let parent = find(windowItem, titles: ["Full Screen Tile"], depth: 2) {
                var selected: DarwinBoolean = false
                if AXUIElementIsAttributeSettable(parent, kAXSelectedAttribute as CFString, &selected) == .success && selected.boolValue {
                    _ = AXUIElementSetAttributeValue(parent, kAXSelectedAttribute as CFString, kCFBooleanTrue)
                } else if let frame = WindowSnapper.shared.frame(of: parent), frame.width > 0 {
                    // Hover opens the submenu without invoking its placeholder item.
                    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                            mouseCursorPosition: CGPoint(x: frame.midX, y: frame.midY), mouseButton: .left)?.post(tap: .cghidEventTap)
                }
                try await pause(0.25)
                if let fresh = find(windowItem, titles: ["Full Screen Tile"], depth: 2),
                   let left = find(fresh, titles: ["Left of Screen"], depth: 2), press(left) { return }
            }
            try await pause(0.15)
        }
        throw GroveError.message("The macOS Full Screen Tile command did not respond. Close the app’s menu or dialog and try again.")
    }

    private static func press(_ element: AXUIElement) -> Bool {
        value(element, kAXEnabledAttribute) as? Bool != false && AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
    private static func find(_ root: AXUIElement, titles: Set<String>, depth: Int) -> AXUIElement? {
        guard depth >= 0 else { return nil }
        for child in children(root) {
            if titles.contains(title(child)) { return child }
            if depth > 0, let match = find(child, titles: titles, depth: depth - 1) { return match }
        }
        return nil
    }
    private static func children(_ element: AXUIElement) -> [AXUIElement] { value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    private static func title(_ element: AXUIElement) -> String { value(element, kAXTitleAttribute) as? String ?? "" }
    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
    private static func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private static func waitUntil(_ message: String, condition: () -> Bool) async throws {
        for _ in 0..<60 {
            if condition() { return }
            try await pause(0.1)
        }
        throw GroveError.message(message)
    }
    private static func cgPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
    }
    private static func click(_ point: CGPoint) {
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }
}
