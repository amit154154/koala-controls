import AppKit
import CoreGraphics

/// One launch per physical connection. Ending TV stays ended until the TV reconnects.
struct TVConnectionPolicy {
    private(set) var connected=false
    private(set) var handled=false
    mutating func update(present:Bool,enabled:Bool,busy:Bool)->Bool {
        if !present {connected=false;handled=false;return false}
        connected=true
        guard enabled,!handled,!busy else{return false}
        handled=true;return true
    }
    mutating func suppress(){handled=true}
    mutating func retry(){handled=false}
}

enum TVDisplayIdentity {
    static func uuid(_ id:CGDirectDisplayID)->String? {CGDisplayCreateUUIDFromDisplayID(id).map{CFUUIDCreateString(nil,$0.takeRetainedValue()) as String}}
    static func id(_ screen:NSScreen)->CGDirectDisplayID?{(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value}
    static func screen(_ uuid:String)->NSScreen? {NSScreen.screens.first{s in guard let id=id(s) else{return false};return Self.uuid(id)==uuid && CGDisplayIsBuiltin(id)==0 && CGDisplayIsInMirrorSet(id)==0}}
    static func blankIDs(tv:CGDirectDisplayID,displays:[(id:CGDirectDisplayID,builtIn:Bool,main:Bool,mirrored:Bool)])->[CGDirectDisplayID] {
        guard displays.contains(where:{$0.id==tv && !$0.builtIn && !$0.mirrored}) else{return []}
        let builtIn=displays.filter{$0.builtIn && $0.id != tv && !$0.mirrored}.map(\.id)
        return builtIn.isEmpty ? displays.filter{$0.main && $0.id != tv && !$0.mirrored}.map(\.id):builtIn
    }
}

/// A reversible black cover, never a display power/brightness or arrangement change.
@MainActor final class TVMacScreenCover {
    private var panels:[CGDirectDisplayID:NSPanel]=[:]
    var coveredIDs:[CGDirectDisplayID]{panels.keys.sorted()}
    func show(ids:[CGDirectDisplayID],reveal:@escaping()->Void){
        for id in Array(panels.keys) where !ids.contains(id){panels.removeValue(forKey:id)?.orderOut(nil)}
        for id in ids {
            guard let screen=NSScreen.screens.first(where:{TVDisplayIdentity.id($0)==id}) else{continue}
            let p:NSPanel
            if let existing=panels[id]{p=existing}else{
                p=NSPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
                p.title="Koala TV — Mac screen blanked";p.backgroundColor = .black;p.isOpaque=true;p.hasShadow=false;p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false
                p.level=NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+1)
                p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
                let view=TVBlackCoverView(frame:CGRect(origin:.zero,size:screen.frame.size));view.reveal=reveal;p.contentView=view;panels[id]=p
            }
            p.setFrame(screen.frame,display:true);p.orderFrontRegardless()
        }
    }
    func hide(){for p in panels.values{p.orderOut(nil)};panels.removeAll()}
}

@MainActor private final class TVBlackCoverView:NSView {
    var reveal:(()->Void)?
    override var isOpaque:Bool{true}
    override func draw(_ dirtyRect:NSRect){NSColor.black.setFill();bounds.fill()}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool{true}
    override func mouseDown(with event:NSEvent){reveal?()}
    override func rightMouseDown(with event:NSEvent){reveal?()}
    override func isAccessibilityElement()->Bool{true}
    override func accessibilityRole()->NSAccessibility.Role?{.button}
    override func accessibilityLabel()->String?{"Mac screen is blank for Koala TV. Click to show the Mac screen."}
    override func accessibilityPerformPress()->Bool{reveal?();return true}
}
