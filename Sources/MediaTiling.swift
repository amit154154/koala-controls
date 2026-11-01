import AppKit
import ApplicationServices

enum MediaTilingPlan {
    /// Reading order: top-left first; a short last row uses all available width.
    static func frames(in screen: CGRect, count: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        if count == 1 { return [screen] }
        let columns = count <= 4 ? 2 : 3
        let rows = Int(ceil(Double(count) / Double(columns)))
        return (0..<count).map { index in
            let row = index / columns, column = index % columns
            let inRow = min(columns, count - row * columns)
            let x0 = floor(screen.width * CGFloat(column) / CGFloat(inRow))
            let x1 = floor(screen.width * CGFloat(column + 1) / CGFloat(inRow))
            let y0 = floor(screen.height * CGFloat(row) / CGFloat(rows))
            let y1 = floor(screen.height * CGFloat(row + 1) / CGFloat(rows))
            return CGRect(x: screen.minX + x0, y: screen.maxY - y1, width: x1 - x0, height: y1 - y0)
        }
    }
    static func belongs(_ window: CGRect, to display: CGRect) -> Bool {
        guard window.width > 0, window.height > 0 else { return false }
        let overlap = window.intersection(display)
        return !overlap.isNull && overlap.width * overlap.height >= window.width * window.height * 0.5
    }
}

/// Arranges only recognized media windows already on the iPad plus the chosen service.
/// Uses the real open windows, so an app restart does not lose the current media layout.
@MainActor final class MediaTiling {
    static let shared = MediaTiling()
    struct Entry {
        let destination: MediaDestination
        let app: NSRunningApplication
        let window: AXUIElement
    }
    private var order: [Entry] = []

