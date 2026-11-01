import AppKit
import SwiftUI

final class AdventureCelebration {
    static let shared = AdventureCelebration()
    private var queue: [AdventureNotice] = []
    private var running = false
    private var panel: NSPanel?
    private var sound: NSSound?
    func enqueue(_ notices: [AdventureNotice]) {
        queue += notices
        if !running { showNext() }
    }
    private func showNext() {
        guard !queue.isEmpty else { running = false; return }
        running = true
        let notice = queue.removeFirst(), prefs = ShortcutFeedback.shared.preferences
        if prefs.sound, prefs.volume > 0,
           let url = Bundle.main.url(forResource:notice.scope == "player" ? "Maplestory-011" : "Maplestory-001",withExtension:"wav",subdirectory:"MapleStorySounds") {
            ShortcutFeedback.shared.stopSound()
            sound = NSSound(contentsOf:url,byReference:false); sound?.volume = Float(prefs.volume); sound?.play()
        }
        if prefs.animationEnabled, let screen = GroveActions.shared.currentScreen() {
            let panel = self.panel ?? ShortcutGuidePanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.level = NSWindow.Level(rawValue:NSWindow.Level.popUpMenu.rawValue-1)
            panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
            panel.title = "Koala level up"
            panel.contentView = NSHostingView(rootView:AdventureLevelUp(notice:notice,reduced:NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
            let vf=screen.visibleFrame
            let width=min(390,vf.width-24)
            panel.setFrame(CGRect(x:vf.maxX-width-12,y:vf.minY+18,width:width,height:165),display:false)
            self.panel=panel; panel.orderFrontRegardless()
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+1.65) { [weak self] in self?.panel?.orderOut(nil) }
        let wait = prefs.sound ? max(1.75,(sound?.duration ?? 0)+0.08) : 1.75
        DispatchQueue.main.asyncAfter(deadline:.now()+wait) { [weak self] in self?.showNext() }
    }
}
struct AdventureLevelUp: View {
    let notice: AdventureNotice
    let reduced: Bool
    @State private var arrived = false
    var body: some View {
        HStack(spacing:12) {
            ZStack {
                ForEach(0..<8,id:\.self) { i in
                    Image(systemName:i % 2 == 0 ? "leaf.fill" : "sparkle")
                        .font(.system(size:12)).foregroundColor(i % 2 == 0 ? GroveTheme.mint : GroveTheme.gold)
                        .offset(x:cos(Double(i)*Double.pi/4)*(arrived ? 51 : 12),y:sin(Double(i)*Double.pi/4)*(arrived ? 53 : 12))
                        .opacity(arrived ? 0.9 : 0)
                }
                GroveArtwork(name:"companion").frame(width:88,height:88).overlay(alignment:.top) { if notice.scope == "player" { Image(systemName:"crown.fill").font(.system(size:24)).foregroundColor(GroveTheme.gold).offset(x:12,y:-5) } }.rotationEffect(.degrees(arrived || reduced ? 0 : -16))
            }.frame(width:110,height:120)
            VStack(alignment:.leading,spacing:7) {
                Text(notice.scope == "player" ? "The grove has promoted you!" : "New trick, same tiny paws.").font(.system(size:13,weight:.bold,design:.rounded)).foregroundColor(GroveTheme.mint)
                Text("Level \(notice.level)").font(.system(size:30,weight:.heavy,design:.rounded)).foregroundColor(GroveTheme.gold)
                Text(notice.name).font(.system(size:12,weight:.semibold)).lineLimit(2)
                Text(notice.unlocked).font(.system(size:11)).foregroundColor(GroveTheme.muted).lineLimit(2)
            }
            Spacer(minLength:0)
        }.padding(14).background(RoundedRectangle(cornerRadius:20).fill(GroveTheme.background.opacity(0.96)))
            .overlay(RoundedRectangle(cornerRadius:20).stroke(GroveTheme.gold.opacity(0.65),lineWidth:1))
            .padding(5).foregroundColor(GroveTheme.text).preferredColorScheme(.dark)
            .scaleEffect(arrived || reduced ? 1 : 0.78)
            .onAppear { withAnimation(reduced ? nil : .spring(response:0.32,dampingFraction:0.65)) { arrived = true } }
    }
}

enum AdventureAccents {
    static func draw(style: CompanionStyle, tier: Int, progress: Double, reduced: Bool, in rect: CGRect) {
        guard tier > 0, let c = NSGraphicsContext.current?.cgContext else { return }
        c.saveGState(); defer { c.restoreGState() }
        let p = min(1,max(0,progress)), alpha = sin(p * .pi)
        c.setAlpha(alpha)
        let count = reduced ? 3 : 4+tier*3
        for i in 0..<count {
            let angle = Double(i)*2 * .pi/Double(count)+(reduced ? 0 : p*Double(tier))
            let radius = min(rect.width,rect.height)*(tier >= 3 ? 0.38 : 0.31)
            let x = rect.midX+cos(angle)*radius, y = rect.midY+sin(angle)*radius*0.82
            if tier == 1 {
                c.saveGState(); c.translateBy(x:x,y:y); c.rotate(by:angle)
                c.setFillColor(CompanionDrawing.mint.cgColor); c.fillEllipse(in:CGRect(x:-3,y:-6,width:6,height:12)); c.restoreGState()
            } else if tier >= 2 && i % 3 == 0 {
                let tokens: [CompanionStyle:String] = [.connect:"◎",.viz:"↗",.basketball:"🏀",.notes:"✉",.focus:"{ }",.battle:"BONK",.setup:"▣",.duo:"×2",.minimize:"zZ",.guide:"❧",.left:"←",.right:"→",.fill:"↔",.topLeft:"↖",.topRight:"↗",.bottomLeft:"↙",.bottomRight:"↘"]
                let text = NSAttributedString(string:tokens[style] ?? "✦",attributes:[.font:NSFont.systemFont(ofSize:style == .battle ? 8 : 12,weight:.bold),.foregroundColor:CompanionDrawing.gold])
                c.saveGState(); c.translateBy(x:x,y:y); text.draw(at:CGPoint(x:-text.size().width/2,y:-6)); c.restoreGState()
            } else {
                let color = tier >= 4 && i % 3 == 0 ? NSColor.systemPurple : i % 2 == 0 ? CompanionDrawing.gold : CompanionDrawing.mint
                c.setFillColor(color.cgColor)
                c.move(to:CGPoint(x:x,y:y+5)); c.addLine(to:CGPoint(x:x+2,y:y+1)); c.addLine(to:CGPoint(x:x+5,y:y)); c.addLine(to:CGPoint(x:x+1,y:y-2)); c.addLine(to:CGPoint(x:x,y:y-5)); c.addLine(to:CGPoint(x:x-2,y:y-1)); c.addLine(to:CGPoint(x:x-5,y:y)); c.addLine(to:CGPoint(x:x-1,y:y+2)); c.closePath(); c.fillPath()
            }
        }
        if tier >= 3 {
            c.setStrokeColor(CompanionDrawing.gold.withAlphaComponent(0.45).cgColor); c.setLineWidth(1.5)
            c.strokeEllipse(in:rect.insetBy(dx:rect.width*0.12,dy:rect.height*0.2))
        }
    }
}
