import AppKit

struct CompanionPreferences: Codable, Equatable {
    var sound = true
    var animationEnabled = true
    var volume: Double = 0.55
    var rareAnimations = true
    var opponent = "random"

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sound = (try? c.decode(Bool.self, forKey: .sound)) ?? true
        animationEnabled = (try? c.decode(Bool.self, forKey: .animationEnabled)) ?? true
        let saved = (try? c.decode(Double.self, forKey: .volume)) ?? 0.55
        volume = saved.isFinite ? min(1, max(0, saved)) : 0.55
        rareAnimations = (try? c.decode(Bool.self, forKey: .rareAnimations)) ?? true
        let savedOpponent = (try? c.decode(String.self, forKey: .opponent)) ?? "random"
        opponent = CompanionMob(rawValue: savedOpponent) != nil ? savedOpponent : "random"
    }
}

enum CompanionStyle: String, CaseIterable {
    case hop, connect, viz, basketball, notes, focus, battle, setup, duo, minimize, guide, left, fill, right, topLeft, topRight, bottomLeft, bottomRight
    var duration: TimeInterval {
        switch self {
        case .hop: return 0.60
        case .left, .right, .topLeft, .topRight, .bottomLeft, .bottomRight: return 0.34
        case .fill: return 0.36
        case .basketball: return 1.20
        case .battle: return 1.05
        case .setup, .duo: return 0.95
        default: return 0.82
        }
    }
    var title: String {
        switch self {
        case .hop: return "Little hop"
        case .connect: return "1 · Portal"
        case .viz: return "2 · Growing chart"
        case .basketball: return "3 · Basketball"
        case .notes: return "4 · Paper plane"
        case .focus: return "5 · Code focus"
        case .battle: return "6 · Mob battle"
        case .setup: return "7 · Desk conductor"
        case .duo: return "8 · Koala team"
        case .minimize: return "9 / P · Tuck away"
        case .guide: return "Knob · Treasure map"
        case .left: return "10 · Left surf"
        case .fill: return "11 · Star stretch"
        case .right: return "12 · Right dash"
        case .topLeft: return "10 + 11 · Top-left launch"
        case .topRight: return "12 + 11 · Top-right launch"
        case .bottomLeft: return "10 + 9 · Bottom-left slide"
        case .bottomRight: return "12 + 9 · Bottom-right slide"
        }
    }
}

enum CompanionPlan {
    static let size = CGSize(width: 240, height: 190)
    static func style(actionID: String, control: String?) -> CompanionStyle? {
        // Rotations can fire many times a second. Preserve their quiet operation.
        if let control = control, ["Lcw", "Lccw", "Rcw", "Rccw"].contains(control) { return nil }
        guard actionID != "disable" else { return nil }
        switch actionID {
        case "grove_connect": return .connect
        case "grove_viz", "grove_chrome_viz": return .viz
        case "grove_media": return .basketball
        case "grove_write": return .notes
        case "grove_code": return .focus
        case "grove_build": return .battle
        case "grove_setup": return .setup
        case "grove_claude": return .duo
        case "win_min": return .minimize
        case "grove_guide": return .guide
        case "win_left": return .left
        case "win_max": return .fill
        case "win_right": return .right
        case "win_tl": return .topLeft
        case "win_tr": return .topRight
        case "win_bl": return .bottomLeft
        case "win_br": return .bottomRight
        default: return .hop
        }
    }