    func existing(on screen: NSScreen) async -> [Entry] {
        let target = WindowSnapper.shared.flip(screen.frame)
        var found: [Entry] = []
        for destination in MediaDestination.allCases {
            guard let url = destination.appURL, let id = Bundle(url: url)?.bundleIdentifier else { continue }
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) where !app.isHidden {
                for window in windows(of: app) where eligible(window, on: target) {
                    found.append(Entry(destination: destination, app: app, window: window))
                }
            }
        }
        // Browser fallbacks are identified by their actual active service URL, not a
        // broad window-title match that could capture the user's ordinary browser.
        if let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first,
           !chrome.isHidden, let script = Bundle.main.url(forResource: "MediaChrome", withExtension: "applescript") {
            let candidates = windows(of: chrome).filter { eligible($0, on: target) }
            if !candidates.isEmpty,
               let listing = try? await ActionProcess.run("/usr/bin/osascript", [script.path, "list"], timeout: 10) {
                for line in listing.split(separator: "\n") {
                    let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                    guard fields.count == 6, let destination = MediaDestination(rawValue: fields[0]),
                          let x = Double(fields[1]), let y = Double(fields[2]),
                          let right = Double(fields[3]), let bottom = Double(fields[4]) else { continue }
                    let frame = CGRect(x: x, y: y, width: right - x, height: bottom - y)
                    let matches = candidates.filter {
                        guard let actual = WindowSnapper.shared.frame(of: $0) else { return false }
                        return abs(actual.minX - frame.minX) < 8 && abs(actual.minY - frame.minY) < 100
                            && abs(actual.width - frame.width) < 8
                    }
                    let named = matches.first(where: {
                        let title = (value($0, kAXTitleAttribute) as? String ?? "")
                            .components(separatedBy: .newlines).joined(separator: " ").replacingOccurrences(of: "\t", with: " ")
                        return title == fields[5]
                    })
                    if let window = named ?? (matches.count == 1 ? matches[0] : nil) {
                        found.append(Entry(destination: destination, app: chrome, window: window))
                    }
                }
            }
        }
        var unique: [Entry] = []
        for entry in found where !unique.contains(where: { CFEqual($0.window, entry.window) }) { unique.append(entry) }
        unique.sort { a, b in
            let ai = order.firstIndex(where: { CFEqual($0.window, a.window) })
            let bi = order.firstIndex(where: { CFEqual($0.window, b.window) })
            if let ai = ai, let bi = bi { return ai < bi }
            if ai != nil || bi != nil { return ai != nil }
            let af = WindowSnapper.shared.frame(of: a.window) ?? .zero
            let bf = WindowSnapper.shared.frame(of: b.window) ?? .zero
            if abs(af.minY - bf.minY) > 20 { return af.minY < bf.minY }
            return af.minX < bf.minX
        }
        return unique
    }

    func arrange(existing: [Entry], adding incoming: Entry, on screen: NSScreen) async throws -> Int {
        let target = WindowSnapper.shared.flip(screen.frame)
        var entries = existing.filter { !$0.app.isTerminated && !$0.app.isHidden && eligible($0.window, on: target) }
        if !entries.contains(where: { CFEqual($0.window, incoming.window) }) { entries.append(incoming) }
        let frames = MediaTilingPlan.frames(in: screen.visibleFrame, count: entries.count)
        let originals = entries.map { (WindowSnapper.shared.frame(of: $0.window), value($0.window, "AXFullScreen") as? Bool == true) }
        do {
            for (index, entry) in entries.enumerated() {
                do { try await GroveActions.shared.place(entry.window, app: entry.app, name: entry.destination.title, frame: frames[index]) }
                catch {
                    // Chrome app shims can apply a cross-display resize asynchronously.
                    try await Task.sleep(nanoseconds: 250_000_000)
                    try await GroveActions.shared.place(entry.window, app: entry.app, name: entry.destination.title, frame: frames[index])
                }
            }
        } catch {
            for (index, entry) in entries.enumerated() {
                if let frame = originals[index].0 { WindowSnapper.shared.setFrame(entry.window, frame) }
                if originals[index].1 { _ = AXUIElementSetAttributeValue(entry.window, "AXFullScreen" as CFString, kCFBooleanTrue) }
            }
            throw GroveError.message("These media windows could not fit together on the iPad. Their previous positions were restored. \(error.localizedDescription)")
        }
        order = entries
        let info: [String: Any] = ["display": screen.localizedName, "count": entries.count,
            "windows": entries.map { ["service": $0.destination.rawValue,
                "frame": WindowSnapper.shared.frame(of: $0.window).map(NSStringFromRect) ?? "unavailable"] }]
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Mini Keyboard/media-layout-status.json")
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url, options: .atomic) }
        return entries.count
    }

    /// Chrome cannot display two tabs side by side as independent macOS windows.
    /// Its native command detaches the selected tab without reloading its playback.
    func detachChromeTab(in app: NSRunningApplication) async throws {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let bar = value(element, kAXMenuBarAttribute) else { throw GroveError.message("Chrome’s Tab menu is unavailable.") }
        let menuBar = bar as! AXUIElement
        guard let tab = children(menuBar).first(where: { value($0, kAXTitleAttribute) as? String == "Tab" }) else {
            throw GroveError.message("Move this media tab into its own Chrome window, then choose it again.")
        }
        _ = AXUIElementPerformAction(tab, kAXPressAction as CFString)
        defer { _ = AXUIElementPerformAction(tab, kAXCancelAction as CFString) }
        try await Task.sleep(nanoseconds: 150_000_000)
        let items = children(tab).flatMap { children($0) }
        guard let item = items.first(where: { value($0, kAXTitleAttribute) as? String == "Move Tab to New Window" }),
              AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
            throw GroveError.message("Move this media tab into its own Chrome window, then choose it again.")
        }
        try await Task.sleep(nanoseconds: 400_000_000)
    }
    private func eligible(_ window: AXUIElement, on target: CGRect) -> Bool {
        guard value(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              value(window, kAXMinimizedAttribute) as? Bool != true,
              let frame = WindowSnapper.shared.frame(of: window) else { return false }
        return MediaTilingPlan.belongs(frame, to: target)
    }
    private func windows(of app: NSRunningApplication) -> [AXUIElement] {
        value(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement] ?? []
    }
    private func children(_ element: AXUIElement) -> [AXUIElement] { value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }
}
