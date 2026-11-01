import AppKit
import SwiftUI
import ApplicationServices
import IOKit.pwr_mgt
import IOKit.ps
import Carbon
import ServiceManagement

/// TV shares the existing signed host and paired-phone boundary. No new input driver.
@MainActor final class TVMode: ObservableObject {
    static let shared = TVMode()
    @Published var active = false
    @Published var homeVisible = false
    @Published var busy = false
    @Published var settingsVisible = false
    @Published var selected = "media:youtube"
    @Published var lastError = false
    @Published var message = "Pick a little downtime."
    @Published var games: [TVGame] = []
    @Published var controllers: [TVControllerInfo] = []
    @Published var openItems:[TVOpenItem]=[]
    @Published var scanningOpen=false
    @Published var openScanNote:String?
    private let openDiscovery=TVOpenDiscovery()
    private var lastOpenScan=Date.distantPast

    @Published var screenName = "Mac display"
    @Published var currentTitle = "Nothing playing yet"
    @Published var powerConnected = false
    @Published var targetID: UInt32?
    private var window: TVWindow?
    private var desk: NSWindow?
    private var avPanel:NSPanel?
    private var deskDelegate: TVDeskDelegate?
    private let tvCursor = TVCursor()
    @Published var controlsVisible = false
    @Published var cursorEnabled = UserDefaults.standard.object(forKey:"koalaTVCursor") as? Bool ?? true {
        didSet { defaults.set(cursorEnabled,forKey:"koalaTVCursor");updateCursor() }
    }
    @Published var cursorLarge = UserDefaults.standard.object(forKey:"koalaTVCursorLarge") as? Bool ?? false {
        didSet {defaults.set(cursorLarge,forKey:"koalaTVCursorLarge");updateCursor()}
    }
    var availableDisplays: [NSScreen] { NSScreen.screens.filter { s in !MediaScreens.displays().contains { $0.id == MediaScreens.id(s) && $0.isIPad } } }
    var targetIsBuiltIn: Bool { MediaScreens.displays().contains { $0.id == targetID && $0.builtIn } }
    private var builtInScreen: NSScreen? { NSScreen.screens.first { s in MediaScreens.displays().contains { $0.id == MediaScreens.id(s) && $0.builtIn } } }
    private var savedAppIcon: NSImage?

    private var awake: IOPMAssertionID = 0
    private var systemAwake: IOPMAssertionID = 0
    private var timer: Timer?
    private var mediaWindows: [String: (NSRunningApplication, AXUIElement)] = [:]
    private var current: (NSRunningApplication, AXUIElement)?
    private var mediaTabs:[String:String]=[:]
    @Published var session: [MediaDestination] = []
    /// A running RPCS3 game window that shares the TV with the media session.
    private var game:(NSRunningApplication,AXUIElement)?
    @Published private(set) var gameTitle:String?
    @Published private(set) var fullscreen = false
    private var arrangedScreenFrame:CGRect?
    private var fullscreenTransition=false
    private var sharingBeforeFullscreen=true
    private var playerTimer:Timer?
    @Published var sharing = true
    @Published var focusedService: MediaDestination?
    private var rail: TVRailPanel?
    private var observer: NSObjectProtocol?
    private var displayTask:Task<Void,Never>?
    private var workspaceObservers:[NSObjectProtocol]=[]
    private var displayWatching=false
    private var connectionPolicy=TVConnectionPolicy()
    private let macCover=TVMacScreenCover()
    private var macRevealed=false
    private var sleeping=false
    @Published private(set) var macScreenBlanked=false
    @Published private(set) var automaticTVName="Your TV"
    @Published private(set) var automaticTVUUID=""
    @Published var automaticTVEnabled=false {didSet{if displayWatching{defaults.set(automaticTVEnabled,forKey:"koalaTVAutomaticEnabled");scheduleDisplayCheck()}}}
    @Published var automaticallyBlankMac=true {didSet{if displayWatching{defaults.set(automaticallyBlankMac,forKey:"koalaTVAutomaticallyBlankMac");macRevealed=false;updateMacCover()}}}

