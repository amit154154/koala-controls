import AppKit
import Carbon

@main enum MinimizeRegression {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    static func main() throws {
        let old = try JSONDecoder().decode(PadSettings.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let new = try JSONDecoder().decode(PadSettings.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        var expected = old
        expected.controls["k9"]?.action = ActionRef(id: "win_min")
        require(new == expected, "Only button 9 changes")
        let before = NativePlan.build(old), after = NativePlan.build(new)
        require(before.bindings.count == 15 && after.bindings.count == 16 && after.skipped.isEmpty, "All sixteen controls register without displacing the knob")
        for (a,b) in zip(before.bindings, after.bindings.prefix(15)) {
            require(a.control == b.control && a.sourceUsage == b.sourceUsage && a.relayUsage == b.relayUsage && a.relayCode == b.relayCode && a.action == b.action, "Earlier hardware assignments stay identical")
        }
        require(Set(after.bindings.map(\.relayCode)).count == 16 && Set(after.bindings.map(\.sourceUsage)).count == 16, "Every input and relay is unique")
        let minimize = after.bindings.last!
        require(minimize.control == "k9" && minimize.sourceUsage == 0x70000000d && minimize.relayCode == UInt32(kVK_ANSI_KeypadEquals) && minimize.relayUsage == 0x700000067, "Key 9's learned J input uses the new relay")
        if case .keys(let key, let mods) = Actions.byID[minimize.action.id]?.kind {
            require(key == "m" && mods == ["cmd"], "Minimize uses Command-M, never Quit or Close")
        } else { fatalError("Missing minimize action") }
        require(Array(LaptopPlan.build(new).prefix(10)) == LaptopPlan.build(old) && LaptopPlan.build(new).last?.key == "P", "Earlier ten laptop shortcuts remain; P follows new minimize assignment")
        let guide = PadGuideEntry.all(new)[8]
        require(guide.title == "Minimize" && guide.artwork == "minimize", "Guide labels and illustrates key 9")
        var hotkeys: Unmanaged<CFArray>?
        if CopySymbolicHotKeys(&hotkeys) == noErr, let entries = hotkeys?.takeRetainedValue() as? [[String:Any]] {
            require(!entries.contains { ($0[kHISymbolicHotKeyCode as String] as? Int) == 81 && ($0[kHISymbolicHotKeyEnabled as String] as? Bool) == true && ($0[kHISymbolicHotKeyModifiers as String] as? Int ?? 0) == 0 }, "New relay has no enabled unmodified macOS system shortcut")
        }
        print("Minimize regression passed: 16 unique assignments; previous 15 and laptop shortcuts unchanged; key 9 sends Command-M; guide artwork present; no bare keypad-equals system conflict.")
    }
}
