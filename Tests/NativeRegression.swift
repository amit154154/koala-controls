import Foundation

@main
enum NativeRegression {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    static func main() throws {
        let settingsURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let settings = try JSONDecoder().decode(PadSettings.self, from: Data(contentsOf: settingsURL))
        check(settings.shortcutEngine == .native, "Older settings migrate to the driver-free mode")
        let plan = NativePlan.build(settings)
        check(plan.bindings.count == 4 && plan.skipped.isEmpty, "All current assignments are supported")
        check(plan.bindings.map(\.control) == ["Rccw", "Rcw", "k10", "k12"], "Preserve physical controls")
        check(plan.bindings.map(\.action.id) == ["tab_prev", "tab_next", "win_left", "win_right"], "Preserve intended actions")
        check(plan.bindings.map(\.sourceUsage) == [0x700000021, 0x700000023, 0x700000004, 0x70000000c], "Use the learned 4, 6, A and I keys")
        check(Set(plan.bindings.map(\.relayUsage)).count == 4, "Every action has a distinct relay")
        let restoredSettings = try JSONDecoder().decode(PadSettings.self, from: JSONEncoder().encode(settings))
        check(restoredSettings == settings, "Preserve saved data across encoding")
        check(NativePlan.usage("0") == 0x27 && NativePlan.usage("f20") == 0x6f, "Correct HID usage values")

        var expanded = settings
        for id in ["k1", "k2", "k3", "k4", "k5"] { expanded.controls[id]?.action = ActionRef(id: "tab_next") }
        let limit = NativePlan.build(expanded)
        check(limit.bindings.count == 9 && limit.skipped.isEmpty, "All nine shortcuts fit without dropping the existing corner key")
        for id in ["k6", "k7", "k8", "k9"] { expanded.controls[id]?.action = ActionRef(id: "tab_next") }
        let full = NativePlan.build(expanded)
        check(full.bindings.count == 13 && full.skipped.isEmpty, "Thirteen keys fit after expanding the relay pool")
        check(Set(full.bindings.map(\.relayUsage)).count == 13, "Expanded relay usages are unique")
        check(Set(full.bindings.map(\.relayCode)).count == 13, "Expanded Carbon hotkeys are unique")
        expanded.controls["Rccw"]?.source = .key(code: "a", mods: [])
        check(!NativePlan.build(expanded).bindings.contains { $0.control == "Rccw" || $0.control == "k10" }, "Reject source collisions")
        var recursion = settings
        recursion.controls["Rcw"]?.action = ActionRef(id: "custom", params: ["code": "f17"])
        check(!NativePlan.build(recursion).bindings.contains { $0.control == "Rcw" }, "Prevent output from re-triggering a reserved relay")

