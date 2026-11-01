import SwiftUI

struct TVContinueSection:View {
    @ObservedObject var tv:TVMode
    var television=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        VStack(alignment:.leading,spacing:television ? 15:12) {
            HStack(spacing:12) {
                Text("Continue watching & playing").font(.system(size:television ? 25:22,weight:.bold,design:.rounded))
                Spacer()
                if tv.scanningOpen {ProgressView().controlSize(.small).tint(TVStyle.mint)}
                Button {tv.refreshOpenItems()}label:{Label("Refresh",systemImage:"arrow.clockwise").font(.system(size:television ? 16:13,weight:.medium))}.buttonStyle(TVSoftButton()).disabled(tv.scanningOpen || tv.busy)
            }
            if tv.openItems.isEmpty {
                HStack(spacing:13) {
                    Image(systemName:"play.rectangle.on.rectangle").font(.system(size:27,weight:.light)).foregroundColor(TVStyle.mint)
                    Text(tv.scanningOpen ? "Looking for your open media and games…":"Your open media apps, Chrome media tabs and running RPCS3 session appear here. Resume keeps the same tab or window.").font(.system(size:television ? 17:13)).foregroundColor(TVStyle.muted).fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength:0)
                }.padding(17).frame(maxWidth:.infinity,alignment:.leading).background(TVStyle.panel.opacity(0.4)).cornerRadius(16)
            } else {
                ScrollViewReader{proxy in
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(spacing:13) {ForEach(tv.openItems){item in card(item).id("open:"+item.id)}}.padding(3)
                    }.onChange(of:tv.selected){id in if id.hasPrefix("open:"){withAnimation(reduceMotion ? nil:.easeOut(duration:0.18)){proxy.scrollTo(id,anchor:.center)}}}
                }
            }
            if let note=tv.openScanNote {Label(note,systemImage:"info.circle").font(.system(size:television ? 15:12)).foregroundColor(TVStyle.gold).fixedSize(horizontal:false,vertical:true)}
        }
    }
    private func card(_ item:TVOpenItem)->some View {
        let focused=tv.selected=="open:"+item.id
        return Button{tv.activateTile("open:"+item.id)}label:{
            HStack(alignment:.center,spacing:15) {
                Group{
                    if let service=item.service {TVMediaIcon(service:service,size:television ? 47:38)}
                    else if let image=item.game?.icon {Image(nsImage:image).resizable().scaledToFit().frame(width:television ? 58:43,height:52)}
                    else{Image(systemName:"gamecontroller.fill").font(.system(size:32)).foregroundColor(TVStyle.gold)}
                }.frame(width:television ? 58:43)
                VStack(alignment:.leading,spacing:6) {
                    Text(item.title).font(.system(size:television ? 18:15,weight:.semibold,design:.rounded)).lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth:.infinity,alignment:.leading)
                    Text(item.subtitle).font(.system(size:television ? 13:11)).foregroundColor(TVStyle.muted).lineLimit(1)
                    Label(item.isGame ? (item.game == nil ? "Return to RPCS3":"Return to game"):"Resume",systemImage: "play.fill").font(.system(size:television ? 14:12,weight:.semibold)).foregroundColor(TVStyle.mint)
                }
            }.padding(17).frame(width:television ? 365:300,height:television ? 108:97,alignment:.leading).background(TVStyle.panel.opacity(0.75)).cornerRadius(17).overlay(RoundedRectangle(cornerRadius:17).stroke(focused ? TVStyle.mint:TVStyle.mint.opacity(0.12),lineWidth:focused ? 2:1))
        }.buttonStyle(TVTileButton()).disabled(tv.busy).accessibilityLabel((item.isGame ? "Return to game: ":"Resume: ")+item.title+", "+item.subtitle)
    }
}
