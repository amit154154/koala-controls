import AppKit
import SwiftUI

struct PadGuideEntry: Identifiable {
    let number: Int
    let action: ActionRef?
    var id: Int { number }
    var title: String { action.flatMap { Actions.byID[$0.id]?.cap } ?? "Not assigned" }
    var artwork: String? { GroveAction.from(action)?.rawValue ?? action.flatMap { WindowArtwork.names[$0.id] } }
    static func all(_ settings: PadSettings) -> [PadGuideEntry] {
        (1...12).map { PadGuideEntry(number: $0, action: settings.mapping("k\($0)").action) }
    }
}

final class PadGuide {
    private var panel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    var onVisibility: ((Bool) -> Void)?
    var isVisible: Bool { panel?.isVisible == true }

    func toggle(settings: PadSettings) {
        if isVisible { hide() } else { show(settings: settings) }
    }
    func show(settings: PadSettings) {
        guard let screen = GroveActions.shared.currentScreen() else { return }
        let base = CGSize(width: 900, height: 690)
        let available = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        let scale = min(1, available.width / base.width, available.height / base.height)
        let size = CGSize(width: base.width * scale, height: base.height * scale)
        let panel = self.panel ?? ShortcutGuidePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Mini keyboard guide"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PadGuideView(settings: settings)
            .frame(width: base.width, height: base.height).scaleEffect(scale)
            .frame(width: size.width, height: size.height))
        panel.setFrame(CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2, width: size.width, height: size.height), display: true)
        self.panel = panel
        panel.orderFrontRegardless()
        installDismissMonitors()
        onVisibility?(true)
    }
    private func installDismissMonitors() {
        removeMonitors()
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            if event.type != .keyDown || event.keyCode == 53 { self?.hide() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            if event.type != .keyDown || event.keyCode == 53 { self?.hide() }
            return event
        }
    }
    private func removeMonitors() {
        if let globalMonitor = globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor = localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
    }
    func hide() {
        let wasVisible = isVisible
        panel?.orderOut(nil); removeMonitors()
        if wasVisible { onVisibility?(false) }
    }
}

struct PadGuideView: View {
    let settings: PadSettings
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private func name(_ id: String) -> String {
        let mapping = settings.mapping(id)
        if let action = mapping.action { return Actions.byID[action.id]?.cap ?? "Shortcut" }
        if case .media(let media) = mapping.source { return Media.byID[media]?.label ?? "Not assigned" }
        return "Not assigned"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "keyboard").font(.system(size: 28)).foregroundColor(GroveTheme.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your mini keyboard").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Press a pad key to run it. Press the left knob again or Escape to close.")
                        .font(.system(size: 13)).foregroundColor(GroveTheme.muted)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                knob("Left knob", symbol: "speaker.wave.2.fill", left: name("Lccw"), right: name("Lcw"), press: name("Lpress"))
                knob("Right knob", symbol: "arrow.left.arrow.right", left: name("Rccw"), right: name("Rcw"), press: name("Rpress"))
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(PadGuideEntry.all(settings)) { entry in
                    HStack(spacing: 10) {
                        if let name = entry.artwork {
                            GroveArtwork(name: name).frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            Image(systemName: "square.dashed").font(.system(size: 25)).foregroundColor(GroveTheme.muted.opacity(0.5)).frame(width: 60, height: 60)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(entry.number)").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(GroveTheme.gold)
                            Text(entry.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10).frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(GroveTheme.panel))
                }
            }
            CornerControlsView()
            Text("Corners: hold either key and tap its partner. 9–12 run on release when used alone.")
                .font(.system(size: 12)).foregroundColor(GroveTheme.muted)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundColor(GroveTheme.text)
        .background(RoundedRectangle(cornerRadius: 24).fill(GroveTheme.background))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(GroveTheme.line, lineWidth: 1))
        .preferredColorScheme(.dark)
    }
    private func knob(_ title: String, symbol: String, left: String, right: String, press: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 23)).foregroundColor(GroveTheme.mint)
                .frame(width: 48, height: 48).background(Circle().fill(GroveTheme.background))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .bold))
                Text("↺ \(left)   ↻ \(right)").font(.system(size: 11)).foregroundColor(GroveTheme.muted)
                Text("Press: \(press)").font(.system(size: 12, weight: .semibold)).foregroundColor(GroveTheme.gold)
            }
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity, minHeight: 80, maxHeight: 80)
            .background(RoundedRectangle(cornerRadius: 14).fill(GroveTheme.panel))
    }
}
