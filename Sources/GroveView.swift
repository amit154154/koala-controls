import AppKit
import SwiftUI

enum GroveTheme {
    static let background = Color(hex: 0x141D18)
    static let panel = Color(hex: 0x1E2A24)
    static let line = Color(hex: 0x35483D)
    static let mint = Color(hex: 0x8ECEAD)
    static let gold = Color(hex: 0xE6BE69)
    static let text = Color(hex: 0xEDF2EB)
    static let muted = Color(hex: 0xA8B8AD)
}

struct GroveArtwork: View {
    let name: String
    init(action: GroveAction) { name = action == .chromeViz ? "viz" : action.rawValue }
    init(name: String) { self.name = name == "chrome_viz" ? "viz" : name }
    private static let images: [String: NSImage] = Dictionary(uniqueKeysWithValues: (GroveAction.allCases.map(\.rawValue) + ["left", "fill", "right", "companion"]).compactMap { name in
        guard let url = Bundle.main.url(forResource: "koala-" + name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        return (name, image)
    })
    var body: some View {
        if let image = Self.images[name] {
            Image(nsImage: image)
                .resizable().interpolation(.high).scaledToFit()
                .accessibilityHidden(true)
        } else if name == "minimize" {
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.12).fill(GroveTheme.panel)
                    if let image = Self.images["companion"] {
                        Image(nsImage: image).resizable().scaledToFit()
                            .frame(width: size * 0.68, height: size * 0.68).offset(y: -size * 0.12)
                    }
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: size * 0.23, weight: .bold))
                        .foregroundColor(GroveTheme.mint)
                        .frame(width: size * 0.48, height: size * 0.36)
                        .background(RoundedRectangle(cornerRadius: size * 0.06).fill(GroveTheme.background))
                        .overlay(RoundedRectangle(cornerRadius: size * 0.06).stroke(GroveTheme.mint, lineWidth: max(1, size * 0.012)))
                        .offset(y: size * 0.22)
                }.frame(width: geometry.size.width, height: geometry.size.height)
            }.accessibilityHidden(true)
        } else if name == "guide" {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(GroveTheme.panel)
                Image(systemName: "keyboard").resizable().scaledToFit().padding(20).foregroundColor(GroveTheme.mint)
                Image(systemName: "questionmark.circle.fill").font(.system(size: 30)).foregroundColor(GroveTheme.gold).offset(y: -22)
            }.accessibilityHidden(true)
        }
    }
}

struct GrovePreview: View {
    @EnvironmentObject var model: AppModel
    let action: GroveAction
    private var previewCaption: String {
        switch action {
        case .media: return "YouTube Music · Spotify · YouTube · GDN · Netflix · HBO Max · NBA"
        case .viz: return "localhost:8300"
        case .chromeViz: return "In Google Chrome · tab knob press"
        case .setup: return "MacBook → notes · middle → code · right → build"
        case .guide: return "Left knob press · rotation stays volume"
        default: return "Same action as the instance widget"
        }
    }
    private var previewSymbol: String {
        switch action {
        case .media: return "play.rectangle"
        case .viz, .chromeViz: return "globe"
        case .setup: return "display.2"
        case .guide: return "keyboard"
        default: return "bolt.horizontal"
        }
    }

