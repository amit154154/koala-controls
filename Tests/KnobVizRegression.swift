import AppKit

@main enum KnobVizRegression {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    static func main() throws {
        let old = try JSONDecoder().decode(PadSettings.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let updated = try JSONDecoder().decode(PadSettings.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        var expected = old
        expected.controls["Rpress"]?.action = ActionRef(id: "grove_chrome_viz")
        check(updated == expected, "Only the tab knob's press assignment changes")
        let before = NativePlan.build(old)
        let after = NativePlan.build(updated)
        check(before.bindings.count == 14 && after.bindings.count == 15 && after.skipped.isEmpty, "All fifteen assignments fit")
        for (a,b) in zip(before.bindings, after.bindings.prefix(14)) {
            check(a.control == b.control && a.sourceUsage == b.sourceUsage && a.relayUsage == b.relayUsage && a.relayCode == b.relayCode && a.action == b.action, "Existing fourteen mappings stay identical")
        }
        let press = after.bindings.last!
        check(press.control == "Rpress" && press.sourceUsage == 0x700000022 && press.relayUsage == 0x700000085 && press.relayCode == 95, "Learned knob input maps to its own safe relay")
        check(Set(after.bindings.map(\.relayCode)).count == 15 && Set(after.bindings.map(\.relayUsage)).count == 15, "No duplicate relay keys")
        check(!after.bindings.contains { [0x44,0x69,0x6a].contains($0.relayUsage & 0xff) }, "Exclude Show Desktop and brightness keys")
        check(GrovePlan.chromeVizAllowed(frontmostBundleID: "com.google.Chrome"), "Chrome accepts the knob press")
        for app in [nil, "com.microsoft.VSCode", "com.apple.Safari", "local.minikeyboard.app"] {
            check(!GrovePlan.chromeVizAllowed(frontmostBundleID: app), "Other apps ignore the Chrome-only action")
        }
        let a = LaptopPlan.build(old), b = LaptopPlan.build(updated)
        check(a.count == 10 && b.count == 10, "Ten laptop shortcuts remain")
        for (x,y) in zip(a,b) { check(x.key == y.key && x.action == y.action, "Laptop assignments unchanged") }
        check(updated.mapping("Lpress").action?.id == "grove_guide", "Volume knob press still opens the guide")
        check(updated.mapping("k2").action?.id == "grove_viz", "Button 2 keeps its general action")
        check(CompanionPlan.style(actionID: "grove_chrome_viz", control: "Rpress") == .viz, "New press uses the Viz reaction")
        for control in ["Rcw","Rccw","Lcw","Lccw"] {
            check(CompanionPlan.style(actionID: "tab_next", control: control) == nil, "Rotations remain quiet")
        }
        print("Knob regression passed: fifteen unique relays, fourteen preserved mappings, Chrome-only guard, unchanged laptop shortcuts/guide/volume/tab rotations, and common press reaction.")
    }
}
