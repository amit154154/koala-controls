import AppKit
import SwiftUI

/// Render this project's own SwiftUI guides offscreen. Never shows windows or
/// starts HID mapping, networking, media playback, or changes another app.
@main struct KoalaScreenshots {
    @MainActor static func main() throws {
        _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        let output=URL(fileURLWithPath:CommandLine.arguments[1])
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var settings=PadSettings.defaults()
        settings.controls["Lccw"]?.source = .media("vol_down")
        settings.controls["Lcw"]?.source = .media("vol_up")
        try save(PadGuideView(settings:settings).frame(width:900,height:780),to:output.appendingPathComponent("mini-keyboard.png"))
        try save(LaptopGuideView(bindings:LaptopPlan.build(settings)).frame(width:900,height:570),to:output.appendingPathComponent("macbook-guide.png"))
        print("Rendered current guides using public starter actions.")
    }
    @MainActor static func save<V:View>(_ view:V,to path:URL)throws {
        let renderer=ImageRenderer(content:view);renderer.scale=2
        guard let image=renderer.cgImage,let data=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else{throw NSError(domain:"KoalaScreenshot",code:1)}
        try data.write(to:path)
    }
}
