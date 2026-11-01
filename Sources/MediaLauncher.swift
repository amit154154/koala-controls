import AppKit
import ApplicationServices

/// Snapshot only connected screens; display IDs may change when Sidecar reconnects.
struct MediaDisplay {
    let id: CGDirectDisplayID
    let vendor: UInt32
    let model: UInt32
    let builtIn: Bool
    let frame: CGRect

    var isIPad: Bool {
        // Sidecar's "aapl" / "iPad" signature, verified on the user's connected iPad.
        // Do not mistake other Apple/AirPlay displays for the iPad.
        !builtIn && vendor == 0x6161706c && model == 0x69506164
    }
}

enum MediaDisplayPlan {
    static func targetID(in displays: [MediaDisplay], fallbackID: CGDirectDisplayID?, pointer: CGPoint) -> CGDirectDisplayID? {
        if let ipad = displays.first(where: { $0.isIPad }) { return ipad.id }
        if let fallback = displays.first(where: { $0.id == fallbackID }) { return fallback.id }
        return displays.first(where: { $0.frame.contains(pointer) })?.id ?? displays.first?.id
    }
}

enum MediaScreens {
    static func id(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func displays() -> [MediaDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let id = id(screen) else { return nil }
            return MediaDisplay(id: id, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                                builtIn: CGDisplayIsBuiltin(id) != 0, frame: screen.frame)
        }
    }

    static func target(fallbackID: CGDirectDisplayID?, pointer: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        let displays = displays()
        guard let target = MediaDisplayPlan.targetID(in: displays, fallbackID: fallbackID, pointer: pointer) else { return nil }
        return screens.first(where: { id($0) == target })
    }
}

/// A fixed menu of the user's media services. Local apps win over browser fallbacks.
enum MediaDestination: String, CaseIterable {
    case youtubeMusic, spotify, youtube, gdn, netflix, hbo, nba, appleTV
    var title: String {
        switch self {
        case .youtubeMusic: return "YouTube Music"
        case .spotify: return "Spotify"
        case .youtube: return "YouTube"
        case .gdn: return "GDN Play · Gas Digital"
        case .netflix: return "Netflix"
        case .hbo: return "HBO Max"
        case .nba: return "NBA · League Pass"
        case .appleTV: return "Apple TV"
        }
    }
    var appURL: URL? {
        switch self {
        case .youtubeMusic, .youtube, .gdn:
            let name = self == .youtubeMusic ? "YouTube Music" : (self == .youtube ? "YouTube" : "GDN Play")
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Chrome Apps.localized/\(name).app")
        case .spotify: return URL(fileURLWithPath: "/Applications/Spotify.app")
        case .appleTV: return URL(fileURLWithPath: "/System/Applications/TV.app")
        default: return nil
        }
    }
    var iconName: String { "media-" + rawValue }
}

