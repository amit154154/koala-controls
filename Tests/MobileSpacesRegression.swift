import AppKit

@main enum MobileSpacesRegression {
    static func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let settingsData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let settings = try JSONDecoder().decode(PadSettings.self, from: settingsData)
        let before = try JSONSerialization.jsonObject(with: settingsData) as! NSDictionary
        let after = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! NSDictionary
        check(before["controls"] as! NSDictionary == after["controls"] as! NSDictionary, "Assignments and learned keys survive unchanged")
        check(NativePlan.build(settings).bindings.count == 16, "All pad bindings remain")
        check(LaptopPlan.build(settings).count == 11, "All laptop bindings remain")

        let mac = MediaDisplay(id:1,vendor:0x610,model:1,builtIn:true,frame:CGRect(x:0,y:0,width:1512,height:982))
        let ipad = MediaDisplay(id:2,vendor:0x6161706c,model:0x69506164,builtIn:false,frame:CGRect(x:-1000,y:-400,width:1000,height:1300))
        let dell = MediaDisplay(id:3,vendor:0x10ac,model:1,builtIn:false,frame:CGRect(x:1512,y:0,width:1920,height:1080))
        check(MobileSpacePlan.displayID(in:[mac]) == 1, "MacBook alone uses native Spaces")
        check(MobileSpacePlan.displayID(in:[ipad,mac]) == 1, "Sidecar still uses MacBook for workspaces")
        for displays in [[mac,dell],[ipad,mac,dell],[dell],[ipad],[]] {
            check(MobileSpacePlan.displayID(in:displays) == nil, "Desk, closed lid, and missing MacBook do not trigger mobile Spaces")
        }
        check(DeskPlan.build([mac,ipad]).steps == [.init(displayID:1,layout:.obsidian)], "Button 7 keeps its original mobile behavior")
        check(MediaDisplayPlan.targetID(in:[mac,ipad],fallbackID:1,pointer:.zero) == 2, "Media still prefers Sidecar")
        let screen = CGRect(x:0,y:0,width:1512,height:982)
        let left = CGRect(x:0,y:38,width:752,height:944), right = CGRect(x:760,y:38,width:752,height:944)
        check(MobileSpacePlan.isSplit(left:left,right:right,screen:screen), "Native divider and menu-bar offsets accepted")
        check(MobileSpacePlan.isSplit(left:CGRect(x:0,y:39,width:1026,height:1290),
                                     right:CGRect(x:1038,y:120,width:1018,height:1209),
                                     screen:CGRect(x:0,y:0,width:2056,height:1329)), "Verified Chrome Split View toolbar inset is accepted")
        check(!MobileSpacePlan.isSplit(left:screen,right:screen,screen:screen), "Two separate fullscreen Spaces never count as Split View")
        check(!MobileSpacePlan.isSplit(left:right,right:left,screen:screen), "Reversed pairs do not count as requested layout")

        for display in [screen,ipad.frame,CGRect(x:-1920,y:100,width:1920,height:1080)] {
            for x in stride(from:display.minX,through:display.maxX,by:80) {
                for y in stride(from:display.minY,through:display.maxY,by:80) {
                    let pointer = CGPoint(x:x,y:y), size = CGSize(width:320,height:310)
                    guard let frame = CompanionPlan.frameBesideMenu(pointer:pointer,menuSize:size,visibleFrame:display) else { fatalError("Room for menu and animation on normal display") }
                    let menuX = min(max(x,display.minX),display.maxX-size.width)
                    let column = CGRect(x:menuX-24,y:display.minY,width:size.width+48,height:display.height)
                    check(display.contains(frame) && !frame.intersects(column), "Animation clears popup across all edges and negative display coordinates")
                }
            }
        }
        check(CompanionPlan.frameBesideMenu(pointer:.zero,menuSize:CGSize(width:320,height:300),visibleFrame:CGRect(x:0,y:0,width:400,height:700)) == nil, "Narrow screen favors readable chooser")

        var picker = CompanionSoundPicker()
        var previous: Int?
        for _ in 0..<100 {
            var cycle: Set<Int> = []
            for _ in 0..<14 {
                let next = picker.next(count:14)!
                check(previous != next, "No repeat at bag boundaries")
                cycle.insert(next); previous = next
            }
            check(cycle.count == 14, "All fourteen effects play once per shuffle")
        }
        check(picker.next(count:0) == nil && picker.next(count:1) == 0 && picker.next(count:1) == 0, "Empty and single-sound libraries handled")
        let urls = try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("Resources/MapleStorySounds"),includingPropertiesForKeys:nil).filter { $0.pathExtension == "wav" }
        check(urls.count == 14, "Entire requested set bundled")
        for url in urls { check(NSSound(contentsOf:url,byReference:false) != nil, "Every sound decodes in AppKit") }
        let packaged = CompanionSoundPicker.urls(in:Bundle(url:URL(fileURLWithPath:CommandLine.arguments[3]))!)
        check(packaged.count == 14, "Installed app discovers all bundled sounds, not just old fallback")
        print("PASS: preserved 16 pad/11 laptop mappings; mobile/desk/Sidecar routing; split geometry; menu-edge placement grid; 1,400 shuffled sounds; all 14 WAV files decode and bundle correctly.")
    }
}
