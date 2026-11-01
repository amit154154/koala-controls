import AppKit
import SwiftUI

@main
enum LaptopRegression {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    @MainActor static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        var settings = try JSONDecoder().decode(PadSettings.self, from: data)
        check(!settings.laptopShortcutsEnabled, "Older settings do not silently enable global shortcuts")
        settings.laptopShortcutsEnabled = true
        let restored = try JSONDecoder().decode(PadSettings.self, from: JSONEncoder().encode(settings))
        check(restored == settings,
              "The laptop option and all assignments survive a round trip")
        let before = settings
        let bindings = LaptopPlan.build(settings)
        check(bindings.count == 10, "Seven actions plus three window positions")
        check(bindings.map(\.key) == ["1","2","3","4","5","6","7","[","]","\\"], "Use the agreed comfortable key positions")
        check(bindings.map(\.action.id) == ["grove_connect","grove_viz","grove_media","grove_write","grove_code","grove_build","grove_claude","win_left","win_max","win_right"], "Correct action for each key")
        check(bindings[6].control == "k8", "Laptop 7 uses the Claude action on pad 8")
        check(Set(bindings.map(\.keyCode)).count == 10 && bindings.allSatisfy { $0.artwork != nil }, "Every trigger is unique and has artwork")
        check(NativePlan.build(settings).bindings.count == 12, "All twelve original pad assignments remain active")
        check(settings == before, "Planning must never mutate learned inputs or actions")
        settings.vendorID = nil; settings.productID = nil
        for id in settings.controls.keys { settings.controls[id]?.source = nil }
        check(LaptopPlan.build(settings) == bindings, "Laptop bindings do not require a device or learned input")
        settings.controls["k3"]?.action = nil
        check(LaptopPlan.build(settings).count == 9, "Removing a pad action removes its laptop equivalent")
        settings.controls["k1"]?.action = ActionRef(id: "custom", params: ["code":"2"], mods: ["cmd","opt"])
        check(!LaptopPlan.build(settings).contains { $0.control == "k1" }, "Reject an output that recursively triggers another laptop shortcut")
        var hold = LaptopHoldState()
        let chord: NSEvent.ModifierFlags = [.command, .option]
        check(!hold.update(flags: .command, now: 0), "One modifier does not open the guide")
        check(!hold.update(flags: chord, now: 1), "A quick chord is quiet")
        check(!hold.update(flags: chord, now: 1.5), "No premature reminder")
        check(hold.update(flags: chord, now: 1.7), "Long hold shows the guide")
        check(!hold.update(flags: .option, now: 2), "Releasing either modifier hides it")
        check(!hold.update(flags: chord, now: 3), "A new chord starts a new delay")
        check(hold.update(flags: chord, now: 4), "A fresh chord can reopen it")
        hold.cancelUntilRelease()
        check(!hold.update(flags: chord, now: 6), "Running an action prevents the guide reappearing while still held")
        _ = hold.update(flags: [], now: 7)
        _ = hold.update(flags: chord, now: 8)
        check(hold.update(flags: chord, now: 9), "Release rearms the guide")
        check(!hold.update(flags: [.command,.option,.control], now: 10), "Other modifier combinations hide the guide")
        check(!hold.update(flags: [.command,.option,.shift], now: 11), "Shift combinations do not open it")
        print("Laptop regression passed: mappings, no-device operation, persistence, recursion prevention, hold/release/cancel behavior.")
        if CommandLine.arguments.count > 2 {
            _ = NSApplication.shared
            let renderer = ImageRenderer(content: LaptopGuideView(bindings: bindings).frame(width: 900, height: 570))
            renderer.scale = 2
            guard let cg = renderer.cgImage else { fatalError("Guide render failed") }
            let bitmap = NSBitmapImageRep(cgImage: cg)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
            print("Rendered guide preview")
        }
    }
}
