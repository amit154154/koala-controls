import AppKit

@main enum AdventureRegression {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) { checks += 1; precondition(value(),message) }
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath:CommandLine.arguments[1]), out = URL(fileURLWithPath:CommandLine.arguments[2])
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        for (a,b,corner) in [("k10","k11",WindowCorner.topLeft),("k12","k11",.topRight),("k10","k9",.bottomLeft),("k12","k9",.bottomRight)] {
            for reversed in [false,true] {
                var state=CornerChordState(); let first=reversed ? b:a, second=reversed ? a:b
                check(state.press(first)==nil,"First press waits")
                check(state.press(second) == .corner(corner),"Either order produces the correct corner")
                check(state.press(second)==nil,"Auto-repeat cannot add another corner")
                check(state.release(first)==nil && state.release(second)==nil,"Both single actions are consumed")
                check(state.press(first)==nil && state.release(first) == .single(first),"Next isolated tap still works")
            }
        }
        var three=CornerChordState(); _=three.press("k10");_=three.press("k11");check(three.press("k9")==nil,"A third key does not minimize")
        check(three.drain().isEmpty,"Consumed keys stay consumed through modifier release")
        var cancel=CornerChordState();_=cancel.press("k9");cancel.cancel();check(cancel.release("k9")==nil,"Stopping cannot fire a pending minimize")
        let buffer=CornerInput(); var emitted:[CornerTrigger]=[]; buffer.onTrigger={ emitted.append($0) }
        buffer.press("k10");buffer.release("k10");buffer.press("k11");buffer.release("k11");buffer.drain()
        check(emitted == [.corner(.topLeft)],"Short firmware pulses still combine once")
        emitted=[];buffer.press("k10");buffer.release("k10");buffer.press("k10");buffer.release("k10");buffer.drain()
        check(emitted == [.single("k10"),.single("k10")],"Rapid repeated singles are never lost")
        for l in 1...100 { for player in [false,true] {
            let threshold=AdventureRules.threshold(l,player:player)
            check(AdventureRules.level(threshold,player:player)==l,"Level threshold exact")
            if l>1 { check(AdventureRules.level(threshold-1,player:player)==l-1,"No early level up") }
        } }
        let history=out.appendingPathComponent("journal-test")
        var store:AdventureStore?=AdventureStore(directory:history);store!.padConnected={true}
        var earned:[AdventureNotice]=[]
        for n in 0..<40 {
            let id=store!.begin(action:"win_tl",name:"Top left",trigger:"10 + 11",origin:.miniKeyboard,now:Date(timeIntervalSince1970:Double(n+1000)))
            earned += store!.finish(id,success:true)
            check(store!.finish(id,success:true).isEmpty,"Duplicate completion does not award XP")
        }
        let fail=store!.begin(action:"grove_viz",name:"Koala Viz",trigger:"⌘⌥2",origin:.macKeyboard);store!.finish(fail,success:false)
        let phone=store!.begin(action:"grove_chrome_viz",name:"Koala Viz",trigger:"Phone",origin:.phone);store!.finish(phone,success:true)
        check(store!.totalClicks==42 && store!.xp==41,"Every click logged; failed requests earn no XP")
        check(store!.mastery["grove_viz"]?.uses==1,"Aliases share one function's mastery")
        check(earned.contains { $0.scope=="shortcut" && $0.level==2 && $0.unlocked=="Leaf trail" },"Function unlock is earned")
        check(earned.contains { $0.scope=="player" && $0.level==2 },"Overall level is independent")
        check(store!.tier(for:"win_tl")==2,"Function level 3 unlocks a star burst")
        let clicks=store!.totalClicks,xp=store!.xp;store=nil
        let recovered=AdventureStore(directory:history)
        check(recovered.totalClicks==clicks && recovered.xp==xp && recovered.playerLevel==2,"History restores across restart")
        let lines=try String(contentsOf:recovered.journalURL).split(separator:"\n")
        let first=try JSONSerialization.jsonObject(with:Data(lines[0].utf8)) as! [String:Any]
        let click=first["click"] as! [String:Any]
        check(click["origin"] as? String=="miniKeyboard" && click["keyboardConnected"] as? Bool==true && click["timestamp"] != nil,"Log contains time, source and connection snapshot")
        check(click["text"]==nil && click["params"]==nil,"Shortcut log excludes typed text and action parameters")
        let mode=(try FileManager.default.attributesOfItem(atPath:recovered.journalURL.path)[.posixPermissions]) as! NSNumber
        check(mode.intValue==0o600,"Journal is owner-only")
        let damaged=history.appendingPathComponent("corrupt-copy");try FileManager.default.createDirectory(at:damaged,withIntermediateDirectories:true)
        try (Data(try Data(contentsOf:recovered.journalURL))+Data("broken-tail".utf8)).write(to:damaged.appendingPathComponent("shortcut-clicks.jsonl"))
        let repaired=AdventureStore(directory:damaged);check(repaired.xp==xp && repaired.totalClicks==clicks,"A partial last write does not erase progress")
        check(CompanionSoundPicker.movementNames.count==8 && Set(CompanionSoundPicker.movementNames).isDisjoint(with:CompanionSoundPicker.reservedNames),"Movement sounds cannot contain level-up audio")
        for name in CompanionSoundPicker.movementNames + Array(CompanionSoundPicker.reservedNames) {check(NSSound(contentsOf:root.appendingPathComponent("Resources/MapleStorySounds/"+name),byReference:false) != nil,"Every required WAV decodes")}
        let now=Date();let base:[String:Any]=["id":UUID().uuidString,"kind":"corner","timestamp":now.timeIntervalSince1970]
        for corner in WindowCorner.allCases {let accepted = try RemoteCommandPolicy.validate(base.merging(["corner":corner.rawValue]){_,b in b},now:now); check(accepted=="corner","Every phone corner is allowed")}
        for bad in ["unknown","../topLeft","win_tl"] {do{_=try RemoteCommandPolicy.validate(base.merging(["corner":bad]){_,b in b},now:now);preconditionFailure("Bad corner accepted")}catch{checks+=1}}
        let settings=try JSONDecoder().decode(PadSettings.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3])))
        check(NativePlan.build(settings).bindings.count==16 && LaptopPlan.build(settings).count==11,"Every original relay and laptop shortcut survives")
        _=NSApplication.shared
        let mascot=NSImage(contentsOf:root.appendingPathComponent("Resources/koala-companion.png"))!
        let mobs=NSImage(contentsOf:root.appendingPathComponent("Resources/koala-mobs-atlas.png"))!
        let poses=NSImage(contentsOf:root.appendingPathComponent("Resources/koala-poses-atlas.png"))!
        for (corner,style) in [(WindowCorner.topLeft,CompanionStyle.topLeft),(.topRight,.topRight),(.bottomLeft,.bottomLeft),(.bottomRight,.bottomRight)] {
            check(CompanionPlan.style(actionID:corner.actionID,control:nil)==style && style.duration<=0.34,"Corner animation maps correctly and stays brief")
            for rare in [false,true] {
                let reaction=CompanionReaction(style:style,rare:rare)
                let name=style.rawValue+(rare ? "-rare":"")
                for frame in 0..<24 { try render(reaction,p:Double(frame)/23,mascot:mascot,mobs:mobs,poses:poses,to:out.appendingPathComponent("\(name)-\(frame).png")) }
            }
        }
        for tier in 1...4 {try render(CompanionReaction(style:.battle,tier:tier),p:0.5,mascot:mascot,mobs:mobs,poses:poses,to:out.appendingPathComponent("mastery-tier-\(tier).png"))}
        print("\(checks) adventure checks passed; all eight corner animations and four mastery tiers rendered.")
    }
    static func render(_ reaction:CompanionReaction,p:Double,mascot:NSImage,mobs:NSImage,poses:NSImage,to url:URL)throws{
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:480,pixelsHigh:380,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
        CompanionDrawing.draw(style:reaction.style,progress:p,reducedMotion:false,image:mascot,in:CGRect(x:0,y:0,width:480,height:380),reaction:reaction,mobs:mobs,poses:poses)
        NSGraphicsContext.restoreGraphicsState();try rep.representation(using:.png,properties:[:])!.write(to:url)
    }
}