    private let defaults = UserDefaults.standard
    var rows: [[String]] {
        let media=MediaDestination.allCases.map { "media:"+$0.rawValue }
        return (openItems.isEmpty ? []:[openItems.map{"open:"+$0.id}]) + (targetIsBuiltIn ? [Array(media.prefix(4)),Array(media.dropFirst(4))]:[media]) + [["share","resume","av","setup","exit"],games.map {"game:"+$0.id}]
    }
    init() {
        let configured=Bundle.main.url(forResource:"TVAutoDisplay",withExtension:"plist").flatMap{try? Data(contentsOf:$0)}.flatMap{try? PropertyListSerialization.propertyList(from:$0,format:nil) as? [String:Any]} ?? [:]
        automaticTVUUID=defaults.string(forKey:"koalaTVAutomaticDisplayUUID") ?? configured["displayUUID"] as? String ?? ""
        automaticTVName=defaults.string(forKey:"koalaTVAutomaticDisplayName") ?? configured["displayName"] as? String ?? "Your TV"
        automaticTVEnabled=defaults.object(forKey:"koalaTVAutomaticEnabled") as? Bool ?? configured["automatic"] as? Bool ?? false
        automaticallyBlankMac=defaults.object(forKey:"koalaTVAutomaticallyBlankMac") as? Bool ?? configured["blankMac"] as? Bool ?? true
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.displaysChanged() } }
    }
    var shouldAutoStartOnLaunch:Bool{automaticTVEnabled && !automaticTVUUID.isEmpty && TVDisplayIdentity.screen(automaticTVUUID) != nil}
    var onAutomaticTV:Bool{targetID.flatMap(TVDisplayIdentity.uuid)==automaticTVUUID && !automaticTVUUID.isEmpty}
    var canBlankMac:Bool{active && onAutomaticTV && !targetIsBuiltIn && !blankDisplayIDs.isEmpty}
    private var blankDisplayIDs:[CGDirectDisplayID]{
        guard let tv=targetID else{return []}
        return TVDisplayIdentity.blankIDs(tv:tv,displays:NSScreen.screens.compactMap{s in guard let id=TVDisplayIdentity.id(s) else{return nil};return(id,CGDisplayIsBuiltin(id) != 0,CGDisplayIsMain(id) != 0,CGDisplayIsInMirrorSet(id) != 0)})
    }
    func startDisplayWatching(){
        guard !displayWatching else{return};displayWatching=true
        if !automaticTVUUID.isEmpty{defaults.set(automaticTVUUID,forKey:"koalaTVAutomaticDisplayUUID");defaults.set(automaticTVName,forKey:"koalaTVAutomaticDisplayName")}
        let center=NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main){[weak self]_ in Task{@MainActor in self?.sleeping=true;self?.macCover.hide();self?.macScreenBlanked=false}})
        workspaceObservers.append(center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main){[weak self]_ in Task{@MainActor in self?.sleeping=false;self?.scheduleDisplayCheck()}})
        if automaticTVEnabled,!defaults.bool(forKey:"koalaTVAutoLoginConfigured"),Bundle.main.bundleIdentifier=="local.minikeyboard.app" {
            do{if SMAppService.mainApp.status != .enabled{try SMAppService.mainApp.register()};defaults.set(true,forKey:"koalaTVAutoLoginConfigured")}catch{message="Enable Open at login in Mini Keyboard to watch for your TV after a restart."}
        }
        scheduleDisplayCheck()
    }
    private func scheduleDisplayCheck(){
        guard displayWatching else{return}
        displayTask?.cancel()
        let present=TVDisplayIdentity.screen(automaticTVUUID) != nil
        if !present{_=connectionPolicy.update(present:false,enabled:automaticTVEnabled,busy:busy);macCover.hide();macScreenBlanked=false}
        displayTask=Task{@MainActor [weak self] in
            do{try await Task.sleep(nanoseconds:900_000_000)}catch{return}
            guard let self=self,!Task.isCancelled,!self.sleeping else{return}
            while self.busy {do{try await Task.sleep(nanoseconds:250_000_000)}catch{return};guard !Task.isCancelled,TVDisplayIdentity.screen(self.automaticTVUUID) != nil else{return}}
            let screen=TVDisplayIdentity.screen(self.automaticTVUUID)
            if self.connectionPolicy.update(present:screen != nil,enabled:self.automaticTVEnabled,busy:self.busy),let screen=screen,let id=TVDisplayIdentity.id(screen){
                do{try self.show(on:String(id));self.message="Welcome home. Koala TV started on "+self.automaticTVName+"."}catch{self.lastError=true;self.message=error.localizedDescription;self.macCover.hide();self.macScreenBlanked=false}
            }else{self.updateMacCover()}
            self.displayDiagnostic()
        }
    }
    func rememberCurrentTV() throws {
        guard active,let id=targetID,!targetIsBuiltIn,let value=TVDisplayIdentity.uuid(id),CGDisplayIsInMirrorSet(id)==0,!MediaScreens.displays().contains(where:{$0.id==id && $0.isIPad}) else{throw RemoteFailure.message("Choose an extended TV display first.")}
        automaticTVUUID=value;automaticTVName=screenName;defaults.set(value,forKey:"koalaTVAutomaticDisplayUUID");defaults.set(screenName,forKey:"koalaTVAutomaticDisplayName");connectionPolicy.retry();automaticTVEnabled=true;scheduleDisplayCheck();updateMacCover()
    }
    func setMacScreenBlank(_ blank:Bool){
        guard active else{return}
        macRevealed = !blank
        if blank,!automaticallyBlankMac{automaticallyBlankMac=true}
        updateMacCover()
    }
    private func updateMacCover(){
        if canBlankMac,automaticallyBlankMac,!macRevealed,!sleeping {
            desk?.orderOut(nil);controlsVisible=false
            macCover.show(ids:blankDisplayIDs){[weak self] in self?.setMacScreenBlank(false)}
        }else{macCover.hide()}
        macScreenBlanked = !macCover.coveredIDs.isEmpty;displayDiagnostic()
    }
    private func displayDiagnostic(){
        let object:[String:Any]=["fullscreen":fullscreen,"home":homeVisible,"playerBundle":current?.0.bundleIdentifier ?? "","active":active,"automaticEnabled":automaticTVEnabled,"automaticDisplay":automaticTVName,"automaticConnected":TVDisplayIdentity.screen(automaticTVUUID) != nil,"target":targetID.map(String.init) ?? "","targetName":screenName,"blankedDisplays":macCover.coveredIDs.map(String.init),"macBlanked":macScreenBlanked,"handledConnection":connectionPolicy.handled,"openAtLogin":SMAppService.mainApp.status == .enabled,"updated":Date().timeIntervalSince1970]
        let url=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Mini Keyboard/tv-display-status.json")
        if let data=try? JSONSerialization.data(withJSONObject:object,options:.sortedKeys){try? data.write(to:url,options:.atomic)}
    }
    func refresh() {
        games = TVLibrary.load(); controllers = [];refreshOpenItems()
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() { powerConnected = (type as String) == kIOPSACPowerValue }
        if !rows.flatMap({ $0 }).contains(selected) { selected = "media:youtube" }
    }
    private func uuid(_ id: UInt32) -> String {
        guard let value = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return String(id) }
        return CFUUIDCreateString(nil, value) as String
    }
    func display(_ requested: String? = nil) throws -> NSScreen {
        let displays = MediaScreens.displays(), screens = NSScreen.screens
        if let requested = requested, requested != "auto" {
            guard let id = UInt32(requested), let screen = screens.first(where: { MediaScreens.id($0) == id }), !displays.contains(where: { $0.id == id && $0.isIPad }) else { throw RemoteFailure.message("Choose a connected TV or Mac display. iPad stays available for your regular media shortcuts.") }
            targetID = id; defaults.set(uuid(id), forKey: "koalaTVDisplayUUID"); screenName = screen.localizedName; return screen
        }
        let saved = defaults.string(forKey: "koalaTVDisplayUUID")
        let candidates = displays.filter { !$0.isIPad }
        let id = candidates.first(where: { uuid($0.id) == saved })?.id
            ?? candidates.filter { !$0.builtIn }.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })?.id
            ?? candidates.first?.id
        guard let screen = screens.first(where: { MediaScreens.id($0) == id }) else { throw RemoteFailure.message("Connect a display to start Koala TV.") }
        targetID = id; screenName = screen.localizedName; return screen
    }
    func show(on requested: String? = nil) throws {
        let screen = try display(requested)
        arrangedScreenFrame=screen.frame
        let starting = !active
        if !active {
            macRevealed=false
            active = true; refresh();TVAudio.shared.start();TVLiveCaptions.shared.loadLocales()
            savedAppIcon=NSApp.applicationIconImage
            if let url=Bundle.main.url(forResource:"TVIcon",withExtension:"icns"),let icon=NSImage(contentsOf:url){NSApp.applicationIconImage=icon}
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Koala TV session" as CFString, &awake)
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Koala TV session" as CFString, &systemAwake)
            playerTimer=Timer.scheduledTimer(withTimeInterval:0.8,repeats:true){[weak self]_ in Task{@MainActor in self?.syncPlayerFullscreen()}}
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshStatus() } }
        }
        refreshOpenItems();updateCursor();updateMacCover()
        if targetIsBuiltIn {
            homeVisible=true;settingsVisible=false;rail?.orderOut(nil);window?.orderOut(nil)
            NSApp.presentationOptions=[];showControls();return
        }
        if window == nil {
            let w = TVWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.title = "Koala TV"; w.level = .floating; w.isReleasedWhenClosed = false; w.backgroundColor = NSColor(red: 20/255, green:29/255, blue:24/255, alpha:1)
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.contentView = NSHostingView(rootView: TVHomeView(tv: self)); window = w
        }
        homeVisible = true; settingsVisible = false; rail?.orderOut(nil); window?.level = .floating
        window?.setFrame(screen.frame, display: true)
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
        window?.makeKeyAndOrderFront(nil); window?.orderFrontRegardless()
        if starting,builtInScreen != nil,!macScreenBlanked { showControls(activate:false) }
        // Foreground activation may finish after macOS transitions out of another app's Space.
        DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { [weak self] in
            guard let self=self, self.active, self.homeVisible, self.desk?.isKeyWindow != true else { return }
            self.window?.makeKeyAndOrderFront(nil); self.window?.orderFrontRegardless()
        }
    }
    func end(disconnected:Bool=false) {
        guard !busy else { return }
        if !disconnected{connectionPolicy.suppress()}
        macCover.hide();macScreenBlanked=false;macRevealed=false
        TVLiveCaptions.shared.stop();TVAudio.shared.stop();avPanel?.orderOut(nil)
        tvCursor.stop();rail?.orderOut(nil); window?.orderOut(nil);desk?.orderOut(nil);controlsVisible=false;active = false; homeVisible = false; settingsVisible = false;game=nil;gameTitle=nil
        if let icon=savedAppIcon{NSApp.applicationIconImage=icon};savedAppIcon=nil
        timer?.invalidate(); timer = nil
        playerTimer?.invalidate();playerTimer=nil;fullscreen=false
        if awake != 0 { IOPMAssertionRelease(awake); awake = 0 }
        if systemAwake != 0 { IOPMAssertionRelease(systemAwake); systemAwake = 0 }
        NSApp.presentationOptions = []; message = "TV session ended. Your apps stay open.";displayDiagnostic()
    }
    func shutdown() { displayTask?.cancel();displayWatching=false;busy = false; end();for observer in workspaceObservers{NSWorkspace.shared.notificationCenter.removeObserver(observer)};workspaceObservers=[] }
    private func refreshStatus() {
        prune()
        if !busy,(homeVisible || controlsVisible),Date().timeIntervalSince(lastOpenScan)>20 {refreshOpenItems()}
        if let info=IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),let type=IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() { powerConnected=(type as String)==kIOPSACPowerValue }
    }
    func refreshOpenItems(){Task { @MainActor in await scanOpenItems() }}
    private func scanOpenItems() async {
        guard !scanningOpen else{return};scanningOpen=true;defer{scanningOpen=false}
        let result=await openDiscovery.scan(games:games)
        openItems=result.items;openScanNote=result.note;lastOpenScan=Date()
        if selected.hasPrefix("open:"),!openItems.contains(where:{"open:"+$0.id==selected}){selected="media:youtube"}
    }
    private func displaysChanged() {
        scheduleDisplayCheck()
        guard active else{return}
        if !NSScreen.screens.contains(where:{MediaScreens.id($0)==targetID}) {
            busy=false;end(disconnected:true);message="TV disconnected. Choose a display to start again."
        } else {
            updateCursor();updateMacCover();TVLiveCaptions.shared.updateOverlay()
            if homeVisible,let s=targetScreen,!targetIsBuiltIn {window?.setFrame(s.frame,display:true)}
            else if !session.isEmpty || game != nil,let screen=targetScreen,screen.frame != arrangedScreenFrame,TVPlayerFullscreen.automaticReflow(busy:busy || fullscreenTransition,fullscreen:current.map{TVPlayerFullscreen.isFullscreen($0.1)} ?? fullscreen) {Task { @MainActor in try? await arrangeSession() }}
        }
    }
    private func updateCursor() {
        if active,cursorEnabled,let screen=targetScreen {tvCursor.start(on:screen,size:cursorLarge ? 66:50)}else{tvCursor.stop()}
    }
    func showControls(activate:Bool=true) {
        if macScreenBlanked{setMacScreenBlank(false)}
        if !active {do {try show()}catch{lastError=true;message=error.localizedDescription};return}
        if desk == nil {
            let w=TVWindow(contentRect:CGRect(x:0,y:0,width:1120,height:800),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            w.title="Koala TV — Mac controls";w.isReleasedWhenClosed=false;w.minSize=NSSize(width:900,height:670)
            w.backgroundColor=NSColor(red:16/255,green:31/255,blue:27/255,alpha:1)
            w.contentView=NSHostingView(rootView:TVDesktopView(tv:self))
            let delegate=TVDeskDelegate();delegate.tv=self;w.delegate=delegate;deskDelegate=delegate;desk=w
            let s=builtInScreen ?? targetScreen ?? NSScreen.main
            if let f=s?.visibleFrame {let width=min(1120,f.width-50),height=min(820,f.height-50);w.setFrame(CGRect(x:f.midX-width/2,y:f.midY-height/2,width:width,height:height),display:false)}
        }
        controlsVisible=true
        if activate {NSApp.setActivationPolicy(.regular);NSApp.activate(ignoringOtherApps:true);desk?.makeKeyAndOrderFront(nil)}else{desk?.orderFront(nil)}
    }
    func desktopClosed(){controlsVisible=false;if targetIsBuiltIn && homeVisible{end()}}
    func run(_ control:String,service:MediaDestination?=nil) {var o:[String:Any]=["control":control];if let s=service{o["service"]=s.rawValue};command(o){_,_,_ in}}
    var captionScreen:NSScreen?{targetScreen}
    func showAVControls(){
        TVAudio.shared.start();TVAudio.shared.refresh(pairedDevices:true);TVLiveCaptions.shared.loadLocales()
        if avPanel==nil {
            let p=NSPanel(contentRect:CGRect(x:0,y:0,width:740,height:840),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            p.title="Koala TV — Audio & Captions";p.isReleasedWhenClosed=false;p.hidesOnDeactivate=false;p.minSize=NSSize(width:650,height:600);p.level=NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+3);p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
            p.contentView=NSHostingView(rootView:TVAVControlsView{[weak self] in self?.avPanel?.orderOut(nil)});avPanel=p
        }
        if let f=(targetScreen ?? NSScreen.main)?.visibleFrame {let width=min(760,f.width-40),height=min(860,f.height-50);avPanel?.setFrame(CGRect(x:f.midX-width/2,y:f.midY-height/2,width:width,height:height),display:true)}
        NSApp.activate(ignoringOtherApps:true);avPanel?.makeKeyAndOrderFront(nil)
    }
    private var targetScreen:NSScreen? { NSScreen.screens.first{MediaScreens.id($0)==targetID} }
    private func prune() {
        let old=session,hadGame=game != nil
        session.removeAll { service in guard let pair=mediaWindows[service.rawValue] else{return true}; return pair.0.isTerminated || WindowSnapper.shared.frame(of:pair.1)==nil }
        if let g=game,g.0.isTerminated || WindowSnapper.shared.frame(of:g.1)==nil {game=nil;gameTitle=nil}
        if let focus=focusedService,!session.contains(focus) { focusedService=session.first;current=focusedService.flatMap{mediaWindows[$0.rawValue]} }
        if current==nil{fullscreen=false}
        if session != old || hadGame != (game != nil), !homeVisible, active,TVPlayerFullscreen.automaticReflow(busy:busy || fullscreenTransition,fullscreen:fullscreen) { Task { @MainActor in try? await arrangeSession() } }
    }
    var snapshot:[String:Any] {
        ["fullscreen":fullscreen,"macScreenBlanked":macScreenBlanked,"canBlankMac":canBlankMac,"automaticTV":automaticTVEnabled,"automaticTVName":automaticTVName,"onAutomaticTV":onAutomaticTV,"audio":TVAudio.shared.snapshot,"captions":TVLiveCaptions.shared.snapshot,"active":active,"home":homeVisible,"busy":busy,"settings":settingsVisible,
         "openItems":openItems.map(\.json),"scanningOpen":scanningOpen,"openScanNote":openScanNote ?? "",
         "macControls":controlsVisible,"largeCursor":cursorEnabled,"cursorVisible":tvCursor.visible,
         "display":targetID.map(String.init) ?? "","displayName":screenName,"selected":selected,
         "message":message,"current":currentTitle,"canResume":!session.isEmpty,"sharing":sharing,
         "session":session.map{["service":$0.rawValue,"name":$0.title,"focused":$0==focusedService] as [String:Any]},
         "games":games.map(\.json),"controllers":[],"power":powerConnected,"rpcs3":rpcs3URL() != nil,"game":gameTitle ?? ""]
    }
    func command(_ o:[String:Any],record:Bool=true,completion:@escaping(String,Bool,[String:Any])->Void) {
        if o["control"] as? String == "macScreen",let blank=o["blank"] as? Bool {setMacScreenBlank(blank);message=macScreenBlanked ? "Mac screen is blank. Click it or use Show Mac screen to reveal it.":"Mac screen is visible.";completion(message,false,["tv":snapshot]);return}
        guard !busy else {completion("Media is opening. Wait for it to finish.",true,[:]);return}
        let action=o["control"] as? String ?? ""
        let logged=["home","media","game","share","focus","fullscreen","focusMedia","hideMedia","resume","resumeOpen","exit"].contains(action)
        let click=record && logged ? AdventureStore.shared.begin(action:"tv_"+action,name:"Koala TV · "+action,trigger:"TV controls",origin:.app):nil
        let arranging=["home","display","media","game","share","focus","fullscreen","focusMedia","hideMedia","resume","resumeOpen","trackpad"].contains(action)
        if arranging {busy=true}
        Task { @MainActor in
            defer {if arranging {busy=false}}
            do {
                lastError=false
                switch action {
                case "home":try await leavePlayerFullscreen();try show(on:o["display"] as? String);message="Choose your evening."
                case "exit":end()
                case "display":try await leavePlayerFullscreen();let controls=controlsVisible;try show(on:o["display"] as? String);if controls{showControls()};message="TV moved to "+screenName+"."
                case "refresh":refresh();prune();message="Library refreshed."
                case "refreshOpen":await scanOpenItems();message=openScanNote ?? "Open media and games refreshed."
                case "resumeOpen":if !active{try show()};try await resumeOpen(o["item"] as? String ?? "")
                case "av":showAVControls();message="Audio & Captions."
                case "automaticTV":automaticTVEnabled=o["enabled"] as? Bool ?? false;message=automaticTVEnabled ? "TV will start when "+automaticTVName+" connects.":"Automatic TV start is off."
                case "rememberTV":try rememberCurrentTV();message="This display is your automatic TV."
                case "captions":if !active{try show()};if o["enabled"] as? Bool == true {TVLiveCaptions.shared.start()}else{TVLiveCaptions.shared.stop()};message=TVLiveCaptions.shared.status
                case "captionSettings":try TVLiveCaptions.shared.configure(o);message="Caption style updated."
                case "captionPreview":TVLiveCaptions.shared.preview();message="Caption preview."
                case "audioRefresh":TVAudio.shared.refresh(pairedDevices:true);TVLiveCaptions.shared.loadLocales();message="Sound outputs refreshed."
                case "audioOutput":try TVAudio.shared.choose(o["output"] as? String ?? "");message=TVAudio.shared.message
                case "audioVolume":guard let value=RemoteCommandPolicy.number(o["value"]),(0...1).contains(value) else{throw RemoteFailure.message("Invalid volume.")};try TVAudio.shared.setVolume(value);message="Volume updated."
                case "audioMute":try TVAudio.shared.setMuted(o["muted"] as? Bool ?? true);message=TVAudio.shared.muted ? "Sound muted.":"Sound unmuted."
                case "audioConnect":try await TVAudio.shared.connect(o["headphones"] as? String ?? "");message=TVAudio.shared.message
                case "audioSettings":TVAudio.shared.settings();message="Bluetooth settings opened on the Mac."
                case "setup":if !active {try show()};settingsVisible=true
                case "resume":try await resume()
                case "trackpad":
                    try await resume()
                    if let pair=current,let f=WindowSnapper.shared.frame(of:pair.1) {CGWarpMouseCursorPosition(CGPoint(x:f.midX,y:f.midY))}
                case "share":sharing=true;try await arrangeSession();showWatch();message="Your media shares one screen."
                case "focus":sharing=false;try await arrangeSession();showWatch();message="Focused on "+currentTitle+". Home stays within reach."
                case "fullscreen":try await togglePlayerFullscreen()
                case "focusMedia":try await focusMedia(service(o))
                case "hideMedia":try await hideMedia(service(o))
                case "select":if homeVisible {try await choose(selected)} else {try input("select")}
                case "media":if !active {try show()};try await choose("media:"+service(o).rawValue)
                case "game":if !active {try show()};try await choose("game:"+(o["game"] as? String ?? ""))
                case "controllers","bluetooth":throw RemoteFailure.message("Controller setup is deferred. Your existing RPCS3 configuration stays as it was.")
                case "back":if avPanel?.isVisible==true{avPanel?.orderOut(nil)}else if settingsVisible {settingsVisible=false} else if homeVisible {message="Choose a service or resume your media."} else {try input("back")}
                default:if homeVisible {navigate(action)} else {try input(action)}
                }
                if let click=click {AdventureStore.shared.finish(click,success:true)}
                completion(message,false,["tv":snapshot])
            } catch {if let click=click {AdventureStore.shared.finish(click,success:false)};lastError=true;message=error.localizedDescription;completion(message,true,["tv":snapshot])}
        }
    }
    private func service(_ o:[String:Any]) throws -> MediaDestination {
        guard let service=MediaDestination(rawValue:o["service"] as? String ?? "") else{throw RemoteFailure.message("Unknown media service")};return service
    }
    func navigate(_ direction:String) {
        guard ["up","down","left","right"].contains(direction) else{return}
        if settingsVisible {settingsVisible=false}
        let rows=self.rows.filter{!$0.isEmpty},r=self.rows.filter{!$0.isEmpty}.firstIndex(where:{$0.contains(selected)}) ?? 0
        let c=rows[r].firstIndex(of:selected) ?? 0
        switch direction {
        case "left":selected=rows[r][max(0,c-1)]
        case "right":selected=rows[r][min(rows[r].count-1,c+1)]
        case "up":let n=max(0,r-1);selected=rows[n][min(c,rows[n].count-1)]
        default:let n=min(rows.count-1,r+1);selected=rows[n][min(c,rows[n].count-1)]
        }
    }
    func activateTile(_ id:String) {
        guard !busy else{return};selected=id;lastError=false
        let arranging = id != "exit" && id != "setup" && id != "av"
        if arranging {busy=true}
        Task { @MainActor in
            defer {if arranging {busy=false}}
            let kind=id.hasPrefix("open:") ? "resumeOpen":id.hasPrefix("media:") ? "media":id.hasPrefix("game:") ? "game":id
            let click=AdventureStore.shared.begin(action:"tv_"+kind,name:"Koala TV · "+kind,trigger:"TV home",origin:.app)
            do {try await choose(id);AdventureStore.shared.finish(click,success:true)}
            catch {AdventureStore.shared.finish(click,success:false);lastError=true;message=error.localizedDescription}
        }
    }
    private func choose(_ id:String) async throws {
        if id=="av" {showAVControls();return}
        if id=="exit" {end();return}
        if id=="setup" {settingsVisible=true;return}
        if id=="resume" {try await resume();return}
        if id=="share" {sharing=true;try await arrangeSession();showWatch();return}
        if id.hasPrefix("open:"){try await resumeOpen(String(id.dropFirst(5)));return}
        if id.hasPrefix("game:") {try await openExistingGame(String(id.dropFirst(5)));return}
        guard let destination=MediaDestination(rawValue:String(id.dropFirst(6))),id.hasPrefix("media:") else{throw RemoteFailure.message("Unknown TV service")}
        guard AXIsProcessTrusted(),let screen=targetScreen else{throw RemoteFailure.message("Connect your TV and enable Accessibility for Mini Keyboard.")}
        prune()
        if session.contains(destination) {try await focusMedia(destination);return}
        guard session.count<mediaLimit else{throw RemoteFailure.message(game == nil ? "Four services already share the TV. Hide one from the phone’s Watching list before adding another.":"Three services already share the TV with your game. Hide one from the phone’s Watching list before adding another.")}
        busy=true;defer{busy=false}
        message="Opening "+destination.title+"…"
        let previous=session,oldFocus=focusedService,oldSharing=sharing
        var pair=mediaWindows[destination.rawValue]
        do {
            if pair?.0.isTerminated != false || pair.flatMap({WindowSnapper.shared.frame(of:$0.1)}) == nil {
                mediaTabs[destination.rawValue]=nil // A fresh window must not inherit a closed tab's identity.
                var opened:(NSRunningApplication,AXUIElement)?
                let stage=TVSessionLayout.stage(screen.visibleFrame)
                let frame=game == nil ? TVSessionLayout.frames(in:stage,count:session.count+1).last!:TVSessionLayout.gameFrames(in:stage,media:session.count+1).media.last!
                _=try await MediaLauncher.shared.launch(destination,explicitID:targetID,television:true,televisionFrame:frame,windowReady:{app,window in opened=(app,window);pair=(app,window)})
                guard let result=opened else{throw RemoteFailure.message("The service did not expose a media window.")};pair=result
            }
            mediaWindows[destination.rawValue]=pair;session.append(destination);focusedService=destination;current=pair;currentTitle=destination.title;sharing=true
            try await arrangeSession();showWatch();message=session.count>1 ? "\(session.count) services share your TV.":destination.title+" is ready."
        } catch {
            if let pair=pair {mediaWindows[destination.rawValue]=pair;_=AXUIElementSetAttributeValue(pair.1,kAXMinimizedAttribute as CFString,kCFBooleanTrue)}
            session=previous;focusedService=oldFocus;sharing=oldSharing;current=oldFocus.flatMap{mediaWindows[$0.rawValue]}
            try? await arrangeSession();throw error
        }
    }
    private func resumeOpen(_ id:String) async throws {
        guard let item=openItems.first(where:{$0.id==id}),!item.app.isTerminated else{refreshOpenItems();throw RemoteFailure.message("This item is no longer open. Refresh Continue watching.")}
        if item.isGame {
            // Bring a running game beside the media. Never boots, sends input or edits RPCS3 settings.
            if let g=item.game,AXIsProcessTrusted(),let w=gameWindow(item.app,id:g.id) {
                game=(item.app,w);gameTitle=g.title
                try await arrangeSession();showWatch();message=session.isEmpty ? g.title+" is back on your TV.":g.title+" is back beside your media.";return
            }
            item.app.unhide();item.app.activate(options:[.activateIgnoringOtherApps])
            window?.orderOut(nil);rail?.orderOut(nil);homeVisible=false;settingsVisible=false
            if targetIsBuiltIn{desk?.orderOut(nil);controlsVisible=false}
            message="Returned to "+item.title+".";return
        }
        guard AXIsProcessTrusted(),let service=item.service else{throw RemoteFailure.message("Allow Accessibility for Mini Keyboard to resume this window.")}
        guard session.contains(service) || session.count<mediaLimit else{throw RemoteFailure.message(game == nil ? "Four services already share the TV. Hide one before resuming another.":"Three services already share the TV with your game. Hide one before resuming another.")}
        message="Resuming "+item.title+"…"
        let resolved=try await openDiscovery.resolve(item),incoming=resolved.1
        let oldSession=session,oldFocus=focusedService,oldTitle=currentTitle,oldSharing=sharing,oldPair=mediaWindows[service.rawValue],oldTab=mediaTabs[service.rawValue]
        let original=WindowSnapper.shared.frame(of:incoming),wasMinimized=attribute(incoming,kAXMinimizedAttribute) as? Bool == true
        mediaWindows[service.rawValue]=resolved;mediaTabs[service.rawValue]=item.chromeTab
        if !session.contains(service){session.append(service)}
        current=resolved;focusedService=service;currentTitle=item.title;sharing=true
        do {
            try await arrangeSession()
            if let pair=oldPair,!CFEqual(pair.1,incoming){_=AXUIElementSetAttributeValue(pair.1,kAXMinimizedAttribute as CFString,kCFBooleanTrue)}
            showWatch();message="Resumed "+item.title+". Playback kept in its existing window.";refreshOpenItems()
        } catch {
            if let frame=original {WindowSnapper.shared.setFrame(incoming,frame)}
            _=AXUIElementSetAttributeValue(incoming,kAXMinimizedAttribute as CFString,wasMinimized ? kCFBooleanTrue:kCFBooleanFalse)
            mediaWindows[service.rawValue]=oldPair;mediaTabs[service.rawValue]=oldTab;session=oldSession;focusedService=oldFocus;currentTitle=oldTitle;sharing=oldSharing;current=oldFocus.flatMap{mediaWindows[$0.rawValue]}
            if !session.isEmpty{try? await arrangeSession()};throw error
        }
    }
    private func focusMedia(_ destination:MediaDestination) async throws {
        guard session.contains(destination),let pair=mediaWindows[destination.rawValue],!pair.0.isTerminated else{throw RemoteFailure.message("Open this service first.")}
        if focusedService==destination,TVPlayerFullscreen.isFullscreen(pair.1){try await resume();return}
        focusedService=destination;current=pair;currentTitle=destination.title
        try await arrangeSession();showWatch();message=destination.title+" selected."
    }
    private func hideMedia(_ destination:MediaDestination) async throws {
        guard session.contains(destination),let pair=mediaWindows[destination.rawValue] else{throw RemoteFailure.message("This service is no longer on the TV.")}
        guard AXUIElementSetAttributeValue(pair.1,kAXMinimizedAttribute as CFString,kCFBooleanTrue) == .success else{throw RemoteFailure.message("This window could not be hidden.")}
        session.removeAll{$0==destination}
        if focusedService==destination {focusedService=session.first;current=focusedService.flatMap{mediaWindows[$0.rawValue]};currentTitle=focusedService?.title ?? "Nothing playing yet"}
        if session.isEmpty && game == nil {try show();message="Media hidden. Its playback may continue in the app."} else{try await arrangeSession();showWatch();message="Hidden from TV. Playback may continue in the app."}
    }
    private func arrangeSession() async throws {
        guard active,let screen=targetScreen else{throw RemoteFailure.message("Your TV disconnected. Start a new TV session.")}
        if let g=game,g.0.isTerminated || WindowSnapper.shared.frame(of:g.1)==nil {game=nil;gameTitle=nil}
        guard !session.isEmpty || game != nil else{throw RemoteFailure.message("Open a service first.")}
        try await leavePlayerFullscreen()
        let wanted=session.isEmpty ? []:(sharing ? session : [focusedService ?? session[0]])
        // A game keeps the large area; up to three services share the column beside it.
        let visible=game == nil ? wanted:Array(wanted.prefix(3))
        let stage=TVSessionLayout.stage(screen.visibleFrame)
        let gameLayout=game == nil ? nil:TVSessionLayout.gameFrames(in:stage,media:visible.count)
        let frames=gameLayout?.media ?? TVSessionLayout.frames(in:stage,count:visible.count)
        var originals=session.compactMap{ service -> (AXUIElement,CGRect,Bool)? in
            guard let w=mediaWindows[service.rawValue]?.1,let frame=WindowSnapper.shared.frame(of:w) else{return nil};return(w,frame,attribute(w,kAXMinimizedAttribute) as? Bool == true)
        }
        if let g=game,let frame=WindowSnapper.shared.frame(of:g.1){originals.append((g.1,frame,false))}
        do {
            for service in session where !visible.contains(service) {if let w=mediaWindows[service.rawValue]?.1 {_=AXUIElementSetAttributeValue(w,kAXMinimizedAttribute as CFString,kCFBooleanTrue)}}
            // RPCS3 opens games full screen with the user's own settings; place() returns it to a window first.
            if let g=game,let frame=gameLayout?.game {try await GroveActions.shared.place(g.1,app:g.0,name:gameTitle ?? "RPCS3",frame:frame)}
            for (i,service) in visible.enumerated() {
                guard let pair=mediaWindows[service.rawValue],!pair.0.isTerminated else{throw RemoteFailure.message("A media app closed. Reopen it from Home.")}
                if let tab=mediaTabs[service.rawValue] {try await openDiscovery.place(tab:tab,service:service,app:pair.0,window:pair.1,frame:frames[i])}
                else {try await GroveActions.shared.place(pair.1,app:pair.0,name:service.title,frame:frames[i])}
            }
        } catch {
            for (w,frame,minimized) in originals {WindowSnapper.shared.setFrame(w,frame);_=AXUIElementSetAttributeValue(w,kAXMinimizedAttribute as CFString,minimized ? kCFBooleanTrue:kCFBooleanFalse)}
            throw RemoteFailure.message("These services need more room. Try Focus one, hide a service, or choose a larger display. "+error.localizedDescription)
        }
        arrangedScreenFrame=screen.frame
        if let pair=current,let focus=focusedService,visible.contains(focus) {pair.0.unhide();pair.0.activate(options:[.activateIgnoringOtherApps]);_=AXUIElementPerformAction(pair.1,kAXRaiseAction as CFString)}
        else if let g=game {g.0.activate(options:[.activateIgnoringOtherApps]);_=AXUIElementPerformAction(g.1,kAXRaiseAction as CFString)}
    }
    func focusGame(){
        guard let g=game,!g.0.isTerminated else{return}
        g.0.activate(options:[.activateIgnoringOtherApps]);_=AXUIElementPerformAction(g.1,kAXRaiseAction as CFString);message=(gameTitle ?? "Game")+" is in front."
    }
    private func showWatch() {
        guard let screen=targetScreen,!session.isEmpty || game != nil else{return}
        homeVisible=false;settingsVisible=false;displayDiagnostic()
        // An all-Spaces canvas must be hidden, not left behind a video’s new Space.
        window?.level = .normal;window?.orderOut(nil);NSApp.presentationOptions=[]
        if fullscreen{rail?.orderOut(nil);return}
        if targetIsBuiltIn {desk?.orderOut(nil);controlsVisible=false}
        if rail==nil {
            let p=TVRailPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.title="Koala TV controls";p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false
            p.level=NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+1)
            p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
            p.contentView=NSHostingView(rootView:TVWatchRail(tv:self));rail=p
        }
        let h=TVSessionLayout.railHeight(screen.frame)
        rail?.setFrame(CGRect(x:screen.frame.minX,y:screen.frame.maxY-h,width:screen.frame.width,height:h),display:true);rail?.orderFrontRegardless()
    }
    private func resume() async throws {
        if !active {try show()};prune();guard !session.isEmpty || game != nil else{throw RemoteFailure.message("Open a service first.")}
        if let pair=current,TVPlayerFullscreen.isFullscreen(pair.1){fullscreen=true;pair.0.activate(options:[.activateIgnoringOtherApps]);_=AXUIElementPerformAction(pair.1,kAXRaiseAction as CFString);hidePlayerChrome();message="Back to full-screen playback.";return}
        try await arrangeSession();showWatch();message="Back to your media."
    }
    private func hidePlayerChrome(){
        homeVisible=false;settingsVisible=false;window?.orderOut(nil);rail?.orderOut(nil);NSApp.presentationOptions=[]
        if targetIsBuiltIn{desk?.orderOut(nil);controlsVisible=false}
    }
    private func syncPlayerFullscreen(){
        guard active,!busy,!fullscreenTransition,let pair=current,!pair.0.isTerminated else{return}
        let actual=TVPlayerFullscreen.isFullscreen(pair.1)
        guard actual != fullscreen else{return}
        fullscreen=actual;displayDiagnostic()
        if actual {
            sharingBeforeFullscreen=sharing
            // Also respect the player’s own button, including its new macOS Space.
            if !homeVisible || pair.0.isActive{hidePlayerChrome()}
        } else if !homeVisible {
            sharing=sharingBeforeFullscreen
            busy=true
            Task{@MainActor in defer{busy=false};do{try await arrangeSession();showWatch()}catch{lastError=true;message=error.localizedDescription}}
        }
    }
    private func leavePlayerFullscreen() async throws {
        guard !fullscreenTransition else{return}
        fullscreenTransition=true;defer{fullscreenTransition=false}
        // A newly selected service may differ from the one that was full screen.
        for service in session {
            if let pair=mediaWindows[service.rawValue],!pair.0.isTerminated,(TVPlayerFullscreen.isFullscreen(pair.1) || TVPlayerFullscreen.controls(pair.1).exit != nil){try await TVPlayerFullscreen.set(false,app:pair.0,window:pair.1)}
        }
        fullscreen=false
    }
    private func togglePlayerFullscreen() async throws {
        guard active,let pair=current,let screen=targetScreen,!pair.0.isTerminated else{throw RemoteFailure.message("Resume a media service first, then choose Full screen.")}
        if TVPlayerFullscreen.isFullscreen(pair.1){
            try await leavePlayerFullscreen();sharing=sharingBeforeFullscreen;try await arrangeSession();showWatch();message="Back to your TV layout.";return
        }
        let oldSharing=sharing;sharingBeforeFullscreen=oldSharing;sharing=false
        do {
            // Move the actual player to the chosen TV before it creates a Space.
            try await arrangeSession()
            fullscreenTransition=true
            hidePlayerChrome()
            defer{fullscreenTransition=false}
            try await TVPlayerFullscreen.set(true,app:pair.0,window:pair.1)
            guard let f=WindowSnapper.shared.frame(of:pair.1),TVPlayerFullscreen.onDisplay(f,WindowSnapper.shared.flip(screen.frame)) else{
                try? await TVPlayerFullscreen.set(false,app:pair.0,window:pair.1)
                throw RemoteFailure.message("The player moved away from your TV. Full screen was cancelled so it cannot be hidden on the Mac display.")
            }
            fullscreen=true;displayDiagnostic();message="Full screen on "+screenName+". Use Exit full screen or Home on your phone to return."
        } catch {
            fullscreenTransition=false;try? await leavePlayerFullscreen();sharing=oldSharing
            try? await arrangeSession();showWatch();throw error
        }
    }
    private func input(_ control:String) throws {
        guard active,AXIsProcessTrusted(),!IsSecureEventInputEnabled(),let current=current,!current.0.isTerminated,WindowSnapper.shared.frame(of:current.1) != nil else{throw RemoteFailure.message("Choose a media service first, or press Home.")}
        let back:(UInt16,CGEventFlags)=current.0.bundleIdentifier?.hasPrefix("com.google.Chrome") == true ? (33,.maskCommand):(53,[])
        let map:[String:(UInt16,CGEventFlags)]=["up":(126,[]),"down":(125,[]),"left":(123,[]),"right":(124,[]),"select":(36,[]),"back":back,"playPause":(49,[]),"previous":(123,[]),"next":(124,[]),"tab":(48,[]),"shiftTab":(48,.maskShift)]
        guard let pair=map[control] else{throw RemoteFailure.message("Use the phone trackpad for this control.")}
        current.0.activate(options:[.activateIgnoringOtherApps]);_=AXUIElementPerformAction(current.1,kAXRaiseAction as CFString)
        for down in [true,false] {let e=CGEvent(keyboardEventSource:CGEventSource(stateID:.privateState),virtualKey:pair.0,keyDown:down);e?.flags=pair.1;e?.postToPid(current.0.processIdentifier)}
        if !fullscreen{rail?.orderFrontRegardless()};message="Control sent to "+currentTitle+"."
    }
    private var mediaLimit:Int{game == nil ? 4:3}
    /// RPCS3 builds after 20064 black-screen Ratchet & Clank (RPCS3 PR #19567). When several copies are
    /// installed, macOS would pick the newest, so prefer the verified build.
    func rpcs3URL()->URL? {
        let build=defaults.string(forKey:"koalaTVRPCS3Build") ?? "20064"
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier:"net.rpcs3.rpcs3").first{Bundle(url:$0)?.infoDictionary?["CFBundleVersion"] as? String==build}
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier:"net.rpcs3.rpcs3")
    }
    private func openExistingGame(_ id:String) async throws {
        guard let game=games.first(where:{$0.id==id}),game.available,FileManager.default.fileExists(atPath:game.path.path),let url=rpcs3URL() else{throw RemoteFailure.message("This game’s file is unavailable. Your existing RPCS3 setup is unchanged.")}
        // RPCS3 keeps the user's own settings and controllers. Koala TV only chooses the TV screen and
        // places the game window beside the media; it never edits emulator config or sends game input.
        let app:NSRunningApplication
        if let running=NSRunningApplication.runningApplications(withBundleIdentifier:"net.rpcs3.rpcs3").first(where:{!$0.isTerminated}) {
            guard AXIsProcessTrusted(),gameWindow(running,id:game.id) != nil else {
                running.activate(options:[.activateIgnoringOtherApps]);message="RPCS3 is already open. Use your existing game list."
                window?.orderOut(nil);rail?.orderOut(nil);homeVisible=false;settingsVisible=false;return
            }
            app=running
        } else {
            let cfg=NSWorkspace.OpenConfiguration();var arguments=["--no-gui"]
            if let screen=NSScreen.screens.firstIndex(where:{MediaScreens.id($0)==targetID}){arguments+=["--game-screen",String(screen)]}
            cfg.arguments=arguments+[game.path.path]
            app=try await NSWorkspace.shared.openApplication(at:url,configuration:cfg)
        }
        guard AXIsProcessTrusted(),active else{message="Opened with your existing RPCS3 settings.";window?.orderOut(nil);rail?.orderOut(nil);homeVisible=false;settingsVisible=false;return}
        message="Starting "+game.title+"…"
        guard let started=await waitForGameWindow(app,id:game.id) else{throw RemoteFailure.message(game.title+" is still starting in RPCS3. Once it appears, choose it under Continue to place it beside your media.")}
        self.game=(app,started);gameTitle=game.title
        try await arrangeSession();showWatch()
        message=session.isEmpty ? game.title+" is on your TV.":game.title+" is beside your media."
    }
    /// The game window's title carries its serial, e.g. "… [NPUA80645]".
    private func gameWindow(_ app:NSRunningApplication,id:String)->AXUIElement? {
        let windows=TVOpenDiscovery.windows(app)
        func title(_ w:AXUIElement)->String{attribute(w,kAXTitleAttribute as String) as? String ?? ""}
        return windows.first{title($0).contains("["+id+"]")} ?? windows.first{title($0).hasPrefix("FPS")}
    }
    private func waitForGameWindow(_ app:NSRunningApplication,id:String) async -> AXUIElement? {
        for _ in 0..<120 {
            if app.isTerminated{return nil}
            if let w=gameWindow(app,id:id){return w}
            try? await Task.sleep(nanoseconds:500_000_000)
        }
        return nil
    }
    private func attribute(_ e:AXUIElement,_ key:String)->CFTypeRef? {var v:CFTypeRef?;return AXUIElementCopyAttributeValue(e,key as CFString,&v) == .success ? v:nil}
}

@MainActor final class TVRailPanel:NSPanel {
    override var canBecomeKey:Bool{false}
    override var canBecomeMain:Bool{false}
}

@MainActor final class TVWindow:NSWindow {
    override var canBecomeKey:Bool{true}
    override var canBecomeMain:Bool{true}
    override func keyDown(with event:NSEvent) {
        let map:[UInt16:String]=[123:"left",124:"right",125:"down",126:"up",36:"select",49:"select",53:"back"]
        if let control=map[event.keyCode]{TVMode.shared.command(["control":control]){_,_,_ in }}else{super.keyDown(with:event)}
    }
}

@MainActor final class TVDeskDelegate:NSObject,NSWindowDelegate {
    weak var tv:TVMode?
    func windowWillClose(_ notification:Notification){tv?.desktopClosed()}
    func windowDidBecomeKey(_ notification:Notification){NSApp.presentationOptions=[]}
}
