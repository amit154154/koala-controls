import AppKit
import SwiftUI

final class ShortcutGuidePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class LaptopGuide {
    private var panel: NSPanel?
    func show(bindings: [LaptopBinding]) {
        guard let screen = GroveActions.shared.currentScreen() else { return }
        let base = CGSize(width: 900, height: 650)
        let available = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        let scale = min(1, available.width / base.width, available.height / base.height)
        let size = CGSize(width: base.width * scale, height: base.height * scale)
        let panel = self.panel ?? ShortcutGuidePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                            backing: .buffered, defer: false)
        panel.title = "Koala shortcut guide"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: LaptopGuideView(bindings: bindings)
            .frame(width: base.width, height: base.height).scaleEffect(scale)
            .frame(width: size.width, height: size.height))
        panel.setFrame(CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
        self.panel = panel
        panel.orderFrontRegardless()
    }
    func hide() { panel?.orderOut(nil) }
}

struct LaptopGuideView: View {
    let bindings: [LaptopBinding]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private var mainBindings: [LaptopBinding] { bindings.filter { Int($0.key) != nil || $0.key == "P" } }
    private var windowBindings: [LaptopBinding] { bindings.filter { ["[", "]", "\\"].contains($0.key) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Image(systemName: "leaf.fill").font(.system(size: 26)).foregroundColor(GroveTheme.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your Koala shortcuts").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Keep Command + Option held, then press a key. Release to close.")
                        .font(.system(size: 13)).foregroundColor(GroveTheme.muted)
                }
                Spacer()
                Text("⌘ ⌥").font(.system(size: 27, weight: .semibold, design: .rounded)).foregroundColor(GroveTheme.gold)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(mainBindings) { binding in GuideTile(binding: binding) }
            }
            Rectangle().fill(GroveTheme.line).frame(height: 1)
            HStack(spacing: 12) {
                ForEach(windowBindings) { binding in GuideTile(binding: binding) }
            }
            HStack(spacing:12) {
                ForEach(WindowCorner.allCases,id:\.self) { corner in
                    VStack(spacing:4) {
                        Label(corner.title,systemImage:corner.symbol).font(.system(size:12,weight:.semibold))
                        Text("⌘⌥ " + corner.laptop).font(.system(size:14,weight:.bold,design:.rounded)).foregroundColor(GroveTheme.gold)
                    }.frame(maxWidth:.infinity)
                }
            }
            Text("Corners: keep ⌘⌥ held, hold either key and tap its partner. Window singles run on release.")
                .font(.system(size: 12)).foregroundColor(GroveTheme.muted)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundColor(GroveTheme.text)
        .background(RoundedRectangle(cornerRadius: 24).fill(GroveTheme.background))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(GroveTheme.line, lineWidth: 1))
        .preferredColorScheme(.dark)
    }
}

private struct GuideTile: View {
    let binding: LaptopBinding
    var body: some View {
        HStack(spacing: 10) {
            if let artwork = binding.artwork {
                GroveArtwork(name: artwork).frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "keyboard").frame(width: 68, height: 68).foregroundColor(GroveTheme.mint)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(binding.combo).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundColor(GroveTheme.gold)
                Text(binding.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(binding.detail).font(.system(size: 11)).foregroundColor(GroveTheme.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 90, maxHeight: 90, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(GroveTheme.panel))
        .accessibilityElement(children: .combine)
    }
}
