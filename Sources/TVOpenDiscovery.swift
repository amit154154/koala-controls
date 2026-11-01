import AppKit
import ApplicationServices

/// Opaque IDs are the only resume target accepted from the paired phone. No URLs or paths.
struct TVOpenItem:Identifiable {
    let id:String
    let identity:String
    let title:String
    let subtitle:String
    let service:MediaDestination?
    let app:NSRunningApplication
    let window:AXUIElement?
    let chromeWindow:String?
    let chromeTab:String?
    let game:TVGame?
    var isGame:Bool{service == nil}
    var json:[String:Any]{["id":id,"title":title,"subtitle":subtitle,"service":service?.rawValue ?? "","game":isGame]}
}
struct TVBrowserTab {
    let service:MediaDestination
    let window:String
    let tab:String
    let frame:CGRect
    let title:String
    let active:Bool
    static func parse(_ line:String)->TVBrowserTab? {
        let f=line.components(separatedBy:"\t")
        guard f.count==9,let service=MediaDestination(rawValue:f[0]),validNumber(f[1]),validNumber(f[2]),let frame=frame(Array(f[3...6])),["0","1"].contains(f[8]) else{return nil}
        return TVBrowserTab(service:service,window:f[1],tab:f[2],frame:frame,title:String(f[7].prefix(240)),active:f[8]=="1")
    }
    static func validNumber(_ s:String)->Bool { !s.isEmpty && s.utf8.count<20 && s.utf8.allSatisfy{(48...57).contains($0)} && UInt64(s).map{$0>0} == true }
    static func frame(_ fields:[String])->CGRect? {
        guard fields.count==4 else{return nil};let n=fields.compactMap(Double.init)
        guard n.count==4,n.allSatisfy({$0.isFinite && abs($0)<100000}),n[2]>n[0],n[3]>n[1] else{return nil}
        return CGRect(x:n[0],y:n[1],width:n[2]-n[0],height:n[3]-n[1])
    }
}
@MainActor final class TVOpenDiscovery {
    private var previous:[TVOpenItem]=[]
    func scan(games:[TVGame]) async -> (items:[TVOpenItem],note:String?) {
        var found:[TVOpenItem]=[]
        func append(identity:String,title:String,subtitle:String,service:MediaDestination?,app:NSRunningApplication,window:AXUIElement?=nil,chromeWindow:String?=nil,chromeTab:String?=nil,game:TVGame?=nil) {
            let old=previous.first{item in item.identity==identity || (window != nil && item.window != nil && item.app.processIdentifier==app.processIdentifier && CFEqual(item.window!,window!))}
            found.append(TVOpenItem(id:old?.id ?? UUID().uuidString,identity:identity,title:title,subtitle:subtitle,service:service,app:app,window:window,chromeWindow:chromeWindow,chromeTab:chromeTab,game:game))
        }
        if AXIsProcessTrusted() {
            for service in MediaDestination.allCases {
                guard let url=service.appURL,let id=Bundle(url:url)?.bundleIdentifier else{continue}
                for app in NSRunningApplication.runningApplications(withBundleIdentifier:id) where !app.isTerminated {
                    for window in Self.windows(app) {
                        let title=(Self.value(window,kAXTitleAttribute) as? String)?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
                        append(identity:"app:\(app.processIdentifier):\(CFHash(window))",title:title.isEmpty ? service.title:title,subtitle:service.title+" · Open app",service:service,app:app,window:window)
                    }
                }
            }
        }
        var note:String?
        if let chrome=NSRunningApplication.runningApplications(withBundleIdentifier:"com.google.Chrome").first,let script=Bundle.main.url(forResource:"TVOpenMedia",withExtension:"applescript") {
            do {
                let listing=try await ActionProcess.run("/usr/bin/osascript",[script.path,"list"],timeout:12)
                let tabs=listing.components(separatedBy:.newlines).compactMap(TVBrowserTab.parse).sorted{$0.active && !$1.active}
                let native=found;found=[]
                for tab in tabs {
                    // Chrome's scripting API also lists PWA windows, but their AX owner is
                    // the web-app process. Keep that native owner when the geometry matches.
                    let owner=native.first{item in
                        guard tab.active,tab.service==item.service,let window=item.window,let frame=WindowSnapper.shared.frame(of:window) else{return false}
                        return abs(tab.frame.minX-frame.minX)<8 && abs(tab.frame.minY-frame.minY)<100 && abs(tab.frame.width-frame.width)<8 && abs(tab.frame.height-frame.height)<110
                    }
                    if let item=owner {append(identity:item.identity,title:tab.title.isEmpty ? item.title:tab.title,subtitle:tab.service.title+" · Open app",service:tab.service,app:item.app,window:item.window)}
                    else {append(identity:"tab:\(chrome.processIdentifier):\(tab.tab)",title:tab.title.isEmpty ? tab.service.title:tab.title,subtitle:tab.service.title+" · Chrome tab",service:tab.service,app:chrome,chromeWindow:tab.window,chromeTab:tab.tab)}
                }
                found += native.filter{item in !found.contains{found in
                    guard let a=item.window,let b=found.window else{return false}
                    return item.app.processIdentifier==found.app.processIdentifier && CFEqual(a,b)
                }}
            } catch {note="Chrome tabs unavailable. Allow Mini Keyboard → Google Chrome in System Settings → Privacy & Security → Automation, then refresh."}
        }
        // RPCS3 is read through window-server metadata only, avoiding Qt accessibility calls.
        // Resume activates the existing process; it never boots a game or changes emulator state.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier:"net.rpcs3.rpcs3") where !app.isTerminated {
            let windows=(CGWindowListCopyWindowInfo([.optionAll,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []).filter{($0[kCGWindowOwnerPID as String] as? Int)==Int(app.processIdentifier) && ($0[kCGWindowLayer as String] as? Int)==0}
            let names=windows.compactMap{$0[kCGWindowName as String] as? String}.filter{!$0.isEmpty}
            let game=games.first{g in names.contains{title in title.contains(g.id) || title.localizedCaseInsensitiveContains(g.title)}}
            append(identity:"game:\(app.processIdentifier)",title:game?.title ?? "RPCS3 · Open session",subtitle:game == nil ? "RPCS3 is already open":"Return to your running game",service:nil,app:app,game:game)
        }
        // Keep IDs stable across refreshes; no browsing data is written to disk.
        previous=found;return(found,note)
    }
    static func windows(_ app:NSRunningApplication)->[AXUIElement] {
        let element=AXUIElementCreateApplication(app.processIdentifier);AXUIElementSetMessagingTimeout(element,0.4)
        return (value(element,kAXWindowsAttribute) as? [AXUIElement] ?? []).filter{w in
            value(w,kAXSubroleAttribute) as? String == kAXStandardWindowSubrole && WindowSnapper.shared.frame(of:w) != nil
        }
    }
    static func value(_ element:AXUIElement,_ key:String)->CFTypeRef? {var v:CFTypeRef?;return AXUIElementCopyAttributeValue(element,key as CFString,&v) == .success ? v:nil}
    func place(tab:String,service:MediaDestination,app:NSRunningApplication,window:AXUIElement,frame:CGRect) async throws {
        guard !app.isTerminated,let script=Bundle.main.url(forResource:"TVOpenMedia",withExtension:"applescript") else{throw RemoteFailure.message("This Chrome media window closed.")}
        if Self.value(window,"AXFullScreen") as? Bool == true {
            guard AXUIElementSetAttributeValue(window,"AXFullScreen" as CFString,kCFBooleanFalse) == .success else{throw RemoteFailure.message("Exit Chrome full screen, then try Resume again.")}
            for _ in 0..<60 {try await Task.sleep(nanoseconds:100_000_000);if Self.value(window,"AXFullScreen") as? Bool != true{break}}
        }
        let target=WindowSnapper.shared.flip(frame)
        let bounds=[target.minX,target.minY,target.maxX,target.maxY].map{String(Int($0.rounded()))}
        for _ in 0..<3 {
            _=try await ActionProcess.run("/usr/bin/osascript",[script.path,"place","0",tab,service.rawValue]+bounds,timeout:12)
            try await Task.sleep(nanoseconds:250_000_000)
            if let actual=WindowSnapper.shared.frame(of:window),abs(actual.minX-target.minX)<6,abs(actual.minY-target.minY)<6,abs(actual.width-target.width)<6,abs(actual.height-target.height)<6{return}
        }
        let actual=WindowSnapper.shared.frame(of:window).map(NSStringFromRect) ?? "unavailable"
        // Bounded diagnostics contain geometry only, never URLs, page content or browsing history.
        let diagnostic=["target":NSStringFromRect(target),"actual":actual]
        let url=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Mini Keyboard/tv-placement-status.json")
        if let data=try? JSONSerialization.data(withJSONObject:diagnostic,options:.sortedKeys){try? data.write(to:url,options:.atomic)}
        throw RemoteFailure.message("Chrome could not fit the TV layout. Its previous position was restored. Try a larger display or Focus one.")
    }
    private func revealChromeWindow(_ app:NSRunningApplication,title:String) async {
        // Native Window-menu selection follows the window into its Space, unlike setting
        // Chrome's AppleScript index when automatic application Space switching is disabled.
        let element=AXUIElementCreateApplication(app.processIdentifier)
        guard let bar=WindowSnapper.shared.element(element,kAXMenuBarAttribute) else{return}
        func children(_ e:AXUIElement)->[AXUIElement]{Self.value(e,kAXChildrenAttribute) as? [AXUIElement] ?? []}
        guard let menu=children(bar).first(where:{Self.value($0,kAXTitleAttribute) as? String == "Window"}) else{return}
        guard AXUIElementPerformAction(menu,kAXPressAction as CFString) == .success else{return}
        defer{_=AXUIElementPerformAction(menu,kAXCancelAction as CFString)}
        try? await Task.sleep(nanoseconds:150_000_000)
        let items=children(menu).flatMap{children($0)}.filter{item in
            guard let name=Self.value(item,kAXTitleAttribute) as? String,!title.isEmpty else{return false}
            return name==title || name.hasPrefix(title)
        }
        guard items.count==1 else{return}
        _=AXUIElementPerformAction(items[0],kAXPressAction as CFString)
        try? await Task.sleep(nanoseconds:400_000_000)
    }
    func resolve(_ item:TVOpenItem) async throws -> (NSRunningApplication,AXUIElement) {
        guard !item.app.isTerminated else{throw RemoteFailure.message("This app closed. Refresh Continue watching.")}
        guard let tab=item.chromeTab,let window=item.chromeWindow,let service=item.service else{
            guard let w=item.window,WindowSnapper.shared.frame(of:w) != nil else{throw RemoteFailure.message("This media window closed. Refresh Continue watching.")};return(item.app,w)
        }
        guard let script=Bundle.main.url(forResource:"TVOpenMedia",withExtension:"applescript") else{throw RemoteFailure.message("The media resume action is missing.")}
        let result=try await ActionProcess.run("/usr/bin/osascript",[script.path,"select",window,tab,service.rawValue],timeout:12)
        let fields=result.trimmingCharacters(in:.whitespacesAndNewlines).components(separatedBy:"\t")
        guard fields.count==7,let count=Int(fields[1]),count>0 else{throw RemoteFailure.message("Chrome could not select this media tab. Refresh and try again.")}
        if count>1 {try await MediaTiling.shared.detachChromeTab(in:item.app)}
        let location=try await ActionProcess.run("/usr/bin/osascript",[script.path,"locate",window,tab,service.rawValue],timeout:12)
        let f=location.trimmingCharacters(in:.whitespacesAndNewlines).components(separatedBy:"\t")
        guard f.count==7,let frame=TVBrowserTab.frame(Array(f[2...5])) else{throw RemoteFailure.message("The resumed tab did not expose a window.")}
        let application=NSRunningApplication.runningApplications(withBundleIdentifier:"com.google.Chrome").first(where:{$0.isActive}) ?? item.app
        let element=AXUIElementCreateApplication(application.processIdentifier);AXUIElementSetMessagingTimeout(element,1)
        func normalized(_ text:String)->String {text.components(separatedBy:.whitespacesAndNewlines).filter{!$0.isEmpty}.joined(separator:" ")}
        let title=normalized(f[6])
        var observed:[CGRect]=[]
        for attempt in 0..<30 {
            if attempt==3 {await revealChromeWindow(application,title:f[6])}
            // Chrome can briefly report old coordinates while changing display or Space.
            // The selected tab's unique title can identify its window during that transition.
            let focused=[WindowSnapper.shared.element(element,kAXFocusedWindowAttribute),WindowSnapper.shared.element(element,kAXMainWindowAttribute)].compactMap{$0}
            var all:[AXUIElement]=[]
            for window in focused+(Self.value(element,kAXWindowsAttribute) as? [AXUIElement] ?? []) where WindowSnapper.shared.frame(of:window) != nil {
                if !all.contains(where:{CFEqual($0,window)}){all.append(window)}
            }
            let named=all.filter{w in !title.isEmpty && normalized(Self.value(w,kAXTitleAttribute) as? String ?? "").contains(title)}
            if named.count==1 {return(application,named[0])}
            let candidates=all.filter{w in
                guard let actual=WindowSnapper.shared.frame(of:w) else{return false}
                return abs(actual.minX-frame.minX)<8 && abs(actual.minY-frame.minY)<100 && abs(actual.width-frame.width)<8 && abs(actual.height-frame.height)<110
            }
            if let exact=candidates.first(where:{w in named.contains{CFEqual($0,w)}}){return(application,exact)}
            if candidates.count==1 {return(application,candidates[0])}
            observed=all.compactMap{WindowSnapper.shared.frame(of:$0)}
            try await Task.sleep(nanoseconds:100_000_000)
        }
        let diagnostic:[String:Any]=["expected":NSStringFromRect(frame),"windows":observed.map(NSStringFromRect),"pid":application.processIdentifier]
        let url=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Mini Keyboard/tv-resolve-status.json")
        if let data=try? JSONSerialization.data(withJSONObject:diagnostic,options:.sortedKeys){try? data.write(to:url,options:.atomic)}
        throw RemoteFailure.message("Chrome’s media window is not ready. Refresh and try Resume again.")
    }
}
