import AppKit
import ApplicationServices
import CoreAudio
import Carbon

@MainActor final class RemoteActions {
    private struct Focus {
        let token: String
        let pid: pid_t
        let window: AXUIElement
        let input: AXUIElement?
    }
    private var focus: Focus?
    private var lastSpaceSwitch = Date.distantPast
    private var mediaCache: [[String: Any]] = []
    private var mediaUpdated = Date.distantPast
    private var mediaRefreshing = false
    private var mediaScreenID: UInt32?

    func snapshot() -> [String: Any] {
        let screens = NSScreen.screens
        let displays: [[String: Any]] = screens.map { s in
            let id = MediaScreens.id(s) ?? 0
            let d = MediaScreens.displays().first { $0.id == id }
            return ["id": String(id), "name": d?.isIPad == true ? "iPad" : d?.builtIn == true ? "MacBook" : s.localizedName,
                    "ipad": d?.isIPad == true, "builtin": d?.builtIn == true, "x": s.frame.minX, "y": s.frame.minY]
        }
        let front = NSWorkspace.shared.frontmostApplication
        let f = captureFocus()
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }.compactMap { app -> [String: Any]? in
                guard let id = app.bundleIdentifier else { return nil }; return ["id": id, "name": app.localizedName ?? id]
            }
        return ["tv": TVMode.shared.snapshot, "serverTime": Date().timeIntervalSince1970, "macName": Host.current().localizedName ?? "Mac",
                "accessibility": AXIsProcessTrusted(), "displays": displays,
                "mobile": !MediaScreens.displays().contains { !$0.builtIn && !$0.isIPad },
                "frontApp": front?.localizedName ?? "Mac", "frontBundle": front?.bundleIdentifier ?? "",
                "focus": f?.token ?? "", "secureInput": IsSecureEventInputEnabled(), "apps": apps,
                "volume": RemoteVolume.get() as Any? ?? NSNull(), "media": mediaCache,
                "mediaDisplay": mediaScreenID.map(String.init) ?? "", "layoutBusy": GroveActions.shared.isRunningLayout, "adventure": AdventureStore.shared.snapshot()]
    }

    func refreshMedia(on screen: NSScreen) {
        let id = MediaScreens.id(screen)
        guard !mediaRefreshing, id != mediaScreenID || Date().timeIntervalSince(mediaUpdated) > 8 else { return }
        mediaRefreshing = true
        Task { @MainActor in
            let entries = await MediaTiling.shared.existing(on: screen)
            mediaCache = entries.map { ["service": $0.destination.rawValue, "name": $0.destination.title] }
            mediaScreenID = id; mediaUpdated = Date(); mediaRefreshing = false
        }
    }
    func invalidateMedia() { mediaUpdated = .distantPast }

    func screen(_ value: String?, media: Bool) throws -> NSScreen {
        let displays = MediaScreens.displays()
        let requested: UInt32?
        if value == nil || value == "auto" {
            requested = (media ? displays.first(where: \.isIPad)?.id : nil) ?? displays.first(where: \.builtIn)?.id ?? displays.first?.id
        } else { requested = value.flatMap(UInt32.init) }
        guard let id = requested, let screen = NSScreen.screens.first(where: { MediaScreens.id($0) == id }) else {
            throw RemoteFailure.message("The selected display disconnected. Choose a display again.")
        }
        return screen
    }

    func activity(_ object: [String:Any], kind: String) -> (action:String,name:String,trigger:String)? {
        if kind == "tv", let control = object["control"] as? String, ["home","media","game","share","focus","fullscreen","focusMedia","hideMedia","resume","resumeOpen","exit"].contains(control) { return ("tv_"+control, "Koala TV · " + control, "Phone TV remote") }
        if kind == "key", let n = object["key"] as? Int {
            let ids = [1:"grove_connect",2:"grove_viz",3:"grove_media",4:"grove_write",5:"grove_code",6:"grove_build",7:"grove_setup",8:"grove_claude",9:"win_min",10:"win_left",11:"win_max",12:"win_right"]
            if let id = ids[n] { return (id,AdventureCatalog.name(id),"Phone key \(n)") }
        }
        if kind == "corner", let raw = object["corner"] as? String, let c = WindowCorner(rawValue:raw) { return (c.actionID,c.title,"Phone " + c.pad) }
        if kind == "media" { return ("grove_media","Media · " + (MediaDestination(rawValue:object["service"] as? String ?? "")?.title ?? "service"),"Phone media chooser") }
        if kind == "special", let control = object["special"] as? String {
            let map = ["previousSpace":"space_prev","nextSpace":"space_next","previousTab":"tab_prev","nextTab":"tab_next"]
            let id = map[control] ?? "remote_" + control
            return (id,AdventureCatalog.name(id),"Phone " + control)
        }
        if kind == "arrangeMedia" || kind == "focusMedia" { let id = kind == "arrangeMedia" ? "media_arrange" : "media_focus"; return (id,AdventureCatalog.name(id),"Phone media") }
        if kind == "volume" { return ("volume","Mac volume","Phone volume") }
        return nil
    }

    func execute(_ object: [String: Any], kind: String, completion: @escaping (String, Bool, [String: Any]) -> Void) {
        do {
            guard AXIsProcessTrusted() else { throw RemoteFailure.message("Enable Mini Keyboard in Mac Settings → Privacy & Security → Accessibility.") }
            if GroveActions.shared.isRunningLayout { throw RemoteFailure.message("A workspace is still being arranged. Wait for it to finish.") }
            switch kind {
            case "tv":
                TVMode.shared.command(object, record: false, completion: completion)
            case "corner":
                _ = try requireFocus(object)
                guard let corner = WindowCorner(rawValue:object["corner"] as! String), WindowSnapper.shared.perform(corner.windowAction) else { throw RemoteFailure.message("Focus a resizable Mac window, then retry.") }
                completion("Window moved to " + corner.title.lowercased() + ".",false,[:])
            case "key":
                let n = object["key"] as! Int
                if n == 3 { completion("Choose media on your phone.", false, ["showMedia": true]); return }
                if [9, 10, 11, 12].contains(n) { _ = try requireFocus(object) }
                if n == 9 {
                    guard let f = focus, AXUIElementSetAttributeValue(f.window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success else { throw RemoteFailure.message("This window cannot be minimized.") }
                    completion("Window minimized.", false, [:]); return
                }
                if [10, 11, 12].contains(n) {
                    let a: WindowAction = n == 10 ? .left : n == 11 ? .maximize : .right
                    guard WindowSnapper.shared.perform(a) else { throw RemoteFailure.message("Focus a normal Mac window, then retry.") }
                    completion(n == 11 ? "Window fills its display." : "Window moved \(n == 10 ? "left" : "right").", false, [:]); return
                }
                let map: [Int: GroveAction] = [1: .connect, 2: .viz, 4: .write, 5: .code, 6: .build, 7: .setup, 8: .claude]
                guard let action = map[n] else { throw RemoteFailure.message("Unknown shortcut") }
                if action == .claude {
                    _ = try requireFocus(object)
                    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.microsoft.VSCode" else {
                        throw RemoteFailure.message("Focus your connected VS Code window using Remote → Controlling, then tap Claude desk again.")
                    }
                }
                let display = try screen(object["display"] as? String, media: false)
                GroveActions.shared.perform(action, onDisplayID: MediaScreens.id(display), phone: true) { message, failed in
                    completion(message, failed, action == .setup && MediaScreens.displays().contains(where: \.isIPad) ? ["showMedia": true] : [:])
                }
            case "media", "arrangeMedia", "focusMedia":
                let display = try screen(object["display"] as? String, media: true)
                guard GroveActions.shared.beginExternalLayout() else { throw RemoteFailure.message("A layout is already running.") }
                Task { @MainActor in
                    defer { GroveActions.shared.endExternalLayout() }
                    do {
                        let message: String
                        if kind == "media" {
                            let destination = MediaDestination(rawValue: object["service"] as! String)!
                            message = try await MediaLauncher.shared.launch(destination, explicitID: MediaScreens.id(display), forceBrowser: object["browser"] as? Bool == true)
                        } else {
                            let entries = await MediaTiling.shared.existing(on: display)
                            if kind == "arrangeMedia" {
                                guard let first = entries.first else { throw RemoteFailure.message("No media windows found on this display.") }
                                let count = try await MediaTiling.shared.arrange(existing: entries, adding: first, on: display)
                                message = "\(count) media windows arranged."
                            } else {
                                guard let entry = entries.first(where: { $0.destination.rawValue == object["service"] as? String }) else { throw RemoteFailure.message("That media window is no longer on this display.") }
                                entry.app.activate(options: [.activateIgnoringOtherApps]); _ = AXUIElementPerformAction(entry.window, kAXRaiseAction as CFString)
                                message = "\(entry.destination.title) focused."
                            }
                        }
                        invalidateMedia(); refreshMedia(on: display); completion(message, false, [:])
                    } catch { completion(error.localizedDescription, true, [:]) }
                }
            case "focusApp":
                guard let id = object["app"] as? String,
                      let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id && $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }) else { throw RemoteFailure.message("That app is no longer running.") }
                app.unhide(); app.activate(options: [.activateIgnoringOtherApps]); completion("\(app.localizedName ?? "App") focused. Choose its intended window before typing.", false, [:])
            case "volume":
                try RemoteVolume.set(Float(object["value"] as! Double)); completion("Mac volume updated.", false, [:])
            case "pointer":
                let p = CGEvent(source: nil)?.location ?? .zero
                let dest = CGPoint(x: p.x + (object["dx"] as! Double), y: p.y + (object["dy"] as! Double))
                CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: dest, mouseButton: .left)?.post(tap: .cghidEventTap)
                completion("", false, [:])
            case "scroll":
                let dx = Int32(object["dx"] as! Double), dy = Int32(object["dy"] as! Double)
                CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: -dy, wheel2: -dx, wheel3: 0)?.post(tap: .cghidEventTap)
                completion("", false, [:])
            case "click":
                let right = object["button"] as? String == "right"
                let p = CGEvent(source: nil)?.location ?? .zero
                for down in [true, false] {
                    CGEvent(mouseEventSource: nil, mouseType: right ? (down ? .rightMouseDown : .rightMouseUp) : (down ? .leftMouseDown : .leftMouseUp), mouseCursorPosition: p, mouseButton: right ? .right : .left)?.post(tap: .cghidEventTap)
                }
                completion("Click sent.", false, [:])
            case "special":
                let special = object["special"] as! String
                if special == "previousSpace" || special == "nextSpace" {
                    // Space navigation is global: it must work on an empty desktop and after
                    // the previous transition changes the frontmost window or focused field.
                    guard Date().timeIntervalSince(lastSpaceSwitch) >= 0.45 else {
                        throw RemoteFailure.message("Let the desktop transition finish, then tap again.")
                    }
                    let preferences = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
                    let shortcut = try RemoteSpaceShortcut.resolve(special, preferences: preferences)
                    let source = CGEventSource(stateID: .privateState)
                    guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcut.code), keyDown: true),
                          let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcut.code), keyDown: false) else {
                        throw RemoteFailure.message("Could not send the desktop shortcut.")
                    }
                    lastSpaceSwitch = Date()
                    down.flags = CGEventFlags(rawValue: shortcut.flags); up.flags = down.flags
                    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
                    completion(special == "previousSpace" ? "Previous Space requested." : "Next Space requested.", false, [:]); return
                }
                _ = try requireFocus(object)
                let map: [String: (String, [String])] = ["escape": ("escape", []), "return": ("return_or_enter", []), "undo": ("z", ["cmd"]), "previousTab": ("tab", ["ctrl", "shift"]), "nextTab": ("tab", ["ctrl"])]
                let pair = map[special]!
                guard NativePlan.macCodes[pair.0] != nil else { throw RemoteFailure.message("This keyboard control is unavailable.") }
                NativeAction.sendKey(pair.0, mods: pair.1); completion("Control sent.", false, [:])
            case "text":
                let f = try requireFocus(object)
                guard !IsSecureEventInputEnabled(), let input = f.input,
                      value(input, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
                      [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(value(input, kAXRoleAttribute) as? String ?? "") else {
                    throw RemoteFailure.message("Click a normal text field on your Mac first. Password fields and non-text targets are not supported.")
                }
                let text = object["text"] as! String
                var chunks: [[UniChar]] = [], chunk: [UniChar] = []
                for scalar in text.unicodeScalars {
                    let units = Array(String(scalar).utf16)
                    if chunk.count + units.count > 20 { chunks.append(chunk); chunk = [] }; chunk += units
                }
                if !chunk.isEmpty { chunks.append(chunk) }
                for chars in chunks {
                    _ = try requireFocus(object)
                    for down in [true, false] {
                        guard let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: 0, keyDown: down) else { continue }
                        chars.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: $0.baseAddress) }
                        event.postToPid(f.pid)
                    }
                }
                completion("Text inserted. Return was not pressed.", false, [:])
            default: throw RemoteFailure.message("Unknown action")
            }
        } catch { completion(error.localizedDescription, true, [:]) }
    }
    private func captureFocus() -> Focus? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else { focus = nil; return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(ax, 0.25)
        guard let window = WindowSnapper.shared.element(ax, kAXFocusedWindowAttribute) else { focus = nil; return nil }
        let input = WindowSnapper.shared.element(ax, kAXFocusedUIElementAttribute)
        if let old = focus, old.pid == app.processIdentifier, CFEqual(old.window, window),
           (old.input == nil && input == nil || old.input != nil && input != nil && CFEqual(old.input!, input!)) { return old }
        let f = Focus(token: UUID().uuidString, pid: app.processIdentifier, window: window, input: input); focus = f; return f
    }
    private func requireFocus(_ object: [String: Any]) throws -> Focus {
        guard let expected = object["focus"] as? String, let f = captureFocus(), expected == f.token else {
            throw RemoteFailure.message("The focused Mac window or field changed. Check the target, then tap again.")
        }
        return f
    }
    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?; return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }
}

enum RemoteVolume {
    static func get()->Float?{TVAudioHardware.output.flatMap{TVAudioHardware.volume($0)}.map(Float.init)}
    static func set(_ volume:Float) throws{try TVAudioHardware.setVolume(Double(volume))}
}