    var body: some View {
        HStack(spacing: 20) {
            GroveArtwork(action: action)
                .frame(width: 192, height: 192)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(Controls.info(model.selection).keyNumber.map { "Key \($0)" } ?? (model.selection.hasPrefix("R") ? "Right knob press" : "Left knob press"))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(GroveTheme.mint.opacity(0.12)))
                    Text("Your grove").font(.caption).foregroundColor(GroveTheme.muted)
                }
                .foregroundColor(GroveTheme.mint)
                Text(action.title).font(.system(size: 25, weight: .bold, design: .rounded))
                Text(action.detail).font(.system(size: 13)).foregroundColor(GroveTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if !action.apps.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(action.apps, id: \.id) { app in
                            HStack(spacing: 6) {
                                GroveAppIcon(bundleID: app.id).frame(width: 22, height: 22)
                                Text(app.name == "Visual Studio Code" ? "VS Code" : app.name.replacingOccurrences(of: "Google ", with: ""))
                                    .font(.system(size: 11, weight: .semibold))
                            }
                                .frame(maxWidth: .infinity).frame(height: 33)
                                .background(RoundedRectangle(cornerRadius: 5).fill(GroveTheme.mint.opacity(0.1)))
                        }
                    }
                    .padding(5)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(GroveTheme.line, lineWidth: 1))
                    Text(action == .claude ? "In your active VS Code SSH window · Key 8" : "Mobile: MacBook Space · Desk: display under your mouse")
                        .font(.caption2).foregroundColor(GroveTheme.muted)
                } else {
                    Label(previewCaption, systemImage: previewSymbol)
                        .font(.caption).foregroundColor(GroveTheme.mint)
                }
                if action == .media {
                    Button("Open media menu…") { NativeAction.perform(ActionRef(id: action.actionID), control: action.key) }
                        .font(.caption.weight(.semibold)).padding(.top, 4)
                } else if [.write, .code, .build].contains(action) {
                    Button("Open workspace") { NativeAction.perform(ActionRef(id: action.actionID), control: action.key) }
                        .font(.caption.weight(.semibold)).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22).fill(GroveTheme.panel))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(GroveTheme.line, lineWidth: 1))
    }
}


/// Exact installed-app icons, kept crisp independently of the illustrated preview.
struct GroveAppIcon: View {
    let bundleID: String
    private static let names = ["md.obsidian": "obsidian", "com.tinyspeck.slackmacgap": "slack",
                                "dev.zed.Zed": "zed", "com.google.Chrome": "chrome",
                                "com.microsoft.VSCode": "vscode", "com.apple.shortcuts": "shortcuts"]
    private static let icons: [String: NSImage] = Dictionary(uniqueKeysWithValues: names.compactMap { id, name in
        guard let url = Bundle.main.url(forResource: "app-" + name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        return (id, image)
    })
    var body: some View {
        if let icon = Self.icons[bundleID] {
            Image(nsImage: icon).resizable().interpolation(.high).scaledToFit().accessibilityHidden(true)
        }
    }
}

enum WindowArtwork {
    static let names = ["win_left": "left", "win_max": "fill", "win_right": "right", "win_min": "minimize"]
}

struct WindowArtworkPreview: View {
    let actionID: String
    private var name: String { WindowArtwork.names[actionID] ?? "fill" }
    private var title: String { actionID == "win_min" ? "Minimize window" : (actionID == "win_max" ? "Fill screen" : (actionID == "win_right" ? "Right half" : "Left half")) }
    private var detail: String {
        if actionID == "win_min" { return "Tuck your current window into the Dock. Your app stays running, ready to bring back." }
        return actionID == "win_max" ? "Expand your focused window to fill its display, keeping the menu bar and Dock available."
            : "Move your focused window to the \(actionID == "win_right" ? "right" : "left") half of its display."
    }
    var body: some View {
        HStack(spacing: 20) {
            GroveArtwork(name: name).frame(width: 192, height: 192)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 25, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.system(size: 13)).foregroundColor(GroveTheme.muted)
                Label(actionID == "win_min" ? "Minimize to Dock · ⌘M" : "Your current app, neatly placed", systemImage: actionID == "win_min" ? "arrow.down.to.line.compact" : (actionID == "win_max" ? "arrow.up.left.and.arrow.down.right" : "rectangle.split.2x1"))
                    .font(.caption).foregroundColor(GroveTheme.mint)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(18)
            .background(RoundedRectangle(cornerRadius: 22).fill(GroveTheme.panel))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(GroveTheme.line, lineWidth: 1))
    }
}
