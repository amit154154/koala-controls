import AppKit
import SwiftUI

@main enum ReactionsRegression {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) { guard condition() else { fatalError(message) } }
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let original = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let settings = try JSONDecoder().decode(PadSettings.self, from: original)
        let before = try JSONSerialization.jsonObject(with: original) as! NSDictionary
        let after = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! NSDictionary
        check((before["controls"] as! NSDictionary) == (after["controls"] as! NSDictionary), "Every learned source and action survives migration")
        let physical = NativePlan.build(settings)
        check(physical.bindings.count == 16 && physical.skipped.isEmpty, "Sixteen working pad shortcuts remain")
        let laptop = LaptopPlan.build(settings)
        check(laptop.count == 11 && Set(laptop.map(\.keyCode)).count == 11, "Eleven distinct laptop shortcuts")
        check(laptop.last?.key == "P" && laptop.last?.keyCode == 35 && laptop.last?.action.id == "win_min" && laptop.last?.control == "k9", "Command-Option-P follows button 9")
        check(laptop.prefix(10).map(\.key) == ["1","2","3","4","5","6","7","[","]","\\"], "Earlier ten key combinations stay unchanged")
        var recursive = settings
        recursive.controls["k1"]?.action = ActionRef(id:"custom",params:["code":"p"],mods:["cmd","opt"])
        check(!LaptopPlan.build(recursive).contains { $0.control == "k1" }, "New trigger is covered by recursion prevention")
        var disconnected = settings
        disconnected.vendorID = nil;disconnected.productID = nil
        for id in disconnected.controls.keys {disconnected.controls[id]?.source = nil}
        check(LaptopPlan.build(disconnected) == laptop, "All eleven work without the USB pad")
        check(settings.companion.rareAnimations && settings.companion.opponent == "random", "Existing users get requested rare reactions and all opponents")
        var preferences = settings.companion
        preferences.opponent = CompanionMob.pig.rawValue;preferences.rareAnimations = false
        check(try! JSONDecoder().decode(CompanionPreferences.self, from: JSONEncoder().encode(preferences)) == preferences, "New choices persist")
        let invalid = try JSONDecoder().decode(CompanionPreferences.self, from: Data(#"{"opponent":"unknown","volume":9}"#.utf8))
        check(invalid.opponent == "random" && invalid.volume == 1, "Invalid saved choices fail safely")
        let expected: [CompanionStyle] = [.connect,.viz,.basketball,.notes,.focus,.battle,.setup,.duo,.minimize,.left,.fill,.right]
        for n in 1...12 {check(CompanionPlan.style(actionID:settings.mapping("k\(n)").action!.id,control:"k\(n)") == expected[n-1], "Each button gets its own reaction")}
        for id in ["Lcw","Lccw","Rcw","Rccw"] {check(CompanionPlan.style(actionID:"tab_next",control:id) == nil,"Rotation never creates sound or animation")}
        var selector = CompanionSelector()
        let bag = (0..<9).map { _ in selector.next(style:.battle,preferences:settings.companion,rareRoll:0.9).mob }
        check(Set(bag) == Set(CompanionMob.allCases), "All nine opponents before a repeat")
        for _ in 0..<12 {check(selector.next(style:.battle,preferences:preferences,rareRoll:0).mob == .pig,"Fixed opponent selection")}
        check(!selector.next(style:.battle,preferences:preferences,rareRoll:0).rare,"Rare toggle works")
        var rarity = CompanionSelector()
        check(rarity.next(style:.basketball,preferences:settings.companion,rareRoll:0).shot == .dunk,"Rare basketball is a dunk")
        for _ in 0..<3 {check(!rarity.next(style:.focus,preferences:settings.companion,rareRoll:0).rare,"Three normal reactions between rares")}
        check(rarity.next(style:.focus,preferences:settings.companion,rareRoll:0).rare,"Rare becomes eligible after cooldown")
        check(rarity.next(style:.basketball,preferences:preferences,rareRoll:1,shotRoll:0.1).shot == .miss,"Ordinary miss is reachable")
        check(rarity.next(style:.basketball,preferences:preferences,rareRoll:1,shotRoll:0.8).shot == .swish,"Ordinary swish is reachable")
        for style in [CompanionStyle.left,.fill,.right] {check(CompanionReaction(style:style,rare:true).duration <= 0.36,"Snap reactions stay short even when rare")}
        for screen in [CGRect(x:0,y:38,width:2056,height:1291),CGRect(x:-1920,y:-100,width:1920,height:1080),CGRect(x:3976,y:190,width:1920,height:1050)] {
            for pointer in [CGPoint(x:screen.minX,y:screen.minY),CGPoint(x:screen.maxX,y:screen.maxY),CGPoint(x:screen.midX,y:screen.midY)] {check(screen.contains(CompanionPlan.frame(pointer:pointer,visibleFrame:screen)),"Wider overlay stays on pointer display")}
        }
        var hold = LaptopHoldState()
        check(!hold.update(flags:[.command,.option],now:0),"Guide waits")
        check(hold.update(flags:[.command,.option],now:1),"Guide appears")
        hold.cancelUntilRelease();check(!hold.update(flags:[.command,.option],now:2),"Action keeps guide dismissed until release")
        print("Reaction checks passed: 16 physical / 11 laptop shortcuts, migration, recursion guard, disconnected operation, 12 distinct reactions, nine-mob shuffle, fixed selection, rare cooldown/toggle, all shot outcomes, quiet rotations and monitor edges.")
        _ = NSApplication.shared
        let output = URL(fileURLWithPath:CommandLine.arguments[3]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let mascot = NSImage(contentsOf:root.appendingPathComponent("Resources/koala-companion.png"))!
        let mobs = NSImage(contentsOf:root.appendingPathComponent("Resources/koala-mobs-atlas.png"))!
        let poses = NSImage(contentsOf:root.appendingPathComponent("Resources/koala-poses-atlas.png"))!
        var scenes: [(String,CompanionReaction)] = []
        for style in CompanionStyle.allCases {
            for rare in [false,true] { scenes.append((style.rawValue + (rare ? "-rare" : ""),CompanionReaction(style:style,rare:rare,shot:rare && style == .basketball ? .dunk : .swish))) }
        }
        scenes.append(("basketball-miss",CompanionReaction(style:.basketball,shot:.miss)))
        for mob in CompanionMob.allCases {scenes.append(("mob-"+mob.rawValue,CompanionReaction(style:.battle,mob:mob)))}
        for (name,reaction) in scenes {
            for i in 0..<40 {
                try render(reaction:reaction,p:Double(i)/39,reduced:false,mascot:mascot,mobs:mobs,poses:poses,to:output.appendingPathComponent("\(name)-\(String(format:"%02d",i)).png"))
            }
        }
        try render(reaction:CompanionReaction(style:.basketball,rare:true,shot:.dunk),p:0.5,reduced:true,mascot:mascot,mobs:mobs,poses:poses,to:output.appendingPathComponent("reduced-motion.png"))
        let renderer = ImageRenderer(content:LaptopGuideView(bindings:laptop).frame(width:900,height:570));renderer.scale=2
        if let cg=renderer.cgImage {try NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("laptop-guide.png"))}
        print("Rendered \(scenes.count) complete scene variants plus Reduce Motion and laptop guide.")
    }
    static func render(reaction:CompanionReaction,p:Double,reduced:Bool,mascot:NSImage,mobs:NSImage,poses:NSImage,to url:URL) throws {
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:480,pixelsHigh:380,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let context=NSGraphicsContext(bitmapImageRep:rep)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
        NSColor(calibratedRed:0.078,green:0.114,blue:0.094,alpha:1).setFill();CGRect(x:0,y:0,width:480,height:380).fill()
        CompanionDrawing.draw(style:reaction.style,progress:p,reducedMotion:reduced,image:mascot,in:CGRect(x:0,y:0,width:480,height:380),reaction:reaction,mobs:mobs,poses:poses)
        context.flushGraphics();NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using:.png,properties:[:])!.write(to:url)
    }
}
