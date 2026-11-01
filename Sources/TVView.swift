import SwiftUI
import AppKit

enum TVStyle {
    static let background=Color(hex:0x101F1B),panel=Color(hex:0x233D32),mint=Color(hex:0x9CD5B4),gold=Color(hex:0xEAC578),text=Color(hex:0xF0F3EB),muted=Color(hex:0x9DB3A8)
    static func name(_ s:MediaDestination)->String { s == .gdn ? "GDN Play":s == .nba ? "NBA League Pass":s.title }
    static func short(_ s:MediaDestination)->String { s == .youtubeMusic ? "YT Music":s == .nba ? "NBA":name(s) }
    static func color(_ s:MediaDestination)->Color {switch s {case .netflix,.youtube,.youtubeMusic:return Color(hex:0xED6762);case .hbo:return Color(hex:0xC1B2EF);case .nba:return gold;case .appleTV:return text;default:return mint}}
}
struct TVMediaIcon:View {
    let service:MediaDestination
    var size:CGFloat=52
    var body:some View {
        Group {
            if let image=TVAssets.services[service.rawValue] {Image(nsImage:image).resizable().scaledToFit()}
            else if service == .appleTV {Image(systemName:"appletv.fill").resizable().scaledToFit().foregroundColor(TVStyle.text)}
            else {Text(service == .netflix ? "N":service == .hbo ? "HBO":"NBA").font(.system(size:service == .netflix ? size*0.8:size*0.4,weight:.heavy,design:.rounded)).foregroundColor(TVStyle.color(service))}
        }.frame(width:size,height:size).accessibilityHidden(true)
    }
}
struct TVHomeView:View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var tv:TVMode
    var body:some View {
        GeometryReader { g in
            let scale=min(g.size.width/1440,g.size.height/900)
            ZStack {
                TVStyle.background.ignoresSafeArea()
                if tv.homeVisible {
                    VStack(alignment:.leading,spacing:20) {
                        header
                        ScrollViewReader {proxy in
                            ScrollView {
                                VStack(alignment:.leading,spacing:22) {
                        hero
                        TVContinueSection(tv:tv,television:true)
                        HStack {Text("Your services").font(.system(size:26,weight:.bold,design:.rounded));Spacer();Text("Choose another to share the screen").font(.system(size:17)).foregroundColor(TVStyle.muted)}
                        HStack(spacing:12) {ForEach(MediaDestination.allCases,id:\.rawValue){service in serviceTile(service)}}
                        sessionStrip
                        gameShelf
                                }.padding(.vertical,5)
                            }.onChange(of:tv.selected){id in withAnimation(reduceMotion ? nil:.easeOut(duration:0.18)){proxy.scrollTo(id,anchor:.center)}}
                        }
                        Spacer(minLength:0)
                        HStack {Label(tv.message,systemImage:tv.lastError ? "exclamationmark.circle":"leaf").font(.system(size:17)).foregroundColor(tv.lastError ? TVStyle.gold:TVStyle.muted).lineLimit(2);Spacer();action("Audio & Captions","av","captions.bubble");action("Setup","setup","slider.horizontal.3");action("End TV","exit","power")}
                    }.padding(38).frame(width:1440,height:900).scaleEffect(scale).frame(width:g.size.width,height:g.size.height)
                    if tv.settingsVisible {setup.scaleEffect(max(0.7,scale)).frame(width:g.size.width,height:g.size.height)}
                    if tv.busy {VStack {Spacer();Text(tv.message).font(.system(size:24,weight:.semibold,design:.rounded)).padding(22).background(TVStyle.panel).cornerRadius(18).padding(30)}}
                }
            }
        }.foregroundColor(TVStyle.text).preferredColorScheme(.dark)
    }
    private var header:some View {
        HStack(spacing:12) {
            TVBrandMark(size:52,busy:tv.busy)
            Text("koala").font(.system(size:32,weight:.bold,design:.rounded)).tracking(-1)
            Text("TV").font(.system(size:15,weight:.heavy,design:.rounded)).foregroundColor(TVStyle.background).padding(.horizontal,9).padding(.vertical,5).background(TVStyle.gold).cornerRadius(7)
            Text("Your lounge").font(.system(size:18)).foregroundColor(TVStyle.muted).padding(.leading,22)
            Spacer();Button {tv.showControls()} label:{Label("Mac controls",systemImage:"laptopcomputer").font(.system(size:16,weight:.semibold))}.buttonStyle(TVSoftButton()).disabled(tv.busy);Label(tv.screenName,systemImage:"tv").font(.system(size:16)).foregroundColor(TVStyle.muted)
            TimelineView(.periodic(from:.now,by:60)){context in Text(context.date,style:.time).font(.system(size:18,weight:.medium,design:.rounded)).monospacedDigit()}.padding(.leading,18)
        }.frame(height:38)
    }
    private var hero:some View {
        ZStack(alignment:.leading) {
            if let url=Bundle.main.url(forResource:"koala-tv-lounge",withExtension:"png"),let image=NSImage(contentsOf:url) {
                Image(nsImage:image).resizable().scaledToFit().frame(width:900,height:375).frame(width:1364,height:280,alignment:.topTrailing).clipped()
            } else {HStack {Spacer();GroveArtwork(name:"media").frame(width:400,height:280)}}
            LinearGradient(colors:[TVStyle.background.opacity(0.95),TVStyle.background.opacity(0.5),.clear],startPoint:.leading,endPoint:.trailing)
            VStack(alignment:.leading,spacing:13) {
                Text("Stay in tonight.").font(.system(size:66,weight:.bold,design:.rounded)).tracking(-2)
                Text("Your shows. Your music. Your kind of evening.").font(.system(size:22)).foregroundColor(TVStyle.text.opacity(0.8))
                if !tv.session.isEmpty {Button {tv.activateTile("resume")} label:{Label("Back to your media",systemImage:"play.fill").font(.system(size:18,weight:.bold)).padding(.horizontal,22).padding(.vertical,13).background(TVStyle.mint).foregroundColor(TVStyle.background).cornerRadius(12)}.buttonStyle(.plain).padding(.top,6)}
                else {Label("Settle in. Your iPhone has the remote.",systemImage:"iphone.radiowaves.left.and.right").font(.system(size:18)).foregroundColor(TVStyle.mint).padding(.top,6)}
            }.padding(32)
        }.frame(height:280).cornerRadius(26)
    }
    private func serviceTile(_ service:MediaDestination)->some View {
        let focused=tv.selected=="media:"+service.rawValue,open=tv.session.contains(service)
        return Button {tv.activateTile("media:"+service.rawValue)} label:{
            VStack(spacing:11) {
                ZStack(alignment:.topTrailing) {
                    RoundedRectangle(cornerRadius:17).fill(TVStyle.color(service).opacity(0.1)).frame(height:73)
                    TVMediaIcon(service:service,size:46).frame(maxWidth:.infinity,maxHeight:.infinity)
                    if open {Circle().fill(TVStyle.mint).frame(width:8,height:8).padding(9)}
                }.frame(height:73)
                Text(TVStyle.name(service)).font(.system(size:16,weight:.semibold,design:.rounded)).lineLimit(1).minimumScaleFactor(0.8)
            }.padding(11).frame(maxWidth:.infinity).background(focused ? Color(hex:0x365543):TVStyle.panel.opacity(0.65)).cornerRadius(21)
                .overlay(RoundedRectangle(cornerRadius:21).stroke(focused ? TVStyle.mint:.clear,lineWidth:3))
                .scaleEffect(focused ? 1.025:1).animation(.easeOut(duration:0.14),value:focused)
        }.buttonStyle(TVTileButton()).disabled(tv.busy).id("media:"+service.rawValue).accessibilityLabel(service.title+(open ? " Open on TV":""))
    }
    private var sessionStrip:some View {
        HStack(spacing:16) {
            ZStack {RoundedRectangle(cornerRadius:12).stroke(TVStyle.muted.opacity(0.35),lineWidth:1).frame(width:92,height:53);HStack(spacing:3){ForEach(tv.session.prefix(4),id:\.rawValue){s in RoundedRectangle(cornerRadius:3).fill(TVStyle.color(s).opacity(0.6))}}.padding(8).frame(width:92,height:53)}
            VStack(alignment:.leading,spacing:5) {
                Text(tv.session.isEmpty ? "One screen. More possibilities.":"On your TV now").font(.system(size:20,weight:.semibold,design:.rounded))
                Text(tv.session.isEmpty ? "Open two services for a side-by-side evening.":tv.session.map{TVStyle.short($0)}.joined(separator:" + ")).font(.system(size:16)).foregroundColor(TVStyle.muted)
            }
            Spacer()
            if !tv.session.isEmpty {action("Resume","resume","play.fill");action("Share screen","share","rectangle.split.2x1")}
        }.padding(17).background(TVStyle.panel.opacity(0.45)).cornerRadius(18)
    }
    private var gameShelf:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text("Your PS3 games").font(.system(size:24,weight:.bold,design:.rounded));Spacer();Text("Your existing RPCS3 setup").font(.system(size:16)).foregroundColor(TVStyle.muted)}
            HStack(spacing:14) {ForEach(Array(tv.games.prefix(4))){game in
                Button {tv.activateTile("game:"+game.id)} label:{HStack(spacing:12){
                    if let image=game.icon {Image(nsImage:image).resizable().scaledToFit().frame(width:70,height:66)} else {Image(systemName:"opticaldisc").font(.system(size:30)).foregroundColor(TVStyle.muted).frame(width:48,height:66)}
                    VStack(alignment:.leading,spacing:5){Text(game.title).font(.system(size:16,weight:.semibold,design:.rounded)).lineLimit(2);Text(game.available ? "Open in RPCS3":"File missing").font(.system(size:13)).foregroundColor(game.available ? TVStyle.mint:TVStyle.gold)}.frame(maxWidth:.infinity,alignment:.leading)
                }.padding(12).frame(maxWidth:.infinity).background(TVStyle.panel.opacity(0.45)).cornerRadius(16).overlay(RoundedRectangle(cornerRadius:16).stroke(tv.selected=="game:"+game.id ? TVStyle.mint:.clear,lineWidth:2))}.buttonStyle(.plain).disabled(tv.busy || !game.available).id("game:"+game.id)
            }}
        }
    }
    private func action(_ title:String,_ id:String,_ symbol:String)->some View {
        Button {tv.activateTile(id)} label:{Label(title,systemImage:symbol).font(.system(size:17,weight:.semibold)).padding(.horizontal,16).padding(.vertical,10).background(tv.selected==id ? TVStyle.mint.opacity(0.2):TVStyle.panel).cornerRadius(11)}.buttonStyle(.plain).disabled(tv.busy).id(id)
    }
    private var setup:some View {
        ScrollView {VStack(alignment:.leading,spacing:24) {
            HStack {Text("Your lounge").font(.system(size:34,weight:.bold,design:.rounded));Spacer();Button("Done"){tv.settingsVisible=false}.buttonStyle(.bordered).controlSize(.large)}
            Label(tv.powerConnected ? "Power connected":"Connect the Mac to power for closed-lid use",systemImage:"powerplug.fill").foregroundColor(TVStyle.mint)
            Text("Home is always on the TV’s top bar and your iPhone. Opening another service adds it to the shared screen. Choose Focus one for a larger view, or Share screen to bring them together.").foregroundColor(TVStyle.muted)
            Divider();Text("TV display").font(.system(size:24,weight:.bold,design:.rounded))
            HStack {ForEach(NSScreen.screens.filter{s in !MediaScreens.displays().contains{$0.id==MediaScreens.id(s) && $0.isIPad}},id:\.localizedName){s in Button(s.localizedName){tv.command(["control":"display","display":String(MediaScreens.id(s) ?? 0)]){_,_,_ in}}.buttonStyle(.bordered).controlSize(.large)}}
            Text("The iPad stays available for your regular media shortcuts.").font(.system(size:17)).foregroundColor(TVStyle.muted)
            Toggle("Big TV pointer",isOn:$tv.cursorEnabled).toggleStyle(.switch).tint(TVStyle.mint)
            if tv.cursorEnabled {Toggle("Extra large pointer",isOn:$tv.cursorLarge).toggleStyle(.switch).tint(TVStyle.mint)}
            TVConnectionView(tv:tv)
            Button {tv.settingsVisible=false;tv.showControls()}label:{Label("Open Mac controls",systemImage:"laptopcomputer")}.buttonStyle(TVSoftButton())
            Divider();Text("RPCS3 keeps your existing game and controller settings. Controller setup can wait until you have it with you.").font(.system(size:18)).foregroundColor(TVStyle.muted)
            Text("Keep the Mac awake and unlocked on the same Wi-Fi. Connect and approve the TV before closing the lid; macOS controls closed-lid sleep.").font(.system(size:16)).foregroundColor(TVStyle.muted)
        }}.frame(maxHeight:630).font(.system(size:20)).padding(36).frame(width:820).background(TVStyle.background).cornerRadius(26).overlay(RoundedRectangle(cornerRadius:26).stroke(TVStyle.mint.opacity(0.4),lineWidth:1)).shadow(color:.black.opacity(0.7),radius:60)
    }
}