        for action in GroveAction.allCases {
            var grove = settings
            grove.controls[action.key]?.action = ActionRef(id: action.actionID)
            check(NativePlan.build(grove).bindings.count == 5, "Workspace action is usable in native mode")
        }
        var allGrove = settings
        for action in GroveAction.allCases { allGrove.controls[action.key]?.action = ActionRef(id: action.actionID) }
        let grovePlan = NativePlan.build(allGrove)
        check(grovePlan.bindings.count == 14 && grovePlan.skipped.isEmpty, "All ten grove actions plus four old assignments are active")
        check(grovePlan.bindings.contains { $0.control == "k12" }, "Keep the right corner key active after adding the six grove actions")
        check(grovePlan.bindings.first(where: { $0.control == "k3" })?.sourceUsage == 0x70000000f, "Media uses learned L on key 3")
        check(Set(MediaDestination.allCases.map(\.rawValue)).count == 7, "Seven distinct media destinations")
        check(MediaDestination.gdn.appURL?.lastPathComponent == "GDN Play.app", "Use the requested GDN app")
        check(MediaDestination.netflix.appURL == nil && MediaDestination.hbo.appURL == nil, "Streaming sites use Chrome")
        var withFill = allGrove
        withFill.controls["k11"]?.action = ActionRef(id: "win_max")
        let fillPlan = NativePlan.build(withFill)
        check(fillPlan.bindings.count == 15 && fillPlan.skipped.isEmpty, "Setup, both knob presses, Claude and Fill fit alongside all existing assignments")
        check(fillPlan.bindings.first(where: { $0.control == "k8" })?.action.id == "grove_claude", "Key 8 opens the Claude workspace")
        check(fillPlan.bindings.first(where: { $0.control == "k8" })?.sourceUsage == 0x700000009, "Key 8 uses its learned F input")
        check(GrovePlan.claudeShortcutAllowed(frontmostBundleID: "com.microsoft.VSCode"), "Claude layout works in VS Code")
        check(!GrovePlan.claudeShortcutAllowed(frontmostBundleID: "com.google.Chrome") && !GrovePlan.claudeShortcutAllowed(frontmostBundleID: nil), "Do not send the layout shortcut into other apps")
        check(fillPlan.bindings.first(where: { $0.control == "k11" })?.action.id == "win_max", "Center bottom key maximizes")
        check(!NativePlan.slots.contains { $0.1 == 103 || $0.0 == 0x44 }, "Never reserve F11, which macOS consumes for Show Desktop")
        check(!NativePlan.slots.contains { [107, 113].contains($0.1) || [0x69, 0x6a].contains($0.0) }, "Never use F14/F15 relays, which also change display brightness")
        check(fillPlan.bindings.first(where: { $0.control == "k4" })?.action.id == "grove_write"
            && fillPlan.bindings.first(where: { $0.control == "k5" })?.action.id == "grove_code", "Brightness fix preserves the Notes & chat and Code focus assignments")
        let screen = CGRect(x: -1512, y: 38, width: 1511, height: 944)
        let halves = GrovePlan.frames(in: screen, count: 2)
        check(halves[0].minX == screen.minX && halves[1].maxX == screen.maxX && halves[0].maxX == halves[1].minX, "Multi-display layouts fill odd widths without gaps")
        check(GrovePlan.frames(in: screen, count: 1) == [screen], "Code focus fills the selected display")
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let externalLeft = CGRect(x: -2560, y: -220, width: 2560, height: 1440)
        let externalAbove = CGRect(x: 0, y: 982, width: 1920, height: 1080)
        let displays = [laptop, externalLeft, externalAbove]
        check(GrovePlan.screenIndex(at: CGPoint(x: -1200, y: 600), frames: displays) == 1, "Pointer on external display wins even when the laptop is first/main")
        check(GrovePlan.screenIndex(at: CGPoint(x: 200, y: 1200), frames: displays) == 2, "Support vertically arranged displays")
        check(GrovePlan.screenIndex(at: CGPoint(x: 100, y: 100), frames: displays) == 0, "Pointer on laptop selects laptop")
        check(GrovePlan.screenIndex(at: CGPoint(x: 0, y: 300), frames: displays) == 0, "A shared display edge has one deterministic owner")
        check(GrovePlan.screenIndex(at: CGPoint(x: 5000, y: 5000), frames: displays) == nil, "Invalid pointer locations fall back safely")
        check(GrovePlan.screenIndex(at: .zero, frames: []) == nil, "Handle no attached displays")
        let macDisplay = MediaDisplay(id: 1, vendor: 0x610, model: 0xa050, builtIn: true, frame: laptop)
        let dellDisplay = MediaDisplay(id: 2, vendor: 0x10ac, model: 0xd0d9, builtIn: false, frame: externalLeft)
        let ipadDisplay = MediaDisplay(id: 4, vendor: 0x6161706c, model: 0x69506164, builtIn: false, frame: externalAbove)
        let mediaDisplays = [macDisplay, dellDisplay, ipadDisplay]
        let laptopPointer = CGPoint(x: 100, y: 100)
        check(MediaDisplayPlan.targetID(in: mediaDisplays, fallbackID: 1, pointer: laptopPointer) == 4, "Connected iPad wins over mouse on laptop")
        check(MediaDisplayPlan.targetID(in: mediaDisplays, fallbackID: 2, pointer: CGPoint(x: -100, y: 100)) == 4, "Connected iPad wins over mouse on external monitor")
        check(MediaDisplayPlan.targetID(in: [macDisplay, dellDisplay], fallbackID: 2, pointer: laptopPointer) == 2, "Disconnected iPad restores the display captured before app focus changes")
        let reconnectedIPad = MediaDisplay(id: 99, vendor: ipadDisplay.vendor, model: ipadDisplay.model, builtIn: false, frame: externalAbove)
        check(MediaDisplayPlan.targetID(in: [macDisplay, reconnectedIPad], fallbackID: 4, pointer: laptopPointer) == 99, "Reconnected iPad is found by its identity, not a stale display ID")
        check(MediaDisplayPlan.targetID(in: [macDisplay, dellDisplay], fallbackID: 4, pointer: laptopPointer) == 1, "Removed destination falls back to a connected screen")
        let otherAirPlay = MediaDisplay(id: 5, vendor: ipadDisplay.vendor, model: 0, builtIn: false, frame: externalAbove)
        check(!otherAirPlay.isIPad && !macDisplay.isIPad, "Other Apple and AirPlay screens are not treated as an iPad")
        check(MediaDisplayPlan.targetID(in: [], fallbackID: 4, pointer: laptopPointer) == nil, "No stale screen is returned when displays are unavailable")
        let plugin = Data(#"{"config":{"shortcut":"  Choose from Menu  "}}"#.utf8)
        check(try! GrovePlan.shortcutName(in: plugin) == "Choose from Menu", "Use the widget's exact configured Connect action")
        do {
            _ = try GrovePlan.shortcutName(in: Data(#"{"config":{"shortcut":" "}}"#.utf8))
            fatalError("Missing Connect configuration must fail clearly")
        } catch {}
        let original: [[String: UInt64]] = [["source": 1, "destination": 2], ["source": 3, "destination": 4]]
        let installed: [[String: UInt64]] = [["source": 1, "destination": 100]]
        let current: [[String: UInt64]] = [["source": 1, "destination": 100], ["source": 3, "destination": 9], ["source": 8, "destination": 7]]
        let restored = NativeShortcuts.restoring(current: current, original: original, installed: installed)
        check(restored.contains(["source": 1, "destination": 2]), "Restore the original pad mapping")
        check(restored.contains(["source": 3, "destination": 9]) && restored.contains(["source": 8, "destination": 7]), "Preserve other edits made while enabled")
        let external: [[String: UInt64]] = [["source": 1, "destination": 88]]
        check(NativeShortcuts.restoring(current: external, original: original, installed: installed) == external, "Do not overwrite a newer external mapping")
        print("Native regression checks passed: current actions, HID values, limits, collision protection, migration and safe restoration.")
    }
}