    static func frame(pointer: CGPoint, visibleFrame: CGRect) -> CGRect {
        let safe = visibleFrame.insetBy(dx: 6, dy: 6)
        let size = CGSize(width: min(Self.size.width, safe.width), height: min(Self.size.height, safe.height))
        // Prefer below-right; flip at an edge instead of covering the pointer.
        var x = pointer.x - 20
        var y = pointer.y - size.height + 24
        if x + size.width > safe.maxX { x = pointer.x - size.width + 20 }
        if y < safe.minY { y = pointer.y - 24 }
        x = min(max(x, safe.minX), safe.maxX - size.width)
        y = min(max(y, safe.minY), safe.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Reserve the menu's entire vertical column, including its shadow. AppKit can
    /// flip or scroll a popup at an edge, so guessing just its vertical bounds is unsafe.
    static func frameBesideMenu(pointer: CGPoint, menuSize: CGSize, visibleFrame: CGRect) -> CGRect? {
        let safe = visibleFrame.insetBy(dx: 6, dy: 6)
        let width = min(menuSize.width, visibleFrame.width)
        let menuX = min(max(pointer.x, visibleFrame.minX), visibleFrame.maxX - width)
        let occupied = CGRect(x: menuX - 24, y: visibleFrame.minY,
                              width: width + 48, height: visibleFrame.height)
        var candidate = frame(pointer: pointer, visibleFrame: visibleFrame)
        for x in [occupied.minX - candidate.width - 12, occupied.maxX + 12] {
            candidate.origin.x = x
            if safe.contains(candidate) { return candidate }
        }
        // On an unusually narrow display, keep the chooser unobstructed.
        return nil
    }

    static func interpolate(_ progress: Double, _ points: [(Double, Double)]) -> Double {
        let p = min(1, max(0, progress))
        guard let last = points.last else { return 0 }
        for i in 1..<points.count where p <= points[i].0 {
            let a = points[i - 1], b = points[i]
            let t = max(0, (p - a.0) / (b.0 - a.0))
            let eased = t * t * (3 - 2 * t)
            return a.1 + (b.1 - a.1) * eased
        }
        return last.1
    }
}

/// Shared drawing code for the live, click-through panel and frame previews.
enum CompanionDrawing {
    static let mint = NSColor(red: 0.56, green: 0.87, blue: 0.70, alpha: 1)
    static let gold = NSColor(red: 0.96, green: 0.77, blue: 0.34, alpha: 1)

    static func draw(style: CompanionStyle, progress p: Double, reducedMotion: Bool, image: NSImage, in rect: CGRect,
                     reaction: CompanionReaction? = nil, mobs: NSImage? = nil, poses: NSImage? = nil) {
        let reaction = reaction ?? CompanionReaction(style: style)
        AdventureAccents.draw(style:style,tier:reaction.tier,progress:p,reduced:reducedMotion,in:rect)
        if ![.hop, .left, .fill, .right, .topLeft, .topRight, .bottomLeft, .bottomRight].contains(style) {
            CompanionScenes.draw(reaction, progress: p, reducedMotion: reducedMotion, mascot: image, mobs: mobs, poses: poses, in: rect)
            return
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.scaleBy(x: rect.width / 184, y: rect.height / 160)
        func curve(_ points: [(Double, Double)]) -> Double { CompanionPlan.interpolate(p, points) }
        let alpha = curve([(0, 0), (0.12, 1), (0.74, 1), (1, 0)])
        context.setAlpha(alpha)
        var x = 92.0, y = 29.0, sx = 1.0, sy = 1.0, tilt = 0.0
        if !reducedMotion {
            switch style {
            case .hop:
                y += curve([(0, 0), (0.12, 0), (0.36, 23), (0.63, 0), (0.79, 4), (1, 0)])
                sx = curve([(0, 0.70), (0.12, 1.10), (0.36, 0.94), (0.63, 1.09), (0.8, 1), (1, 0.88)])
                sy = curve([(0, 0.70), (0.12, 0.80), (0.36, 1.07), (0.63, 0.87), (0.8, 1), (1, 0.88)])
                tilt = curve([(0, -0.07), (0.35, 0.06), (0.7, -0.025), (1, 0)])
                sparkle(context, x: 140, y: 120, radius: 5 * sin(.pi * p), color: gold)
                sparkle(context, x: 43, y: 91, radius: 3.4 * sin(.pi * p), color: mint)
            case .left, .right, .topLeft, .topRight, .bottomLeft, .bottomRight:
                let isLeft = [.left,.topLeft,.bottomLeft].contains(style)
                let d = isLeft ? -1.0 : 1.0
                let corner = [.topLeft,.topRight,.bottomLeft,.bottomRight].contains(style)
                if corner { y += 17 + ([.topLeft,.topRight].contains(style) ? 1 : -1) * curve([(0,-9),(0.6,12),(1,20)]) }
                x += d * curve([(0, -22), (0.17, -16), (0.6, 13), (0.82, 19), (1, 25)])
                y += curve([(0, 0), (0.24, 6), (0.6, 4), (0.83, 0), (1, 0)])
                tilt = -d * curve([(0, 0), (0.3, 0.16), (0.65, 0.1), (1, 0)])
                sx = curve([(0, 0.78), (0.32, 1.09), (0.74, 1), (1, 0.88)])
                sy = curve([(0, 0.78), (0.32, 0.91), (0.74, 1), (1, 0.88)])
                if isLeft {
                    context.setFillColor(mint.cgColor)
                    context.fillEllipse(in: CGRect(x: x - 29, y: 26, width: 58, height: 5))
                }
                let windowX = 92 + d * curve([(0, 29), (0.7, 53), (1, 58)])
                miniWindow(context, frame: CGRect(x: windowX - 23, y: corner ? ([.topLeft,.topRight].contains(style) ? 99 : 44) : 68, width: 46, height: 38), side: style)
                context.setStrokeColor(mint.withAlphaComponent(0.75 * sin(.pi * p)).cgColor)
                context.setLineWidth(2); context.setLineCap(.round)
                for (offset, length) in [(0.0, 18.0), (9.0, 12.0), (18.0, 21.0)] {
                    context.move(to: CGPoint(x: x - d * 39, y: 55 + offset))
                    context.addLine(to: CGPoint(x: x - d * (39 + length), y: 55 + offset))
                }
                context.strokePath()
            case .fill:
                let expansion = curve([(0, 0), (0.22, 0.12), (0.68, 1), (1, 1)])
                let w = 48 + 102 * expansion, h = 34 + 70 * expansion
                let frame = CGRect(x: 92 - w / 2, y: 78 - h / 2, width: w, height: h)
                miniWindow(context, frame: frame, side: .fill)
                sx = curve([(0, 0.68), (0.22, 0.88), (0.6, 1.18), (0.83, 1), (1, 0.93)])
                sy = curve([(0, 0.68), (0.22, 0.83), (0.6, 0.94), (0.83, 1), (1, 0.93)])
                y += curve([(0, 0), (0.5, 7), (0.85, 0), (1, 0)])
                for point in [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)] {
                    sparkle(context, x: point.x, y: point.y, radius: 4.2 * sin(.pi * p), color: gold)
                }
            default: break
            }
        }
        if reaction.rare && !reducedMotion {
            for i in 0..<7 {
                let angle = Double(i) * .pi * 2 / 7 + p * 2
                sparkle(context, x: x + cos(angle) * 56, y: 73 + sin(angle) * 47,
                        radius: 4 * sin(.pi * p), color: i % 2 == 0 ? gold : mint)
            }
            if style == .left || style == .right { tilt += sin(p * .pi * 2) * 0.32 }
        }
        // A small soft landing shadow, never an opaque background or toast.
        context.setFillColor(NSColor.black.withAlphaComponent(0.13).cgColor)
        context.fillEllipse(in: CGRect(x: x - 22, y: 24, width: 44, height: 6))
        context.translateBy(x: x, y: y)
        context.rotate(by: tilt)
        context.scaleBy(x: sx, y: sy)
        image.draw(in: CGRect(x: -43, y: 0, width: 86, height: 86), from: .zero, operation: .sourceOver, fraction: 1)
    }

    private static func miniWindow(_ c: CGContext, frame: CGRect, side: CompanionStyle) {
        c.saveGState(); defer { c.restoreGState() }
        let path = CGPath(roundedRect: frame, cornerWidth: 5, cornerHeight: 5, transform: nil)
        c.setFillColor(NSColor(red: 0.08, green: 0.16, blue: 0.12, alpha: 0.18).cgColor)
        c.addPath(path); c.fillPath()
        c.setStrokeColor(mint.cgColor); c.setLineWidth(1.8)
        c.addPath(path); c.strokePath()
        c.addPath(path); c.clip()
        var selected = frame.insetBy(dx: 3, dy: 3)
        if side != .fill {
            selected.size.width = (frame.width - 6) / 2
            if [.right,.topRight,.bottomRight].contains(side) { selected.origin.x = frame.midX }
            if [.topLeft,.topRight,.bottomLeft,.bottomRight].contains(side) {
                selected.size.height = (frame.height-6)/2
                if [.topLeft,.topRight].contains(side) { selected.origin.y = frame.midY }
            }
        }
        c.setFillColor(mint.withAlphaComponent(0.27).cgColor); c.fill(selected)
        c.setFillColor(gold.cgColor)
        c.fillEllipse(in: CGRect(x: frame.minX + 5, y: frame.maxY - 8, width: 3, height: 3))
    }

    private static func sparkle(_ c: CGContext, x: Double, y: Double, radius r: Double, color: NSColor) {
        guard r > 0 else { return }
        c.setFillColor(color.cgColor)
        c.move(to: CGPoint(x: x, y: y + r))
        c.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x + r * 0.22, y: y + r * 0.22))
        c.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x + r * 0.22, y: y - r * 0.22))
        c.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x - r * 0.22, y: y - r * 0.22))
        c.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x - r * 0.22, y: y + r * 0.22))
        c.closePath(); c.fillPath()
    }
}

