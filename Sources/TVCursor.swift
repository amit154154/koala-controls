import AppKit
import CoreGraphics
import Carbon

/// A TV-only pointer. It never captures clicks or changes macOS pointer preferences.
@MainActor final class TVCursor {
    private var panel: TVCursorPanel?
    private var drawing: TVCursorDrawing?
    private var timer: Timer?
    private var display: UInt32?
    private var screen: CGRect = .zero
    private var ownsHide = false
    private var lastButtons = 0
    private var lastPoint: CGPoint?
    private var movedAt: TimeInterval = 0
    private var suspended = false
    private var observers: [NSObjectProtocol] = []
    private(set) var visible = false
    private var size: CGFloat = 50
    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.suspended = true; self?.restore() } })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.suspended = false } })
        }
    }
    func start(on screen: NSScreen, size: CGFloat) {
        self.screen = screen.frame; self.display = MediaScreens.id(screen); self.size = size
        if panel == nil {
            let p = TVCursorPanel(contentRect: CGRect(x:0,y:0,width:128,height:128), styleMask:[.borderless,.nonactivatingPanel], backing:.buffered, defer:false)
            p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false;p.ignoresMouseEvents=true;p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false
            p.level=NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+4)
            p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
            p.setAccessibilityElement(false)
            let view=TVCursorDrawing(frame:CGRect(x:0,y:0,width:128,height:128));view.setAccessibilityElement(false);p.contentView=view
            panel=p;drawing=view
        }
        drawing?.pointerSize=size
        if timer == nil {
            let t=Timer(timeInterval:1.0/60.0,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            RunLoop.main.add(t,forMode:.common);timer=t
        }
        tick()
    }
    func stop() { timer?.invalidate();timer=nil;display=nil;restore() }
    private func restore() {
        panel?.orderOut(nil);visible=false;lastPoint=nil;lastButtons=0
        // Each successful hide is paired exactly once, including leaving the TV, sleep and quit.
        if ownsHide {CGDisplayShowCursor(display ?? CGMainDisplayID());ownsHide=false}
    }
    private func tick() {
        let point=NSEvent.mouseLocation
        guard let display=display,!suspended,!IsSecureEventInputEnabled(),screen.contains(point) else{restore();return}
        let buttons=NSEvent.pressedMouseButtons,now=ProcessInfo.processInfo.systemUptime
        if lastPoint != point || buttons != lastButtons {movedAt=now};lastPoint=point
        if now-movedAt>4.5 {panel?.orderOut(nil);visible=false;return}
        // Draw before hiding the system pointer, so no frame can leave the user without a pointer.
        panel?.setFrameOrigin(CGPoint(x:point.x-24,y:point.y-104));panel?.orderFrontRegardless();visible=true
        if !ownsHide {ownsHide = CGDisplayHideCursor(display) == .success}
        if buttons != 0 && lastButtons == 0 {drawing?.clickedAt=ProcessInfo.processInfo.systemUptime}
        lastButtons=buttons
        if let drawing=drawing,ProcessInfo.processInfo.systemUptime-drawing.clickedAt < 0.3 {drawing.needsDisplay=true}
    }
}
@MainActor private final class TVCursorPanel:NSPanel {
    override var canBecomeKey:Bool{false}
    override var canBecomeMain:Bool{false}
}
@MainActor final class TVCursorDrawing:NSView {
    var pointerSize:CGFloat=50 {didSet{needsDisplay=true}}
    var clickedAt:TimeInterval = -1
    override var isFlipped:Bool{true}
    override func hitTest(_ point:NSPoint)->NSView?{nil}
    override func draw(_ dirtyRect:NSRect) {
        let elapsed=ProcessInfo.processInfo.systemUptime-clickedAt
        if elapsed>=0 && elapsed<0.3 {
            let t=elapsed/0.3,r=CGFloat(12+t*25)
            NSColor(red:0.92,green:0.77,blue:0.47,alpha:1-t).setStroke()
            let ring=NSBezierPath(ovalIn:CGRect(x:24-r,y:24-r,width:r*2,height:r*2));ring.lineWidth=3;ring.stroke()
        }
        NSGraphicsContext.saveGraphicsState()
        let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.65);shadow.shadowBlurRadius=7;shadow.shadowOffset=NSSize(width:0,height:2);shadow.set()
        let s=pointerSize/50,path=NSBezierPath()
        let points:[CGPoint]=[(0,0),(0,46),(12,36),(21,54),(29,50),(20,32),(40,32)].map{CGPoint(x:24+CGFloat($0.0)*s,y:24+CGFloat($0.1)*s)}
        path.move(to:points[0]);for p in points.dropFirst(){path.line(to:p)};path.close()
        NSColor(red:0.61,green:0.84,blue:0.71,alpha:1).setFill();path.fill()
        NSColor(red:0.06,green:0.12,blue:0.10,alpha:1).setStroke();path.lineWidth=3;path.lineJoinStyle = .round;path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(red:0.96,green:0.98,blue:0.93,alpha:0.95).setStroke()
        let edge=NSBezierPath();edge.move(to:CGPoint(x:27,y:31));edge.line(to:CGPoint(x:27,y:24+37*s));edge.lineWidth=2;edge.lineCapStyle = .round;edge.stroke()
    }
}
