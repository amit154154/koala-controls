import AppKit
import ApplicationServices

/// Controls the existing player without reloading its page or changing playback time.
@MainActor enum TVPlayerFullscreen {
    enum Intent { case enter, exit }
    struct Controls { var enter:AXUIElement?;var exit:AXUIElement? }
    static func intent(_ label:String)->Intent? {
        let text=label.lowercased().trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"fullscreen",with:"full screen")
        if ["exit full screen","exit full screen (f)","leave full screen"].contains(text){return .exit}
        if ["full screen","full screen (f)","enter full screen"].contains(text){return .enter}
        return nil
    }
    static func automaticReflow(busy:Bool,fullscreen:Bool)->Bool{!busy && !fullscreen}
    static func onDisplay(_ frame:CGRect,_ display:CGRect)->Bool {
        display.contains(CGPoint(x:frame.midX,y:frame.midY)) && frame.width>=display.width*0.9 && frame.height>=display.height*0.9
    }
    static func value(_ e:AXUIElement,_ name:String)->CFTypeRef? {
        var v:CFTypeRef?;return AXUIElementCopyAttributeValue(e,name as CFString,&v) == .success ? v:nil
    }
    static func controls(_ window:AXUIElement)->Controls {
        var result=Controls(),queue:[(AXUIElement,Int,Bool)]=[(window,0,false)],index=0
        let until=Date().addingTimeInterval(0.35)
        while index<queue.count,index<900,Date()<until {
            let (element,depth,inWeb)=queue[index];index+=1
            let role=value(element,kAXRoleAttribute) as? String ?? "",web=inWeb || role=="AXWebArea"
            if web,role==kAXButtonRole {
                let label=(value(element,kAXTitleAttribute) as? String).flatMap{$0.isEmpty ? nil:$0} ?? (value(element,kAXDescriptionAttribute) as? String) ?? ""
                switch intent(label){case .enter:result.enter=element;case .exit:result.exit=element;case nil:break}
                if result.exit != nil{return result}
            }
            if depth<22,let children=value(element,kAXChildrenAttribute) as? [AXUIElement]{queue += children.map{($0,depth+1,web)}}
        }
        return result
    }
    static func isFullscreen(_ window:AXUIElement)->Bool {
        // A stale HTML label is not proof that the window fills its display.
        value(window,"AXFullScreen") as? Bool == true
    }
    private static func rect(_ e:AXUIElement)->CGRect? {
        guard let p=value(e,kAXPositionAttribute),let s=value(e,kAXSizeAttribute),CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(s)==AXValueGetTypeID() else{return nil}
        var point=CGPoint.zero,size=CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size) else{return nil}
        return CGRect(origin:point,size:size)
    }
    private static func enterPlayer(app:NSRunningApplication,window:AXUIElement) async throws {
        guard app.isActive,let button=controls(window).enter else{throw RemoteFailure.message("Bring the video player forward, then try Full screen again.")}
        // Chromium's hidden controls may report stale screen coordinates. Focus
        // the actual HTML button and activate it with a real keyboard event.
        guard AXUIElementSetAttributeValue(button,kAXFocusedAttribute as CFString,kCFBooleanTrue) == .success else{throw RemoteFailure.message("The video’s full-screen button could not receive keyboard focus.")}
        try await Task.sleep(nanoseconds:160_000_000)
        let root=AXUIElementCreateApplication(app.processIdentifier)
        let focused=value(root,kAXFocusedUIElementAttribute)
        let exact=focused.map{CFGetTypeID($0)==AXUIElementGetTypeID() && CFEqual($0,button)} ?? false
        guard app.isActive,exact || value(button,kAXFocusedAttribute) as? Bool == true else{throw RemoteFailure.message("The player’s full-screen button lost focus. Try again.")}
        for down in [true,false]{let e=CGEvent(keyboardEventSource:CGEventSource(stateID:.privateState),virtualKey:49,keyDown:down);e?.flags=[];e?.postToPid(app.processIdentifier)}
    }
    static func set(_ enabled:Bool,app:NSRunningApplication,window:AXUIElement) async throws {
        guard !app.isTerminated,AXIsProcessTrusted() else{throw RemoteFailure.message("Allow Accessibility for Mini Keyboard to control full screen.")}
        app.unhide();app.activate(options:[.activateIgnoringOtherApps]);_=AXUIElementPerformAction(window,kAXRaiseAction as CFString)
        for _ in 0..<12{if app.isActive{break};try await Task.sleep(nanoseconds:100_000_000)}
        try await Task.sleep(nanoseconds:180_000_000)
        var buttons=controls(window)
        if enabled {
            if isFullscreen(window){return}
            if buttons.enter != nil {
                try await enterPlayer(app:app,window:window)
                for _ in 0..<20{
                    try await Task.sleep(nanoseconds:150_000_000)
                    if isFullscreen(window){return}
                    buttons=controls(window)
                    if buttons.exit != nil{break}
                }
                guard buttons.exit != nil || isFullscreen(window) else{throw RemoteFailure.message("The player did not enter full screen. Playback stays in its current window.")}
            }
        } else if buttons.exit != nil {
            // Escape is Chromium’s standard, tested way to leave both HTML video
            // full screen and its Space, including a stale in-window video mode.
            guard app.isActive else{throw RemoteFailure.message("Bring the player forward to exit full screen.")}
            for down in [true,false]{let e=CGEvent(keyboardEventSource:CGEventSource(stateID:.privateState),virtualKey:53,keyDown:down);e?.flags=[];e?.postToPid(app.processIdentifier)}
            for _ in 0..<25{
                try await Task.sleep(nanoseconds:150_000_000)
                buttons=controls(window)
                if buttons.enter != nil,buttons.exit==nil{break}
            }
        }
        // Complete the native transition too, if HTML and macOS fell out of sync.
        if isFullscreen(window) != enabled {
            guard AXUIElementSetAttributeValue(window,"AXFullScreen" as CFString,enabled ? kCFBooleanTrue:kCFBooleanFalse) == .success else{throw RemoteFailure.message("This app could not change full screen.")}
        }
        for _ in 0..<30{
            try await Task.sleep(nanoseconds:150_000_000)
            if isFullscreen(window)==enabled{
                if !enabled{try await Task.sleep(nanoseconds:350_000_000)}
                return
            }
        }
        throw RemoteFailure.message("The full-screen transition did not finish. Try again in a moment.")
    }
}