private final class CompanionCanvas: NSView {
    let mascot: NSImage
    let mobs: NSImage?
    let poses: NSImage?
    var style = CompanionStyle.hop
    var reaction = CompanionReaction(style: .hop)
    var progress = 0.0
    var reducedMotion = false
    init(image: NSImage) {
        mascot = image
        mobs = Bundle.main.url(forResource: "koala-mobs-atlas", withExtension: "png").flatMap(NSImage.init(contentsOf:))
        poses = Bundle.main.url(forResource: "koala-poses-atlas", withExtension: "png").flatMap(NSImage.init(contentsOf:))
        super.init(frame: CGRect(origin: .zero, size: CompanionPlan.size))
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill(using: .copy)
        CompanionDrawing.draw(style: style, progress: progress, reducedMotion: reducedMotion, image: mascot, in: bounds,
                              reaction: reaction, mobs: mobs, poses: poses)
    }
}

final class ShortcutFeedback {
    static let shared = ShortcutFeedback()
    var preferences = CompanionPreferences() {
        didSet {
            if !preferences.animationEnabled { hide() }
            if !preferences.sound { sound?.stop() }
        }
    }
    private var panel: ShortcutGuidePanel?
    private var canvas: CompanionCanvas?
    private var timer: Timer?
    private var sound: NSSound?
    private var sounds: [NSSound] = []
    private var soundPicker = CompanionSoundPicker()
    private var movementPicker = CompanionSoundPicker()
    private var movementSounds: [NSSound] = []
    private var lastSound = -Double.infinity
    private var began = 0.0
    private var duration = 0.6
    private(set) var lastStyle: CompanionStyle?
    private(set) var reactionCount = 0
    private var selector = CompanionSelector()
    private(set) var lastReaction: CompanionReaction?
    var isVisible: Bool { panel?.isVisible == true }

