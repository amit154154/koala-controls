import AppKit
import SwiftUI

enum AdventureCatalog {
    static let core = ["grove_connect","grove_viz","grove_media","grove_write","grove_code","grove_build","grove_setup","grove_claude","win_min","win_left","win_max","win_right","win_tl","win_tr","win_bl","win_br"]
    static func name(_ id: String) -> String { Actions.byID[id]?.cap ?? ["space_prev":"Previous Space","space_next":"Next Space","media_arrange":"Arrange media","media_focus":"Focus media","volume":"Mac volume"][id] ?? id.replacingOccurrences(of:"_",with:" ") }
}

final class AdventureWindow {
    static let shared = AdventureWindow()
    private var window: NSWindow?
    func show() {
        if window == nil {
            let w = NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:760),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            w.title = "Your Koala adventure"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView:AdventureView()); w.minSize = NSSize(width:640,height:560)
            w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
}
struct AdventureView: View {
    @ObservedObject private var adventure = AdventureStore.shared
    private var ids: [String] { AdventureCatalog.core + adventure.mastery.keys.filter { !AdventureCatalog.core.contains($0) }.sorted() }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack(alignment:.center,spacing:20) {
                    GroveArtwork(name:"companion").frame(width:115,height:115)
                    VStack(alignment:.leading,spacing:8) {
                        Text("Grove Adventurer").font(.system(size:30,weight:.bold,design:.rounded))
                        Text(AdventureRules.title(adventure.playerLevel)).font(.title3).foregroundColor(GroveTheme.gold)
                        Text("Level \(adventure.playerLevel) · \(adventure.xp) XP · \(adventure.totalClicks) shortcut clicks").font(.callout).foregroundColor(GroveTheme.muted)
                        ProgressView(value:Double(adventure.xp-AdventureRules.threshold(adventure.playerLevel,player:true)),total:Double(AdventureRules.threshold(adventure.playerLevel+1,player:true)-AdventureRules.threshold(adventure.playerLevel,player:true))).tint(GroveTheme.mint)
                        Text("\(AdventureRules.threshold(adventure.playerLevel+1,player:true)-adventure.xp) XP until your next promotion. No actual management responsibilities.").font(.caption).foregroundColor(GroveTheme.muted)
                    }
                }
                if let notice = adventure.notices.last {
                    Label("\(notice.scope == "player" ? "Player" : notice.name) reached level \(notice.level) · \(notice.unlocked)",systemImage:"sparkles").font(.callout).foregroundColor(GroveTheme.gold)
                }
                Divider().overlay(GroveTheme.line)
                HStack { Text("Your mastery field guide").font(.title2.bold()); Spacer(); Text("1 successful use = 1 XP").font(.caption).foregroundColor(GroveTheme.muted) }
                Text("Every function grows on its own. Levels 2, 3, 5 and 10 unlock Leaf trail, Star burst, Golden orbit and Cosmic grove. Your original scenes and rare surprises stay in the collection.").font(.callout).foregroundColor(GroveTheme.muted)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:12) {
                    ForEach(ids,id:\.self) { id in masteryRow(id) }
                }
                HStack { Text("Recent shortcut clicks").font(.title2.bold()); Spacer(); Button("Open full local journal") { NSWorkspace.shared.activateFileViewerSelecting([adventure.journalURL]) } }
                Text("Time, function, source, pad connection and outcome. Only registered shortcuts are recorded.").font(.caption).foregroundColor(GroveTheme.muted)
                if let error = adventure.error { Text(error).foregroundColor(GroveTheme.gold) }
                if adventure.recent.isEmpty { Text("Your first shortcut starts the adventure. The koala has packed exactly one leaf.").foregroundColor(GroveTheme.muted).padding(.vertical,18) }
                ForEach(adventure.recent.prefix(20)) { click in
                    HStack(alignment:.top) {
                        VStack(alignment:.leading,spacing:5) {
                            Text(click.name).font(.callout.bold())
                            Text("\(click.origin.title) · Pad \(click.keyboardConnected ? "connected" : "disconnected") · \(click.trigger)").font(.caption).foregroundColor(GroveTheme.muted)
                        }
                        Spacer()
                        VStack(alignment:.trailing,spacing:5) {
                            Text(click.timestamp,format:.dateTime.month(.abbreviated).day().hour().minute().second()).font(.caption)
                            Text(click.result).font(.caption).foregroundColor(click.result == "failed" ? GroveTheme.gold : GroveTheme.mint)
                        }
                    }.padding(.vertical,7)
                }
            }.padding(28)
        }.background(GroveTheme.background).foregroundColor(GroveTheme.text).preferredColorScheme(.dark)
    }
    private func masteryRow(_ id: String) -> some View {
        let m = adventure.mastery[id] ?? AdventureMastery(), tier = AdventureRules.tier(m.level)
        return VStack(alignment:.leading,spacing:8) {
            HStack {
                if let corner = WindowCorner.from(actionID:id) { Image(systemName:corner.symbol).foregroundColor(GroveTheme.mint) }
                Text(AdventureCatalog.name(id)).font(.callout.bold()); Spacer()
                Text("Lv. \(m.level)").font(.callout.bold()).foregroundColor(GroveTheme.gold)
            }
            Text(AdventureRules.flavor(id)).font(.caption).foregroundColor(GroveTheme.muted)
            ProgressView(value:Double(m.uses-AdventureRules.threshold(m.level,player:false)),total:Double(AdventureRules.threshold(m.level+1,player:false)-AdventureRules.threshold(m.level,player:false))).tint(GroveTheme.mint)
            HStack {
                Text("\(m.uses) uses").font(.caption)
                Spacer()
                Text(tier == 0 ? "Leaf trail at level 2" : AdventureRules.accents[tier]).font(.caption).foregroundColor(tier == 0 ? GroveTheme.muted : GroveTheme.gold)
            }
        }.padding(14).background(RoundedRectangle(cornerRadius:14).fill(GroveTheme.panel))
    }
}

struct CornerControlsView: View {
    var body: some View {
        HStack(spacing:10) {
            ForEach(WindowCorner.allCases,id:\.self) { corner in
                VStack(spacing:5) {
                    Image(systemName:corner.symbol).foregroundColor(GroveTheme.mint)
                    Text(corner.pad).font(.system(size:12,weight:.semibold,design:.rounded))
                    Text(corner.title).font(.system(size:10)).foregroundColor(GroveTheme.muted)
                }.frame(maxWidth:.infinity).padding(.vertical,8)
            }
        }.background(RoundedRectangle(cornerRadius:10).fill(GroveTheme.panel))
    }
}
