import AppKit
import ApplicationServices

/// The user's workspace shortcuts. Kept as first-class actions so their names,
/// illustrations and behavior stay together when the user changes assignments.
enum GroveAction: String, CaseIterable {
    case connect, viz, media, write, code, build, claude, setup, guide
    case chromeViz = "chrome_viz"
    var actionID: String { "grove_" + rawValue }
    var key: String { [Self.connect: "k1", .viz: "k2", .media: "k3", .write: "k4", .code: "k5", .build: "k6", .claude: "k8", .setup: "k7", .guide: "Lpress", .chromeViz: "Rpress"][self]! }
    var title: String {
        switch self {
        case .connect: return "Connect"
        case .viz: return "Koala Viz"
        case .chromeViz: return "Koala Viz in Chrome"
        case .media: return "Media"
        case .write: return "Notes & chat"
        case .code: return "Code focus"
        case .build: return "Build & browse"
        case .claude: return "Claude workspace"
        case .setup: return "Set up everything"
        case .guide: return "Keypad guide"
        }
    }
    var detail: String {
        switch self {
        case .connect: return "Run the instance viewer’s Connect shortcut."
        case .viz: return "Find your Koala Viz tab in Chrome, or open it once."
        case .chromeViz: return "While Google Chrome is active, press the tab knob to open or switch to Koala Viz, just like key 2."
        case .media: return "Choose your music or movie app. Open media shares your iPad: one fills it, two sit side by side, and more use a grid. Without the iPad, it fills the display under your mouse."
        case .write: return "Obsidian left, Slack right. A Split View Space on the MacBook when mobile; desktop halves at your desk."
        case .code: return "VS Code in a Full Screen Space when mobile; fills the display under your mouse at your desk."
        case .build: return "Zed left, Chrome right. A Split View Space on the MacBook when mobile; desktop halves at your desk."
        case .claude: return "Two Claude chats above, nvitop and a free shell below. Reuse your sessions, or start new chats."
        case .setup: return "Arrange your whole desk: notes and chat on the MacBook, code in the middle, build and browse on the right. With just the MacBook, open Obsidian."
        case .guide: return "Show your physical keypad’s shortcuts. Press the left knob again, press a shortcut, or hit Escape to close."
        }
    }
    var apps: [(id: String, name: String)] {
        switch self {
        case .write: return [("md.obsidian", "Obsidian"), ("com.tinyspeck.slackmacgap", "Slack")]
        case .code, .claude: return [("com.microsoft.VSCode", "Visual Studio Code")]
        case .build: return [("dev.zed.Zed", "Zed"), ("com.google.Chrome", "Google Chrome")]
        default: return []
        }
    }
    static func from(_ ref: ActionRef?) -> GroveAction? {
        guard let ref = ref else { return nil }
        return allCases.first { $0.actionID == ref.id }
    }
}