final class MediaLauncher: NSObject {
    static let shared = MediaLauncher()
    private var selected: MediaDestination?
    private var showing = false
    // The parent action stays busy until the selection is launched (or the menu is dismissed).
    func present(onDisplayID: CGDirectDisplayID? = nil, completion: @escaping (String, Bool) -> Void) {
        guard !showing else { completion("The media chooser is already open.", false); return }
        showing = true
        selected = nil
        let requestedScreen = NSScreen.screens.first { MediaScreens.id($0) == onDisplayID }
        let point = requestedScreen.map { CGPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) } ?? NSEvent.mouseLocation
        // Preserve the original mouse display as fallback, independent of app focus.
        let fallbackID = onDisplayID ?? GroveActions.shared.currentScreen().flatMap(MediaScreens.id)
        let screen = MediaScreens.target(fallbackID: fallbackID, pointer: point)
        let menu = NSMenu(title: "Media")
        menu.autoenablesItems = false
        let heading = NSMenuItem(title: "Media · choose your escape", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        for (index, destination) in MediaDestination.allCases.enumerated() {
            let item = NSMenuItem(title: destination.title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            if let url = Bundle.main.url(forResource: destination.iconName, withExtension: "png"), let icon = NSImage(contentsOf: url) {
                icon.size = NSSize(width: 24, height: 24); item.image = icon
            } else {
                item.image = NSImage(systemSymbolName: destination == .nba ? "basketball.fill" : "play.tv.fill", accessibilityDescription: nil)
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let ipad = screen.flatMap(MediaScreens.id).map { id in MediaScreens.displays().contains { $0.id == id && $0.isIPad } } ?? false
        let hint = NSMenuItem(title: ipad ? "iPad · share with your open media" : "Fill \(screen?.localizedName ?? "this display")", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        var menuPoint = point
        if let display = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            // Leave room on the right ourselves so AppKit never has to flip horizontally
            // into the companion's reserved area. Vertical flips are safe in either direction.
            menuPoint.x = max(display.visibleFrame.minX + 24,
                              min(point.x, display.visibleFrame.maxX - menu.size.width - 24))
        }
        ShortcutFeedback.shared.moveBesideMenu(at: menuPoint, size: menu.size)
        menu.popUp(positioning: nil, at: menuPoint, in: nil)
        showing = false
        guard let destination = selected else { completion("Media menu closed.", false); return }
        Task { @MainActor in
            do { completion(try await launch(destination, fallbackID: fallbackID, point: point), false) }
            catch { completion(error.localizedDescription, true) }
        }
    }
    @MainActor func launch(_ destination: MediaDestination, explicitID: CGDirectDisplayID? = nil,
                           forceBrowser: Bool = false, television: Bool = false, fallbackID: CGDirectDisplayID? = nil,
                           point: CGPoint = NSEvent.mouseLocation, televisionFrame: CGRect? = nil,
                           windowReady: ((NSRunningApplication, AXUIElement) -> Void)? = nil) async throws -> String {
                guard AXIsProcessTrusted() else { throw GroveError.message("Allow Accessibility for Mini Keyboard to place your media window.") }
                let initialScreen = explicitID.flatMap { id in NSScreen.screens.first { MediaScreens.id($0) == id } } ?? (explicitID == nil ? MediaScreens.target(fallbackID: fallbackID, pointer: point) : nil)
                guard initialScreen != nil else { throw GroveError.message("The selected display is no longer connected. Choose a display again.") }
                let initialID = initialScreen.flatMap(MediaScreens.id)
                let sharingIPad = !television && (initialID.map { id in MediaScreens.displays().contains { $0.id == id && $0.isIPad } } ?? false)
                let existing = sharingIPad && initialScreen != nil ? await MediaTiling.shared.existing(on: initialScreen!) : []
                let app: NSRunningApplication
                var detach = false
                if !forceBrowser, let url = destination.appURL, FileManager.default.fileExists(atPath: url.path) {
                    // Read the ID from the exact installed app, including the user's Chrome app shims.
                    guard let id = Bundle(url: url)?.bundleIdentifier else { throw GroveError.message("\(destination.title) has an invalid app bundle.") }
                    app = try await self.launchInstalledApp(at: url, id: id)
                } else {
                    guard let script = Bundle.main.url(forResource: television ? "TVChrome" : "MediaChrome", withExtension: "applescript") else {
                        throw GroveError.message("The media browser action is missing. Reinstall Mini Keyboard.")
                    }
                    let result = try await ActionProcess.run("/usr/bin/osascript", [script.path, destination.rawValue, sharingIPad ? "window" : "tab"], timeout: 90)
                    detach = result.trimmingCharacters(in: .whitespacesAndNewlines) == "detach"
                    app = try await GroveActions.shared.launch("com.google.Chrome", name: "Google Chrome")
                }
                if detach { try await MediaTiling.shared.detachChromeTab(in: app) }
                // Prefer this service's current iPad window if the app also has other windows.
                let window: AXUIElement
                if let current = existing.first(where: { $0.destination == destination && $0.app.processIdentifier == app.processIdentifier }),
                   app.bundleIdentifier != "com.google.Chrome" { window = current.window }
                else { window = try await GroveActions.shared.window(for: app, name: destination.title) }
                windowReady?(app,window)
                // Re-read after the menu/app launch: Sidecar may have connected or disconnected.
                guard let screen = explicitID.flatMap({ id in NSScreen.screens.first { MediaScreens.id($0) == id } }) ?? (explicitID == nil ? MediaScreens.target(fallbackID: fallbackID, pointer: point) : nil) else {
                    throw GroveError.message("No display is available.")
                }
                let isIPad = MediaScreens.id(screen).map { id in MediaScreens.displays().contains { $0.id == id && $0.isIPad } } ?? false
                var mediaCount = 1
                if isIPad {
                    let onScreen = await MediaTiling.shared.existing(on: screen)
                    mediaCount = try await MediaTiling.shared.arrange(existing: onScreen,
                        adding: MediaTiling.Entry(destination: destination, app: app, window: window), on: screen)
                } else {
                    try await GroveActions.shared.place(window, app: app, name: destination.title, frame: televisionFrame ?? screen.visibleFrame)
                }
                app.activate(options: [.activateIgnoringOtherApps])
                _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                return mediaCount > 1 ? "\(mediaCount) media windows share your iPad. \(destination.title) is ready."
                    : "\(destination.title) is ready on \(screen.localizedName)."
    }
    @MainActor private func launchInstalledApp(at url: URL, id: String) async throws -> NSRunningApplication {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first { return running }
        return try await withCheckedThrowingContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
                if let app = app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: error ?? GroveError.message("The media app could not open.")) }
            }
        }
    }
    @objc private func choose(_ item: NSMenuItem) {
        guard MediaDestination.allCases.indices.contains(item.tag) else { return }
        selected = MediaDestination.allCases[item.tag]
    }
}

/// Runs only fixed executables with separate arguments. No shell evaluation.
enum ActionProcess {
    @MainActor static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errors
            process.terminationHandler = { process in
                let result = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let error = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if process.terminationStatus == 0 { continuation.resume(returning: result) }
                else if error.contains("1743") || error.contains("not authorized") {
                    continuation.resume(throwing: GroveError.message("Allow Mini Keyboard → Google Chrome in Privacy & Security → Automation, then try Media again."))
                } else {
                    continuation.resume(throwing: GroveError.message(error.isEmpty ? "The media app did not respond. Check for a permission prompt, then retry." : String(error.prefix(400))))
                }
            }
            do {
                try process.run()
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak process] in
                    if let process = process, process.isRunning { process.terminate() }
                }
            } catch { continuation.resume(throwing: error) }
        }
    }
}