    init() {
        sounds = CompanionSoundPicker.urls(in: Bundle.main).compactMap { NSSound(contentsOf: $0, byReference: false) }
        movementSounds = CompanionSoundPicker.urls(in:Bundle.main,movement:true).compactMap { NSSound(contentsOf:$0,byReference:false) }
        // Decode once; shortcut actions should never wait on image generation or disk I/O.
        if let url = Bundle.main.url(forResource: "koala-companion", withExtension: "png"), let image = NSImage(contentsOf: url) {
            canvas = CompanionCanvas(image: image)
        }
    }

    func react(actionID: String, control: String? = nil, pointer: CGPoint = NSEvent.mouseLocation) {
        guard let style = CompanionPlan.style(actionID: actionID, control: control) else { return }
        var reaction = selector.next(style: style, preferences: preferences)
        reaction.tier = AdventureStore.shared.tier(for:actionID)
        playReaction(reaction, pointer:pointer, movement:AdventureRules.movement(actionID))
    }

    func play(_ style: CompanionStyle, pointer: CGPoint = NSEvent.mouseLocation, rare: Bool = false,
              mob: CompanionMob? = nil, shot: BasketballShot = .swish) {
        playReaction(CompanionReaction(style: style, rare: rare, mob: mob ?? .slime, shot: rare && style == .basketball ? .dunk : shot), pointer: pointer)
    }
    private func playReaction(_ reaction: CompanionReaction, pointer: CGPoint, movement: Bool? = nil) {
        let style = reaction.style
        lastStyle = style; lastReaction = reaction; reactionCount += 1
        let now = ProcessInfo.processInfo.systemUptime
        if preferences.sound && preferences.volume > 0 && now - lastSound > 0.075 {
            sound?.stop()
            let moving = movement ?? [.left,.right,.fill,.topLeft,.topRight,.bottomLeft,.bottomRight,.minimize,.notes,.focus,.battle,.setup].contains(style)
            if moving { if let index = movementPicker.next(count:movementSounds.count) { sound = movementSounds[index] } }
            else if let index = soundPicker.next(count:sounds.count) { sound = sounds[index] }
            sound?.volume = Float(min(1, max(0, preferences.volume)))
            sound?.play(); lastSound = now
        }
        guard preferences.animationEnabled, let canvas = canvas,
              let index = GrovePlan.screenIndex(at: pointer, frames: NSScreen.screens.map(\.frame)) else { return }
        let screen = NSScreen.screens[index]
        timer?.invalidate()
        let panel = self.panel ?? ShortcutGuidePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Koala companion"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true; panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.contentView = canvas
        panel.setFrame(CompanionPlan.frame(pointer: pointer, visibleFrame: screen.visibleFrame), display: false)
        self.panel = panel
        canvas.style = style
        canvas.reaction = reaction
        canvas.reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        duration = canvas.reducedMotion ? 0.20 : reaction.duration
        began = now
        canvas.progress = 0.04; canvas.needsDisplay = true
        panel.orderFrontRegardless()
        let timer = Timer(timeInterval: 1 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        // Continue drawing and dismissing while the media menu tracks the mouse.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let progress = (ProcessInfo.processInfo.systemUptime - began) / duration
        guard progress < 1 else { hide(); return }
        canvas?.progress = progress; canvas?.needsDisplay = true
    }

    func moveBesideMenu(at point: CGPoint, size: CGSize) {
        guard let panel = panel, panel.isVisible,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return }
        // A chooser on another display cannot obscure this animation.
        guard panel.frame.intersects(screen.frame) else { return }
        if let frame = CompanionPlan.frameBesideMenu(pointer: point, menuSize: size, visibleFrame: screen.visibleFrame) {
            panel.setFrame(frame, display: true)
        } else { hide() }
    }

    func hide() {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil)
    }
    func stopSound() { sound?.stop() }
    func stop() { hide(); stopSound() }
}