struct TVWatchRail:View {
    @ObservedObject var tv:TVMode
    private func run(_ control:String,_ service:MediaDestination?=nil) {var o:[String:Any]=["control":control];if let s=service{o["service"]=s.rawValue};tv.command(o){_,_,_ in}}
    var body:some View {
        HStack(spacing:13) {
            Button {run("home")} label:{Label("Home",systemImage:"leaf.fill").font(.system(size:20,weight:.bold,design:.rounded)).foregroundColor(TVStyle.mint)}
            Divider().frame(height:28).padding(.horizontal,8)
            Button {run("back")} label:{Label("Back",systemImage:"chevron.left").font(.system(size:17,weight:.medium))}
            if let title=tv.gameTitle {Button {tv.focusGame()} label:{HStack(spacing:8){Image(systemName:"gamecontroller.fill").font(.system(size:20)).foregroundColor(TVStyle.mint);Text(title).font(.system(size:17,weight:.semibold)).lineLimit(1).frame(maxWidth:260,alignment:.leading)}.padding(.horizontal,13).padding(.vertical,11).background(TVStyle.mint.opacity(0.09)).cornerRadius(13)}.help("Bring the game to the front").accessibilityLabel("Game: "+title)}
            ForEach(tv.session,id:\.rawValue){service in Button {run("focusMedia",service)} label:{HStack(spacing:8){TVMediaIcon(service:service,size:28);Text(TVStyle.short(service)).font(.system(size:17,weight:.semibold)).lineLimit(1)}.padding(.horizontal,13).padding(.vertical,11).background(tv.focusedService==service ? TVStyle.mint.opacity(0.17):Color.clear).cornerRadius(13)}}
            Spacer(minLength:12)
            Button {run("fullscreen")}label:{Label("Full screen",systemImage:"arrow.up.left.and.arrow.down.right").font(.system(size:17,weight:.semibold))}.help("Fill the TV with the selected player").accessibilityLabel("Full screen")
            TVAVButtons(tv:tv)
            Button {tv.showControls()}label:{Image(systemName:"laptopcomputer").font(.system(size:22))}.help("Mac controls").accessibilityLabel("Mac controls")
            Button {run(tv.sharing ? "focus":"share")} label:{Label(tv.sharing ? "Focus one":"Share screen",systemImage:tv.sharing ? "rectangle":"rectangle.split.2x1").font(.system(size:17,weight:.medium))}
            Button {run("home")} label:{Label("Add media",systemImage:"plus").font(.system(size:17,weight:.bold)).padding(.horizontal,17).padding(.vertical,12).background(TVStyle.mint).foregroundColor(TVStyle.background).cornerRadius(12)}
        }.buttonStyle(.plain).disabled(tv.busy).padding(.horizontal,28).frame(maxWidth:.infinity,maxHeight:.infinity).background(TVStyle.background).foregroundColor(TVStyle.text).preferredColorScheme(.dark)
    }
}
