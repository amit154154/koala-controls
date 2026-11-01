import SwiftUI
import AppKit

/// The normal Mac window stays usable while the separate TV display is playing.
struct TVDesktopView:View {
    @ObservedObject var tv:TVMode
    private let columns=[GridItem(.flexible(),spacing:12),GridItem(.flexible(),spacing:12),GridItem(.flexible(),spacing:12),GridItem(.flexible(),spacing:12)]
    var body:some View {
        VStack(spacing:0) {
            header.padding(.horizontal,28).padding(.vertical,18)
            Divider().overlay(TVStyle.mint.opacity(0.1))
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    banner
                    TVContinueSection(tv:tv)
                    HStack(alignment:.top,spacing:24) {
                        VStack(alignment:.leading,spacing:16) {
                            HStack {Text("Your services").font(.system(size:25,weight:.bold,design:.rounded));Spacer();Text("Choose to open or bring forward").font(.system(size:13)).foregroundColor(TVStyle.muted)}
                            LazyVGrid(columns:columns,spacing:12) {ForEach(MediaDestination.allCases,id:\.rawValue) {service in serviceTile(service)}}
                            gameShelf.padding(.top,10)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                        VStack(alignment:.leading,spacing:20) {session;playback;cursorSettings;TVConnectionView(tv:tv)}.frame(width:276)
                    }
                }.padding(28)
            }
            HStack(spacing:12) {
                if tv.busy {ProgressView().controlSize(.small).tint(TVStyle.mint)}else{Image(systemName:tv.lastError ? "exclamationmark.circle.fill":"leaf.fill").foregroundColor(tv.lastError ? TVStyle.gold:TVStyle.mint)}
                Text(tv.message).font(.system(size:13)).foregroundColor(tv.lastError ? TVStyle.gold:TVStyle.muted).lineLimit(2)
                Spacer()
                Button("End TV"){tv.run("exit")}.buttonStyle(TVSoftButton()).disabled(tv.busy)
            }.padding(.horizontal,28).padding(.vertical,14).background(TVStyle.panel.opacity(0.45))
        }.background(TVStyle.background).foregroundColor(TVStyle.text).preferredColorScheme(.dark)
    }
    private var header:some View {
        HStack(spacing:13) {
            TVBrandMark(size:59,busy:tv.busy)
            VStack(alignment:.leading,spacing:3) {
                Text("koala TV").font(.system(size:28,weight:.bold,design:.rounded)).tracking(-0.8)
                Text("Your lounge").font(.system(size:13)).foregroundColor(TVStyle.muted)
            }
            Spacer()
            Button{tv.showAVControls()}label:{Label("Audio & Captions",systemImage:"captions.bubble").font(.system(size:14,weight:.semibold))}.buttonStyle(TVSoftButton()).padding(.trailing,12)
            VStack(alignment:.trailing,spacing:5) {
                Text("Play on").font(.system(size:12)).foregroundColor(TVStyle.muted)
                Menu {
                    ForEach(Array(tv.availableDisplays.enumerated()),id:\.offset){_,s in Button {tv.command(["control":"display","display":String(MediaScreens.id(s) ?? 0)]){_,_,_ in}}label:{Label(s.localizedName,systemImage:tv.targetID==MediaScreens.id(s) ? "checkmark":"display")}}
                } label:{Label(tv.screenName,systemImage:"display").font(.system(size:15,weight:.semibold)).padding(.horizontal,13).padding(.vertical,8).background(TVStyle.panel).cornerRadius(10)}.menuStyle(.borderlessButton).fixedSize().disabled(tv.busy).help("Choose where your TV home and media appear")
            }
        }
    }
    private var banner:some View {
        ZStack(alignment:.leading) {
            GeometryReader {g in
                if let image=TVAssets.lounge {Image(nsImage:image).resizable().scaledToFill().frame(width:g.size.width*0.74,height:g.size.height,alignment:.trailing).clipped().frame(width:g.size.width,alignment:.trailing)}
                LinearGradient(colors:[TVStyle.background,TVStyle.background.opacity(0.8),.clear],startPoint:.leading,endPoint:.trailing)
            }
            VStack(alignment:.leading,spacing:10) {
                Text("Your evening,\nyour way.").font(.system(size:34,weight:.bold,design:.rounded)).tracking(-1).fixedSize(horizontal:false,vertical:true)
                Text("A little music. A big game. Or both.").font(.system(size:15)).foregroundColor(TVStyle.text.opacity(0.8))
                Button {tv.run("home")}label:{Label(tv.targetIsBuiltIn ? "Browse here":"Show TV home",systemImage:"tv").font(.system(size:14,weight:.semibold))}.buttonStyle(TVSoftButton(prominent:true)).disabled(tv.busy).padding(.top,5)
            }.padding(23)
        }.frame(height:230).background(TVStyle.panel).clipShape(RoundedRectangle(cornerRadius:23))
    }
    private func serviceTile(_ service:MediaDestination)->some View {
        let open=tv.session.contains(service)
        return Button {tv.activateTile("media:"+service.rawValue)}label:{
            VStack(spacing:10) {
                TVMediaIcon(service:service,size:42)
                Text(TVStyle.short(service)).font(.system(size:14,weight:.semibold,design:.rounded)).lineLimit(1).minimumScaleFactor(0.8)
                Text(open ? "On your screen":"Open").font(.system(size:11)).foregroundColor(open ? TVStyle.mint:TVStyle.muted)
            }.frame(maxWidth:.infinity).padding(.vertical,17).background(open ? TVStyle.mint.opacity(0.13):TVStyle.panel.opacity(0.65)).cornerRadius(16).overlay(RoundedRectangle(cornerRadius:16).stroke(tv.selected=="media:"+service.rawValue ? TVStyle.mint.opacity(0.7):.clear,lineWidth:2))
        }.buttonStyle(TVTileButton()).disabled(tv.busy).accessibilityLabel(service.title+(open ? ", on your screen":""))
    }
    private var session:some View {
        VStack(alignment:.leading,spacing:13) {
            HStack {Text("Watching now").font(.system(size:20,weight:.bold,design:.rounded));Spacer();Text("\(tv.session.count)/4").font(.system(size:12,weight:.medium)).foregroundColor(TVStyle.muted)}
            if tv.session.isEmpty {
                Image(systemName:"rectangle.split.2x1").font(.system(size:33,weight:.light)).foregroundColor(TVStyle.mint).padding(.vertical,5)
                Text("Make room for both.").font(.system(size:16,weight:.semibold,design:.rounded))
                Text("Open a service, then another. Koala arranges them together on your selected display.").font(.system(size:13)).foregroundColor(TVStyle.muted).fixedSize(horizontal:false,vertical:true)
            } else {
                TVSessionPreview(services:tv.session,sharing:tv.sharing,focus:tv.focusedService).frame(height:100)
                ForEach(tv.session,id:\.rawValue){service in
                    HStack(spacing:9) {
                        Button {tv.run("focusMedia",service:service)}label:{HStack(spacing:9){TVMediaIcon(service:service,size:25);Text(TVStyle.short(service)).font(.system(size:14,weight:.semibold));Spacer();if tv.focusedService==service{Image(systemName:"speaker.wave.2").font(.system(size:11)).foregroundColor(TVStyle.mint)}}}.buttonStyle(.plain).help("Control "+service.title)
                        Button {tv.run("hideMedia",service:service)}label:{Image(systemName:"minus.circle").foregroundColor(TVStyle.muted)}.buttonStyle(.plain).help("Hide from TV; playback may continue").accessibilityLabel("Hide "+service.title)
                    }.padding(.vertical,3)
                }
                HStack(spacing:8) {
                    Button {tv.run("share")}label:{Label("Share",systemImage:"rectangle.split.2x1")}.buttonStyle(TVSoftButton(prominent:tv.sharing))
                    Button {tv.run("focus")}label:{Label("Focus one",systemImage:"rectangle")}.buttonStyle(TVSoftButton(prominent:!tv.sharing))
                }.font(.system(size:12,weight:.semibold))
                Button {tv.run("resume")}label:{Label("Show media",systemImage:"play.fill").frame(maxWidth:.infinity)}.buttonStyle(TVSoftButton())
            }
        }.padding(18).background(TVStyle.panel.opacity(0.55)).cornerRadius(19).disabled(tv.busy)
    }
    private var playback:some View {
        VStack(alignment:.leading,spacing:13) {
            Text("In control").font(.system(size:18,weight:.bold,design:.rounded))
            Text(tv.focusedService.map{TVStyle.name($0)} ?? "Choose a service first").font(.system(size:13)).foregroundColor(TVStyle.muted)
            HStack(spacing:9) {control("back","chevron.left","Go back");control("previous","backward.end.fill","Previous");control("playPause","playpause.fill","Play or pause");control("next","forward.end.fill","Next")}
            Button {tv.run("fullscreen")}label:{Label(tv.fullscreen ? "Exit full screen":"Full screen",systemImage:tv.fullscreen ? "arrow.down.right.and.arrow.up.left":"arrow.up.left.and.arrow.down.right").frame(maxWidth:.infinity)}.buttonStyle(TVSoftButton(prominent:true)).accessibilityLabel(tv.fullscreen ? "Exit full screen":"Full screen")
            Text("Player shortcuts follow the selected app. Use your iPhone trackpad for browsing.").font(.system(size:12)).foregroundColor(TVStyle.muted).fixedSize(horizontal:false,vertical:true)
        }.disabled(tv.busy || tv.session.isEmpty)
    }
    private func control(_ action:String,_ icon:String,_ title:String)->some View {Button{tv.run(action)}label:{Image(systemName:icon).frame(maxWidth:.infinity).frame(height:20)}.buttonStyle(TVSoftButton()).help(title).accessibilityLabel(title)}
    private var cursorSettings:some View {
        VStack(alignment:.leading,spacing:10) {
            Toggle("Big TV pointer",isOn:$tv.cursorEnabled).toggleStyle(.switch).font(.system(size:13,weight:.medium))
            if tv.cursorEnabled {Toggle("Extra large",isOn:$tv.cursorLarge).toggleStyle(.switch).font(.system(size:12)).foregroundColor(TVStyle.muted)}
            Text("Mint pointer, gold click ripple. Only on the selected display during a TV session.").font(.system(size:12)).foregroundColor(TVStyle.muted).fixedSize(horizontal:false,vertical:true)
        }.tint(TVStyle.mint)
    }
    private var gameShelf:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Your PS3 shelf").font(.system(size:22,weight:.bold,design:.rounded))
            Text("Open with your existing RPCS3 setup.").font(.system(size:13)).foregroundColor(TVStyle.muted)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                ForEach(tv.games.prefix(4)){game in Button {tv.activateTile("game:"+game.id)}label:{HStack(spacing:10){
                    if let image=game.icon{Image(nsImage:image).resizable().scaledToFit().frame(width:55,height:52)}else{Image(systemName:"opticaldisc").frame(width:55,height:52)}
                    VStack(alignment:.leading,spacing:4){Text(game.title).font(.system(size:13,weight:.semibold)).lineLimit(2);Text(game.available ? "Open in RPCS3":"File missing").font(.system(size:11)).foregroundColor(game.available ? TVStyle.mint:TVStyle.gold)}.frame(maxWidth:.infinity,alignment:.leading)
                }.padding(11).background(TVStyle.panel.opacity(0.5)).cornerRadius(12).overlay(RoundedRectangle(cornerRadius:12).stroke(tv.selected=="game:"+game.id ? TVStyle.mint:.clear,lineWidth:2))}.buttonStyle(TVTileButton()).disabled(tv.busy || !game.available)}
            }
        }
    }
}
struct TVSessionPreview:View {
    let services:[MediaDestination]
    let sharing:Bool
    let focus:MediaDestination?
    var body:some View {
        GeometryReader{g in
            let visible=sharing ? services:services.filter{$0==(focus ?? services.first)}
            let frames=TVSessionLayout.frames(in:CGRect(origin:.zero,size:g.size),count:visible.count)
            ForEach(Array(visible.enumerated()),id:\.element.rawValue){i,s in
                if i<frames.count {let f=frames[i];RoundedRectangle(cornerRadius:8).fill(TVStyle.color(s).opacity(0.15)).overlay(TVMediaIcon(service:s,size:25)).overlay(RoundedRectangle(cornerRadius:8).stroke(TVStyle.color(s).opacity(0.35),lineWidth:1)).frame(width:f.width,height:f.height).position(x:f.midX,y:g.size.height-f.midY)}
            }
        }.padding(7).background(Color.black.opacity(0.16)).cornerRadius(12).accessibilityLabel(sharing ? "Shared screen preview":"Single service preview")
    }
}
enum TVAssets {
    static let icon: NSImage? = Bundle.main.url(forResource:"koala-tv-icon",withExtension:"png").flatMap(NSImage.init(contentsOf:))
    static let lounge:NSImage? = Bundle.main.url(forResource:"koala-tv-lounge",withExtension:"png").flatMap(NSImage.init(contentsOf:))
    static let services:[String:NSImage] = Dictionary(uniqueKeysWithValues:MediaDestination.allCases.compactMap{s in Bundle.main.url(forResource:s.iconName,withExtension:"png").flatMap(NSImage.init(contentsOf:)).map{(s.rawValue,$0)}})
}
struct TVBrandMark:View {
    var size:CGFloat=48
    var busy:Bool=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered=false
    var body:some View {
        TimelineView(.animation(minimumInterval:0.08,paused:reduceMotion)){context in
            let phase=reduceMotion ? 0:sin(context.date.timeIntervalSinceReferenceDate*0.85)
            Group{if let image=TVAssets.icon{Image(nsImage:image).resizable().scaledToFit()}else{Image(systemName:"tv").resizable().scaledToFit().foregroundColor(TVStyle.mint)}}
                .rotationEffect(.degrees(hovered && !reduceMotion ? -6:phase*1.2)).offset(y:hovered && !reduceMotion ? -2:phase*0.7)
                .frame(width:size,height:size).overlay(alignment:.bottomTrailing){Circle().fill(busy ? TVStyle.gold:TVStyle.mint).frame(width:9,height:9).overlay(Circle().stroke(TVStyle.background,lineWidth:2)).padding(2)}
                .onHover{hovered=$0}.animation(reduceMotion ? nil:.spring(response:0.3),value:hovered)
        }.accessibilityHidden(true)
    }
}
struct TVTileButton:ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration:Configuration)->some View {TVTileBody(configuration:configuration,reduceMotion:reduceMotion)}
    private struct TVTileBody:View {
        let configuration:ButtonStyle.Configuration
        let reduceMotion:Bool
        @State private var hover=false
        var body:some View {configuration.label.overlay(RoundedRectangle(cornerRadius:16).stroke(TVStyle.mint.opacity(hover ? 0.8:0),lineWidth:2)).brightness(hover ? 0.035:0).scaleEffect(reduceMotion ? 1:configuration.isPressed ? 0.97:hover ? 1.02:1).onHover{hover=$0}.animation(reduceMotion ? nil:.easeOut(duration:0.14),value:hover).animation(reduceMotion ? nil:.easeOut(duration:0.1),value:configuration.isPressed)}
    }
}
struct TVSoftButton:ButtonStyle {
    var prominent=false
    func makeBody(configuration:Configuration)->some View {configuration.label.padding(.horizontal,12).padding(.vertical,9).background(prominent ? TVStyle.mint:TVStyle.panel).foregroundColor(prominent ? TVStyle.background:TVStyle.text).cornerRadius(9).opacity(configuration.isPressed ? 0.65:1)}
}