enum GrovePlan {
    static func chromeVizAllowed(frontmostBundleID: String?) -> Bool {
        frontmostBundleID == "com.google.Chrome"
    }
    static func claudeShortcutAllowed(frontmostBundleID: String?) -> Bool {
        frontmostBundleID == "com.microsoft.VSCode"
    }
    /// AppKit pointer locations and NSScreen frames share the same desktop coordinates.
    static func screenIndex(at pointer: CGPoint, frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(pointer) }
    }
    static func frames(in screen: CGRect, count: Int) -> [CGRect] {
        if count == 1 { return [screen] }
        let leftWidth = floor(screen.width / 2)
        return [CGRect(x: screen.minX, y: screen.minY, width: leftWidth, height: screen.height),
                CGRect(x: screen.minX + leftWidth, y: screen.minY, width: screen.width - leftWidth, height: screen.height)]
    }
    static func shortcutName(in data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let config = object?["config"] as? [String: Any],
              let name = config["shortcut"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GroveError.message("Choose a Connect shortcut in the instance viewer first.")
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum GroveError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

final class GroveActions {
    static let shared = GroveActions()
    var onStatus: ((String, Bool) -> Void)?
    var onPadGuide: (() -> Void)?
    private var busy: Set<GroveAction> = []
    private var layoutRunning = false
    var isRunningLayout: Bool { layoutRunning }
    func beginExternalLayout() -> Bool { guard !layoutRunning else { return false }; layoutRunning = true; return true }
    func endExternalLayout() { layoutRunning = false }
    private var completions: [GroveAction: (String, Bool) -> Void] = [:]
    private var processes: [GroveAction: Process] = [:]
    // Read the live widget's config first, just as its Connect button does.
    static var configurationURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent("Library/Application Support/Mini Keyboard/connect.json")]
    }

    func perform(_ action: GroveAction, onDisplayID: CGDirectDisplayID? = nil, phone: Bool = false, onAccepted: (() -> Void)? = nil, completion: ((String, Bool) -> Void)? = nil) {
        if action == .chromeViz {
            guard GrovePlan.chromeVizAllowed(frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else { completion?("Koala Viz knob press is available in Chrome.",true); return }
            // Reuse button 2's action, tab matching, and duplicate-execution guard.
            perform(.viz, onAccepted: onAccepted, completion: completion)
            return
        }
        guard !busy.contains(action) else { completion?("This action is already running.", true); return }
        if (action == .media || action == .setup || !action.apps.isEmpty) && layoutRunning { completion?("A workspace is still being arranged. Try again when it finishes.", true); return }
        busy.insert(action)
        completions[action] = completion
        if action != .claude || GrovePlan.claudeShortcutAllowed(frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
            onAccepted?()
        }
        onStatus?("\(action.title)…", false)
        switch action {
        case .guide:
            onPadGuide?()
            finish(action, "Keypad guide toggled. Turn the left knob to change volume.")
        case .setup:
            let plan = DeskPlan.build(MediaScreens.displays())
            layoutRunning = true
            Task { @MainActor in
                let errors = await DeskSetup.run(plan, actions: self)
                let message = errors.isEmpty ? "Your desk is ready." : "Desk setup: " + errors.joined(separator: " ")
                if !phone, let ipadID = plan.mediaDisplayID,
                   NSScreen.screens.contains(where: { MediaScreens.id($0) == ipadID }) {
                    MediaLauncher.shared.present(onDisplayID: ipadID) { [weak self] mediaMessage, failed in
                        self?.layoutRunning = false
                        self?.finish(action, message + " " + mediaMessage, failed: !errors.isEmpty || failed)
                    }
                } else {
                    self.layoutRunning = false
                    self.finish(action, message, failed: !errors.isEmpty)
                }
            }
        case .claude:
            guard GrovePlan.claudeShortcutAllowed(frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else {
                finish(action, "Focus your connected VS Code window, then press key 8."); return
            }
            guard AXIsProcessTrusted() else {
                finish(action, "Allow Accessibility for Mini Keyboard to send the VS Code shortcut.", failed: true); return
            }
            NativeAction.sendKey("8", mods: ["ctrl", "opt", "cmd"])
            finish(action, "Claude workspace requested in VS Code.")
        case .media:
            layoutRunning = true
            MediaLauncher.shared.present { [weak self] message, failed in
                self?.layoutRunning = false
                self?.finish(action, message, failed: failed)
            }
        case .connect:
            do {
                guard let config = Self.configurationURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                    throw GroveError.message("The instance viewer configuration could not be found.")
                }
                let name = try GrovePlan.shortcutName(in: Data(contentsOf: config))
                run(action, executable: "/usr/bin/shortcuts", arguments: ["run", name], timeout: nil,
                    success: "Connect shortcut finished.")
            } catch { finish(action, error.localizedDescription, failed: true) }
        case .viz, .chromeViz:
            guard let script = Bundle.main.url(forResource: "KoalaChrome", withExtension: "applescript") else {
                finish(action, "Koala Viz’s browser action is missing. Reinstall Mini Keyboard.", failed: true); return
            }
            run(action, executable: "/usr/bin/osascript", arguments: [script.path], timeout: 90,
                success: "Koala Viz is ready in Chrome.")
        default:
            let mobileID = MobileSpacePlan.displayID(in: MediaScreens.displays())
            let screen: NSScreen?
            if let id = mobileID ?? onDisplayID { screen = NSScreen.screens.first { MediaScreens.id($0) == id } }
            else { screen = currentScreen() }
            layoutRunning = true
            Task { @MainActor in
                defer { self.layoutRunning = false }
                do {
                    guard AXIsProcessTrusted() else { throw GroveError.message("Allow Accessibility for Mini Keyboard to arrange windows.") }
                    guard let screen = screen else { throw GroveError.message("No display is available.") }
                    // Keep the pointer's display captured before launching or focusing any apps.
                    let targets = GrovePlan.frames(in: screen.visibleFrame, count: action.apps.count)
                    var applications: [NSRunningApplication] = []
                    for app in action.apps {
                        applications.append(try await self.launch(app.id, name: app.name))
                    }
                    if mobileID != nil, try await MobileSpaces.reuseExistingSpace(for: applications, on: screen) {
                        self.finish(action, "Switched to your existing \(action.title) Space.")
                        return
                    }
                    var windows: [(NSRunningApplication, AXUIElement)] = []
                    for (index, running) in applications.enumerated() {
                        let window = try await self.window(for: running, name: action.apps[index].name)
                        windows.append((running, window))
                    }
                    if mobileID != nil {
                        try await MobileSpaces.arrange(windows, names: action.apps.map(\.name), on: screen, actions: self)
                        self.finish(action, "\(action.title) is ready in a macOS \(windows.count == 1 ? "Full Screen" : "Split View") Space on \(screen.localizedName).")
                        return
                    }
                    for (index, pair) in windows.enumerated() {
                        try await self.place(pair.1, app: pair.0, name: action.apps[index].name, frame: targets[index])
                    }
                    // Leave the editor/notes app focused, with the companion visible beside it.
                    windows.first?.0.activate(options: [.activateIgnoringOtherApps])
                    if let window = windows.first?.1 { _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
                    self.finish(action, "\(action.title) is ready on \(screen.localizedName).")
                } catch { self.finish(action, error.localizedDescription, failed: true) }
            }
        }
    }

    @MainActor func place(_ window: AXUIElement, app: NSRunningApplication, name: String, frame: CGRect) async throws {
        _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        if self.attribute(window, "AXFullScreen") as? Bool == true {
            guard AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse) == .success else {
                throw GroveError.message("Exit full screen in \(name), then press this key again.")
            }
            for _ in 0..<60 {
                try await Task.sleep(nanoseconds: 100_000_000)
                if self.attribute(window, "AXFullScreen") as? Bool != true { break }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        app.unhide()
        let target = WindowSnapper.shared.flip(frame)
        WindowSnapper.shared.setFrame(window, target)
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        try await Task.sleep(nanoseconds: 200_000_000)
        WindowSnapper.shared.setFrame(window, target)
        guard let actual = WindowSnapper.shared.frame(of: window),
              abs(actual.minX - target.minX) < 6, abs(actual.minY - target.minY) < 6,
              abs(actual.width - target.width) < 6, abs(actual.height - target.height) < 6 else {
            throw GroveError.message("\(name) could not fit this layout. Check its minimum window size or exit full screen, then retry.")
    }
    }

    private func finish(_ action: GroveAction, _ message: String, failed: Bool = false) {
        busy.remove(action)
        processes[action] = nil
        onStatus?(message, failed)
        let completion = completions.removeValue(forKey: action)
        completion?(message, failed)
    }

    private func run(_ action: GroveAction, executable: String, arguments: [String], timeout: TimeInterval?, success: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        process.terminationHandler = { [weak self] process in
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard let self = self, self.processes[action] === process else { return }
                if process.terminationStatus == 0 { self.finish(action, success) }
                else if detail.contains("1743") || detail.contains("not authorized") {
                    self.finish(action, "Allow Mini Keyboard → Google Chrome in System Settings → Privacy & Security → Automation, then press key 2 again.", failed: true)
                } else {
                    self.finish(action, detail.isEmpty ? "\(action.title) could not finish. Try again." : String(detail.prefix(500)), failed: true)
                }
            }
        }
        do {
            processes[action] = process
            try process.run()
            if let timeout = timeout {
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self, weak process] in
                    guard let self = self, let process = process, self.processes[action] === process, process.isRunning else { return }
                    process.terminate()
                    self.finish(action, "Chrome did not respond. Check for a permission prompt, then press key 2 again.", failed: true)
                }
            }
        } catch { finish(action, error.localizedDescription, failed: true) }
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    func currentScreen() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard let index = GrovePlan.screenIndex(at: pointer, frames: screens.map(\.frame)) else { return NSScreen.main }
        return screens[index]
    }
    @MainActor func launch(_ id: String, name: String) async throws -> NSRunningApplication {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first { return app }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            throw GroveError.message("Install \(name) in Applications to use this shortcut.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                if let app = app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: error ?? GroveError.message("Could not open \(name).")) }
            }
        }
    }
    @MainActor func window(for app: NSRunningApplication, name: String) async throws -> AXUIElement {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 1)
        // Reopen a running app with no windows through its normal Dock-style open event.
        var reopened = false
        for attempt in 0..<80 {
            let candidates = [WindowSnapper.shared.element(element, kAXFocusedWindowAttribute),
                              WindowSnapper.shared.element(element, kAXMainWindowAttribute)].compactMap { $0 }
                + (attribute(element, kAXWindowsAttribute) as? [AXUIElement] ?? [])
            if let window = candidates.first(where: {
                (attribute($0, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole
                    && WindowSnapper.shared.frame(of: $0) != nil
            }) { return window }
            if attempt == 10, !reopened, let url = app.bundleURL {
                reopened = true
                let config = NSWorkspace.OpenConfiguration(); config.activates = false
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        throw GroveError.message("Open a normal \(name) window, then press this key again.")
    }
}
