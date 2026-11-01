import AppKit
import SwiftUI

@main enum DeskRegression {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    @MainActor static func main() throws {
        let settings = try JSONDecoder().decode(PadSettings.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let native = NativePlan.build(settings)
        check(native.bindings.count == 14 && native.skipped.isEmpty, "Every existing shortcut plus desk setup and knob guide is active")
        let guide = native.bindings.first { $0.control == "Lpress" }
        check(guide?.sourceUsage == 0xc000000e2 && guide?.action.id == "grove_guide", "Only the knob's consumer mute press becomes the guide")
        check(!native.bindings.contains { ["Lcw","Lccw"].contains($0.control) }, "Volume rotation is never remapped")
        check(native.bindings.first { $0.control == "k7" }?.action.id == "grove_setup", "Physical 7 sets up the desk")
        let laptop = LaptopPlan.build(settings)
        check(laptop.count == 10 && laptop.first { $0.key == "7" }?.action.id == "grove_claude", "Existing laptop shortcuts stay unchanged")
        check(PadGuideEntry.all(settings).map(\.number) == Array(1...12), "Guide follows physical rows, including unassigned 9")
        check(PadGuideEntry.all(settings)[8].action == nil, "Key 9 remains unassigned")
        check(Set(native.bindings.map(\.relayCode)).count == 14, "Each physical control has a unique relay")
        check(NativePlan.sourceUsage(.media("vol_down")) == nil && NativePlan.sourceUsage(.media("vol_up")) == nil, "Do not claim rotation inputs")
        var full = settings
        full.controls["k9"]?.action = ActionRef(id: "tab_new")
        full.controls["Rpress"]?.action = ActionRef(id: "grove_chrome_viz")
        check(NativePlan.build(full).bindings.count == 16 && NativePlan.build(full).skipped.isEmpty, "All pad controls and both knob presses fit")
        var old = settings
        old.controls["k7"]?.action = nil; old.controls["Lpress"]?.action = nil
        let oldBindings = NativePlan.build(old).bindings
        check(zip(oldBindings, native.bindings.prefix(12)).allSatisfy { $0.control == $1.control && $0.relayCode == $1.relayCode }, "Preserve every previously working relay position")
        let mac = MediaDisplay(id:1,vendor:0x610,model:0xa050,builtIn:true,frame:CGRect(x:0,y:0,width:2056,height:1329))
        let middle = MediaDisplay(id:2,vendor:0x10ac,model:0xd0d9,builtIn:false,frame:CGRect(x:2056,y:24,width:1920,height:1080))
        let right = MediaDisplay(id:3,vendor:0x10ac,model:0xd0d9,builtIn:false,frame:CGRect(x:3976,y:161,width:1920,height:1080))
        let ipad = MediaDisplay(id:9,vendor:0x6161706c,model:0x69506164,builtIn:false,frame:CGRect(x:5896,y:0,width:1194,height:834))
        let desk = DeskPlan.build([right,ipad,mac,middle])
        check(desk.steps == [.init(displayID:1,layout:.notesChat),.init(displayID:2,layout:.code),.init(displayID:3,layout:.build)], "Use built-in identity and physical horizontal order, not enumeration order or pointer")
        check(desk.mediaDisplayID == 9, "iPad gets media, never a work layout")
        let mobile = DeskPlan.build([mac])
        check(mobile.steps == [.init(displayID:1,layout:.obsidian)] && mobile.mediaDisplayID == nil, "MacBook alone opens only Obsidian")
        let mobileIPad = DeskPlan.build([ipad,mac])
        check(mobileIPad.steps == mobile.steps && mobileIPad.mediaDisplayID == 9, "iPad does not count as an external work monitor")
        let singleExternal = DeskPlan.build([middle,mac])
        check(singleExternal.steps == [.init(displayID:1,layout:.notesChat),.init(displayID:2,layout:.code)], "One external monitor does not receive two competing layouts")
        check(DeskPlan.build([]).steps.isEmpty, "No phantom display without attached screens")
        check(DeskPlan.build([right,middle]).steps == [.init(displayID:2,layout:.code),.init(displayID:3,layout:.build)], "Closed-lid setup avoids a missing MacBook display")
        check(MediaDestination.allCases.count == 8 && MediaDestination.nba.appURL == nil, "Eight media choices keep NBA and add Apple TV")
        print("Desk regression passed: 14 controls, preserved volume/relay assignments, physical guide order, monitor topology, iPad exclusion, mobile/one-monitor fallbacks, NBA.")
        if CommandLine.arguments.count > 2 {
            _ = NSApplication.shared
            let renderer = ImageRenderer(content: PadGuideView(settings:settings).frame(width:900,height:620))
            renderer.scale = 2
            guard let cg=renderer.cgImage else { fatalError("Guide render failed") }
            try NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
            print("Rendered keypad guide")
        }
    }
}
