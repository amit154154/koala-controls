import AppKit

@main enum CompanionRegression {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let original = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let settings = try JSONDecoder().decode(PadSettings.self, from: original)
        check(settings.companion.sound && settings.companion.animationEnabled && settings.companion.volume == 0.55, "Old settings enable requested feedback at a quiet volume")
        let before = try JSONSerialization.jsonObject(with: original) as! NSDictionary
        let after = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! NSDictionary
        check((before["controls"] as! NSDictionary) == (after["controls"] as! NSDictionary), "Migration preserves every action and learned source")
        check(NativePlan.build(settings).bindings.count == 14 && LaptopPlan.build(settings).count == 10, "All physical and laptop shortcuts survive")
        var changed = settings
        changed.companion.sound = false; changed.companion.animationEnabled = false; changed.companion.volume = 0.23
        check(try! JSONDecoder().decode(PadSettings.self, from: JSONEncoder().encode(changed)) == changed, "All feedback preferences persist")
        let high = try JSONDecoder().decode(CompanionPreferences.self, from: Data("{\"volume\":22}".utf8))
        let low = try JSONDecoder().decode(CompanionPreferences.self, from: Data("{\"volume\":-3}".utf8))
        check(high.volume == 1 && low.volume == 0, "Clamp saved volume to the valid sound range")
        for control in ["Lccw","Lcw","Rccw","Rcw"] {
            check(CompanionPlan.style(actionID: "tab_next", control: control) == nil, "Rotations stay quiet")
        }
        check(CompanionPlan.style(actionID: "grove_guide", control: "Lpress") == .guide, "Knob press gets the map reaction")
        for (action, expected) in [("win_left",CompanionStyle.left),("win_max",.fill),("win_right",.right)] {
            check(CompanionPlan.style(actionID:action, control:nil) == expected, "Laptop and pad window actions share the correct directional style")
            check(expected.duration < CompanionStyle.hop.duration && expected.duration <= 0.36, "Bottom row reactions are shorter")
        }
        check(CompanionPlan.style(actionID: "disable", control: "k9") == nil, "Unassigned/disabled actions make no noise")
        for screen in [CGRect(x:0,y:38,width:2056,height:1291), CGRect(x:-1920,y:-100,width:1920,height:1080), CGRect(x:3976,y:190,width:1920,height:1050)] {
            for pointer in [CGPoint(x:screen.minX,y:screen.minY),CGPoint(x:screen.maxX,y:screen.maxY),CGPoint(x:screen.midX,y:screen.midY)] {
                check(screen.contains(CompanionPlan.frame(pointer:pointer,visibleFrame:screen)), "Keep the entire overlay on the pointer's display at every edge")
            }
        }
        let image = NSImage(contentsOf: root.appendingPathComponent("Resources/koala-companion.png"))!
        check(NSSound(contentsOf:root.appendingPathComponent("Resources/koala-pop.wav"),byReference:false) != nil, "Bundled sound loads")
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        // Render exactly the live drawing code, enlarged only for visual inspection.
        for style in CompanionStyle.allCases {
            for frame in 0..<36 {
                let p = Double(frame) / 35
                try render(image: image, style: style, progress:p, reduced:false, to:output.appendingPathComponent("\(style.rawValue)-\(String(format:"%02d",frame)).png"))
            }
        }
        try render(image:image,style:.hop,progress:0.5,reduced:true,to:output.appendingPathComponent("reduced-motion.png"))
        print("Companion checks passed: settings migration/persistence, all 24 shortcuts, quiet rotations, correct/faster directional styles, monitor-edge placement, audio loading, exact animation frame renders.")
    }
    static func render(image: NSImage, style: CompanionStyle, progress: Double, reduced: Bool, to url: URL) throws {
        let size = CGSize(width:368,height:320)
        let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width),pixelsHigh:Int(size.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let context = NSGraphicsContext(bitmapImageRep:rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=context
        NSColor(red:0.078,green:0.114,blue:0.094,alpha:1).setFill()
        CGRect(origin:.zero,size:size).fill()
        CompanionDrawing.draw(style:style,progress:progress,reducedMotion:reduced,image:image,in:CGRect(origin:.zero,size:size))
        context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using:.png,properties:[:])!.write(to:url)
    }
}
