import Foundation

// MARK: - The physical controls on the pad

struct ControlInfo {
    let id: String          // "Lccw", "Rpress", "k1" ... "k12"
    let name: String        // "Right knob, turn left"
    let part: String        // "Turn left", "Press"
    let knob: String?       // "L" / "R" for knob parts
    let keyNumber: Int?     // 1...12 for keys
}

enum Controls {
    static let rows = ["Top row", "Second row", "Third row", "Bottom row"]
    static let cols = ["left", "middle", "right"]
    static let knobParts: [(suffix: String, title: String)] = [("ccw", "Turn left"), ("cw", "Turn right"), ("press", "Press")]

    static let all: [ControlInfo] = {
        var out: [ControlInfo] = []
        for knob in ["L", "R"] {
            let side = knob == "L" ? "Left" : "Right"
            for p in knobParts {
                out.append(ControlInfo(id: knob + p.suffix, name: "\(side) knob, \(p.title.lowercased())", part: p.title, knob: knob, keyNumber: nil))
            }
        }
        for i in 0..<12 {
            out.append(ControlInfo(id: "k\(i + 1)", name: "\(rows[i / 3]), \(cols[i % 3]) key", part: "Press", knob: nil, keyNumber: i + 1))
        }
        return out
    }()

    static let byID: [String: ControlInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static let order: [String] = all.map { $0.id }

    static func info(_ id: String) -> ControlInfo { byID[id] ?? ControlInfo(id: id, name: id, part: "", knob: nil, keyNumber: nil) }
    static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}

// MARK: - Modifiers

enum Mods {
    static let order = ["fn", "ctrl", "opt", "shift", "cmd"]
    static let glyph: [String: String] = ["fn": "fn", "ctrl": "⌃", "opt": "⌥", "shift": "⇧", "cmd": "⌘"]
    static let name: [String: String] = ["fn": "fn", "ctrl": "Control", "opt": "Option", "shift": "Shift", "cmd": "Command"]
    static let karabinerTo: [String: String] = ["fn": "fn", "ctrl": "left_control", "opt": "left_option", "shift": "left_shift", "cmd": "left_command"]
    static let karabinerFrom: [String: String] = ["ctrl": "control", "opt": "option", "shift": "shift", "cmd": "command"]

    static func sorted(_ mods: [String]) -> [String] { order.filter { mods.contains($0) } }
    static func text(_ mods: [String]) -> String { sorted(mods).compactMap { glyph[$0] }.joined() }
}

// MARK: - Key names (Karabiner key_code values, checked against Karabiner's source)

enum Keys {
    static let letters = "abcdefghijklmnopqrstuvwxyz".map { String($0) }
    static let digits = "1234567890".map { String($0) }

    static let groups: [(title: String, codes: [String])] = [
        ("Letters", letters),
        ("Numbers", digits),
        ("Function keys", (1...24).map { "f\($0)" }),
        ("Arrows and navigation", ["left_arrow", "right_arrow", "up_arrow", "down_arrow", "home", "end", "page_up", "page_down"]),
        ("Editing", ["return_or_enter", "tab", "spacebar", "delete_or_backspace", "delete_forward", "escape", "caps_lock"]),
        ("Symbols", ["hyphen", "equal_sign", "open_bracket", "close_bracket", "backslash", "semicolon", "quote", "grave_accent_and_tilde", "comma", "period", "slash", "non_us_backslash"]),
        ("Keypad", (1...9).map { "keypad_\($0)" } + ["keypad_0", "keypad_plus", "keypad_hyphen", "keypad_asterisk", "keypad_slash", "keypad_period", "keypad_enter", "keypad_equal_sign", "keypad_num_lock"]),
        ("Other", ["print_screen", "scroll_lock", "pause", "insert", "application", "international1", "international3", "lang1", "lang2"])
    ]

    static let shortLabels: [String: String] = [
        "left_arrow": "←", "right_arrow": "→", "up_arrow": "↑", "down_arrow": "↓", "home": "Home", "end": "End", "page_up": "PgUp", "page_down": "PgDn",
        "return_or_enter": "↩", "tab": "⇥", "spacebar": "Space", "delete_or_backspace": "⌫", "delete_forward": "⌦", "escape": "Esc", "caps_lock": "⇪",
        "hyphen": "-", "equal_sign": "=", "open_bracket": "[", "close_bracket": "]", "backslash": "\\", "semicolon": ";", "quote": "'", "grave_accent_and_tilde": "`",
        "comma": ",", "period": ".", "slash": "/", "non_us_backslash": "§", "keypad_plus": "Num +", "keypad_hyphen": "Num −", "keypad_asterisk": "Num *",
        "keypad_slash": "Num /", "keypad_period": "Num .", "keypad_enter": "Num ↩", "keypad_equal_sign": "Num =", "keypad_num_lock": "Clear",
        "print_screen": "PrtSc", "scroll_lock": "ScrLk", "pause": "Pause", "insert": "Ins", "application": "Menu", "international1": "Ro", "international3": "Yen",
        "lang1": "Lang1", "lang2": "Lang2",
        "left_shift": "Left ⇧", "right_shift": "Right ⇧", "left_control": "Left ⌃", "right_control": "Right ⌃",
        "left_option": "Left ⌥", "right_option": "Right ⌥", "left_command": "Left ⌘", "right_command": "Right ⌘", "fn": "fn"
    ]

    static let longLabels: [String: String] = [
        "left_arrow": "← Left arrow", "right_arrow": "→ Right arrow", "up_arrow": "↑ Up arrow", "down_arrow": "↓ Down arrow",
        "page_up": "Page up", "page_down": "Page down", "return_or_enter": "↩ Return", "tab": "⇥ Tab", "spacebar": "Space",
        "delete_or_backspace": "⌫ Delete", "delete_forward": "⌦ Forward delete", "escape": "Esc", "caps_lock": "⇪ Caps lock",
        "hyphen": "- Minus", "equal_sign": "= Equals", "open_bracket": "[ Left bracket", "close_bracket": "] Right bracket",
        "backslash": "\\ Backslash", "semicolon": "; Semicolon", "quote": "' Quote", "grave_accent_and_tilde": "` Backtick",
        "comma": ", Comma", "period": ". Period", "slash": "/ Slash", "non_us_backslash": "§ Section", "keypad_num_lock": "Keypad clear",
        "print_screen": "Print screen", "scroll_lock": "Scroll lock", "application": "Menu key", "international1": "Ro (JIS)", "international3": "Yen (JIS)"
    ]

    static func short(_ code: String) -> String {
        if let s = shortLabels[code] { return s }
        if code.count == 1 { return code.uppercased() }
        if code.hasPrefix("f"), Int(code.dropFirst()) != nil { return code.uppercased() }
        if code.hasPrefix("keypad_"), let d = code.last, d.isNumber { return "Num \(d)" }
        return code
    }

    static func long(_ code: String) -> String {
        if let s = longLabels[code] { return s }
        if code.hasPrefix("keypad_") { return "Keypad " + short(code).replacingOccurrences(of: "Num ", with: "") }
        return short(code)
    }

    /// macOS virtual key code (kVK_*) → Karabiner key_code. Physical positions, so input language doesn't matter.
    static let fromMacKeyCode: [UInt16: String] = [
        0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h", 0x05: "g", 0x06: "z", 0x07: "x", 0x08: "c", 0x09: "v",
        0x0A: "non_us_backslash", 0x0B: "b", 0x0C: "q", 0x0D: "w", 0x0E: "e", 0x0F: "r", 0x10: "y", 0x11: "t",
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "equal_sign", 0x19: "9", 0x1A: "7",
        0x1B: "hyphen", 0x1C: "8", 0x1D: "0", 0x1E: "close_bracket", 0x1F: "o", 0x20: "u", 0x21: "open_bracket",
        0x22: "i", 0x23: "p", 0x24: "return_or_enter", 0x25: "l", 0x26: "j", 0x27: "quote", 0x28: "k", 0x29: "semicolon",
        0x2A: "backslash", 0x2B: "comma", 0x2C: "slash", 0x2D: "n", 0x2E: "m", 0x2F: "period", 0x30: "tab", 0x31: "spacebar",
        0x32: "grave_accent_and_tilde", 0x33: "delete_or_backspace", 0x35: "escape",
        0x36: "right_command", 0x37: "left_command", 0x38: "left_shift", 0x39: "caps_lock", 0x3A: "left_option",
        0x3B: "left_control", 0x3C: "right_shift", 0x3D: "right_option", 0x3E: "right_control", 0x3F: "fn",
        0x40: "f17", 0x41: "keypad_period", 0x43: "keypad_asterisk", 0x45: "keypad_plus", 0x47: "keypad_num_lock",
        0x4B: "keypad_slash", 0x4C: "keypad_enter", 0x4E: "keypad_hyphen", 0x4F: "f18", 0x50: "f19", 0x51: "keypad_equal_sign",
        0x52: "keypad_0", 0x53: "keypad_1", 0x54: "keypad_2", 0x55: "keypad_3", 0x56: "keypad_4", 0x57: "keypad_5",
        0x58: "keypad_6", 0x59: "keypad_7", 0x5A: "f20", 0x5B: "keypad_8", 0x5C: "keypad_9", 0x5D: "international3",
        0x5E: "international1", 0x60: "f5", 0x61: "f6", 0x62: "f7", 0x63: "f3", 0x64: "f8", 0x65: "f9", 0x66: "lang2",
        0x67: "f11", 0x68: "lang1", 0x69: "f13", 0x6A: "f16", 0x6B: "f14", 0x6D: "f10", 0x6F: "f12", 0x71: "f15",
        0x72: "insert", 0x73: "home", 0x74: "page_up", 0x75: "delete_forward", 0x76: "f4", 0x77: "end", 0x78: "f2",
        0x79: "page_down", 0x7A: "f1", 0x7B: "left_arrow", 0x7C: "right_arrow", 0x7D: "down_arrow", 0x7E: "up_arrow"
    ]

    static let modifierKeyCodes: Set<UInt16> = [0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F]
}

// MARK: - Media keys a knob or key can send

struct MediaKey {
    let id: String
    let label: String
    let consumer: String     // consumer_key_code
    let twin: String?        // keyboard-page key_code that some pads send instead
}

enum Media {
    static let all: [MediaKey] = [
        MediaKey(id: "vol_up", label: "Volume up", consumer: "volume_increment", twin: "volume_up"),
        MediaKey(id: "vol_down", label: "Volume down", consumer: "volume_decrement", twin: "volume_down"),
        MediaKey(id: "mute", label: "Mute", consumer: "mute", twin: nil),
        MediaKey(id: "play", label: "Play/pause", consumer: "play_or_pause", twin: nil),
        MediaKey(id: "next", label: "Next track", consumer: "scan_next_track", twin: nil),
        MediaKey(id: "prev", label: "Previous track", consumer: "scan_previous_track", twin: nil),
        MediaKey(id: "bright_up", label: "Brightness up", consumer: "display_brightness_increment", twin: nil),
        MediaKey(id: "bright_down", label: "Brightness down", consumer: "display_brightness_decrement", twin: nil)
    ]
    static let byID: [String: MediaKey] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    /// NX_KEYTYPE_* values found in NSSystemDefined media-key events
    static let fromNXKeyType: [Int: String] = [0: "vol_up", 1: "vol_down", 2: "bright_up", 3: "bright_down", 7: "mute", 16: "play", 17: "next", 18: "prev"]
}

// MARK: - What a control sends

enum Source: Codable, Equatable {
    case key(code: String, mods: [String])
    case media(String)

    var signature: String {
        switch self {
        case .key(let code, let mods): return "k:" + Mods.sorted(mods).joined(separator: "+") + ":" + code
        case .media(let id): return "m:" + id
        }
    }

    var text: String {
        switch self {
        case .key(let code, let mods): return Mods.text(mods) + Keys.short(code)
        case .media(let id): return Media.byID[id]?.label ?? id
        }
    }
}

// MARK: - Window actions (done by this app, or by Rectangle / macOS)

enum WindowAction: String, CaseIterable, Codable {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case maximize, almostMaximize, center, restore
    case nextDisplay, previousDisplay
}

enum SnapEngine: String, Codable, CaseIterable {
    case app, rectangle, macos

    var title: String {
        switch self {
        case .app: return "This app"
        case .rectangle: return "Rectangle"
        case .macos: return "macOS"
        }
    }
}

// MARK: - Action catalog

struct ActionRef: Codable, Equatable {
    var id: String
    var params: [String: String] = [:]
    var mods: [String] = []

    init(id: String, params: [String: String] = [:], mods: [String] = []) {
        self.id = id; self.params = params; self.mods = mods
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        params = try c.decodeIfPresent([String: String].self, forKey: .params) ?? [:]
        mods = try c.decodeIfPresent([String].self, forKey: .mods) ?? []
    }
}

struct ActionDef {
    enum Kind {
        case keys(String, [String])
        case consumer(String)
        case window(WindowAction)
        case workspace(GroveAction)
        case customShortcut, openApp, openURL, shell, disable
    }
    let id: String
    let group: String
    let label: String
    let cap: String
    let glyph: String?
    let kind: Kind

    init(_ id: String, _ group: String, _ label: String, cap: String? = nil, glyph: String? = nil, _ kind: Kind) {
        self.id = id; self.group = group; self.label = label; self.cap = cap ?? label; self.glyph = glyph; self.kind = kind
    }

    var isCustom: Bool {
        switch kind { case .customShortcut, .openApp, .openURL, .shell: return true; default: return false }
    }
}

enum Actions {
    static let groups = ["Your grove", "Tabs", "Windows", "Desktop and apps", "Media", "Editing", "Navigation", "Your own"]

    static let all: [ActionDef] = GroveAction.allCases.map { ActionDef($0.actionID, "Your grove", $0.title, .workspace($0)) } + [
        ActionDef("tab_next", "Tabs", "Next tab", glyph: "→", .keys("tab", ["ctrl"])),
        ActionDef("tab_prev", "Tabs", "Previous tab", cap: "Prev tab", glyph: "←", .keys("tab", ["ctrl", "shift"])),
        ActionDef("tab_new", "Tabs", "New tab", .keys("t", ["cmd"])),
        ActionDef("tab_close", "Tabs", "Close tab", .keys("w", ["cmd"])),
        ActionDef("tab_reopen", "Tabs", "Reopen closed tab", cap: "Reopen tab", .keys("t", ["cmd", "shift"])),

        ActionDef("win_left", "Windows", "Window to left half", cap: "Left half", glyph: "◧", .window(.left)),
        ActionDef("win_right", "Windows", "Window to right half", cap: "Right half", glyph: "◨", .window(.right)),
        ActionDef("win_top", "Windows", "Window to top half", cap: "Top half", glyph: "⬒", .window(.top)),
        ActionDef("win_bottom", "Windows", "Window to bottom half", cap: "Bottom half", glyph: "⬓", .window(.bottom)),
        ActionDef("win_tl", "Windows", "Window to top-left quarter", cap: "Top left", .window(.topLeft)),
        ActionDef("win_tr", "Windows", "Window to top-right quarter", cap: "Top right", .window(.topRight)),
        ActionDef("win_bl", "Windows", "Window to bottom-left quarter", cap: "Bottom left", .window(.bottomLeft)),
        ActionDef("win_br", "Windows", "Window to bottom-right quarter", cap: "Bottom right", .window(.bottomRight)),
        ActionDef("win_l3", "Windows", "Window to left third", cap: "Left third", .window(.leftThird)),
        ActionDef("win_c3", "Windows", "Window to center third", cap: "Mid third", .window(.centerThird)),
        ActionDef("win_r3", "Windows", "Window to right third", cap: "Right third", .window(.rightThird)),
        ActionDef("win_l23", "Windows", "Window to left two-thirds", cap: "Left ⅔", .window(.leftTwoThirds)),
        ActionDef("win_r23", "Windows", "Window to right two-thirds", cap: "Right ⅔", .window(.rightTwoThirds)),
        ActionDef("win_max", "Windows", "Fill the screen", cap: "Fill screen", .window(.maximize)),
        ActionDef("win_almost", "Windows", "Almost fill the screen", cap: "Almost full", .window(.almostMaximize)),
        ActionDef("win_center", "Windows", "Center window", cap: "Center", .window(.center)),
        ActionDef("win_restore", "Windows", "Restore window size", cap: "Restore", .window(.restore)),
        ActionDef("win_next_display", "Windows", "Window to next display", cap: "Next screen", .window(.nextDisplay)),
        ActionDef("win_prev_display", "Windows", "Window to previous display", cap: "Prev screen", .window(.previousDisplay)),
        ActionDef("win_full", "Windows", "Toggle full screen", cap: "Full screen", .keys("f", ["ctrl", "cmd"])),
        ActionDef("win_min", "Windows", "Minimize window", cap: "Minimize", .keys("m", ["cmd"])),
        ActionDef("app_hide", "Windows", "Hide app", .keys("h", ["cmd"])),
        ActionDef("app_quit", "Windows", "Quit app", .keys("q", ["cmd"])),

        ActionDef("mission", "Desktop and apps", "Mission Control", .keys("up_arrow", ["ctrl"])),
        ActionDef("app_windows", "Desktop and apps", "All windows of this app", cap: "App windows", .keys("down_arrow", ["ctrl"])),
        ActionDef("space_next", "Desktop and apps", "Next desktop", .keys("right_arrow", ["ctrl"])),
        ActionDef("space_prev", "Desktop and apps", "Previous desktop", cap: "Prev desktop", .keys("left_arrow", ["ctrl"])),
        ActionDef("app_last", "Desktop and apps", "Switch to last app", cap: "Last app", .keys("tab", ["cmd"])),
        ActionDef("spotlight", "Desktop and apps", "Spotlight search", cap: "Spotlight", .keys("spacebar", ["cmd"])),
        ActionDef("shot_area", "Desktop and apps", "Screenshot of an area", cap: "Screenshot", .keys("4", ["cmd", "shift"])),
        ActionDef("shot_tool", "Desktop and apps", "Screenshot toolbar", cap: "Shot tools", .keys("5", ["cmd", "shift"])),
        ActionDef("emoji", "Desktop and apps", "Emoji picker", cap: "Emoji", .keys("spacebar", ["ctrl", "cmd"])),
        ActionDef("lock", "Desktop and apps", "Lock screen", cap: "Lock", .keys("q", ["ctrl", "cmd"])),

        ActionDef("m_vol_up", "Media", "Volume up", cap: "Vol +", .consumer("volume_increment")),
        ActionDef("m_vol_down", "Media", "Volume down", cap: "Vol −", .consumer("volume_decrement")),
        ActionDef("m_mute", "Media", "Mute", .consumer("mute")),
        ActionDef("m_play", "Media", "Play/pause", cap: "Play/Pause", .consumer("play_or_pause")),
        ActionDef("m_next", "Media", "Next track", .consumer("scan_next_track")),
        ActionDef("m_prev", "Media", "Previous track", cap: "Prev track", .consumer("scan_previous_track")),
        ActionDef("m_bright_up", "Media", "Brightness up", cap: "Bright +", .consumer("display_brightness_increment")),
        ActionDef("m_bright_down", "Media", "Brightness down", cap: "Bright −", .consumer("display_brightness_decrement")),

        ActionDef("copy", "Editing", "Copy", .keys("c", ["cmd"])),
        ActionDef("paste", "Editing", "Paste", .keys("v", ["cmd"])),
        ActionDef("cut", "Editing", "Cut", .keys("x", ["cmd"])),
        ActionDef("undo", "Editing", "Undo", .keys("z", ["cmd"])),
        ActionDef("redo", "Editing", "Redo", .keys("z", ["cmd", "shift"])),
        ActionDef("select_all", "Editing", "Select all", .keys("a", ["cmd"])),
        ActionDef("save", "Editing", "Save", .keys("s", ["cmd"])),
        ActionDef("find", "Editing", "Find", .keys("f", ["cmd"])),
        ActionDef("zoom_in", "Editing", "Zoom in", cap: "Zoom +", .keys("equal_sign", ["cmd"])),
        ActionDef("zoom_out", "Editing", "Zoom out", cap: "Zoom −", .keys("hyphen", ["cmd"])),
        ActionDef("zoom_reset", "Editing", "Actual size", cap: "Zoom 100%", .keys("0", ["cmd"])),

        ActionDef("nav_up", "Navigation", "Arrow up", cap: "Up", glyph: "↑", .keys("up_arrow", [])),
        ActionDef("nav_down", "Navigation", "Arrow down", cap: "Down", glyph: "↓", .keys("down_arrow", [])),
        ActionDef("nav_left", "Navigation", "Arrow left", cap: "Left", glyph: "←", .keys("left_arrow", [])),
        ActionDef("nav_right", "Navigation", "Arrow right", cap: "Right", glyph: "→", .keys("right_arrow", [])),
        ActionDef("page_up", "Navigation", "Page up", .keys("page_up", [])),
        ActionDef("page_down", "Navigation", "Page down", .keys("page_down", [])),
        ActionDef("word_left", "Navigation", "Previous word", cap: "Word ←", .keys("left_arrow", ["opt"])),
        ActionDef("word_right", "Navigation", "Next word", cap: "Word →", .keys("right_arrow", ["opt"])),
        ActionDef("back", "Navigation", "Back (browser, Finder)", cap: "Back", .keys("open_bracket", ["cmd"])),
        ActionDef("forward", "Navigation", "Forward (browser, Finder)", cap: "Forward", .keys("close_bracket", ["cmd"])),

        ActionDef("custom", "Your own", "A shortcut of your choice…", cap: "Shortcut", .customShortcut),
        ActionDef("open_app", "Your own", "Open an app…", cap: "Open app", .openApp),
        ActionDef("open_url", "Your own", "Open a website or file…", cap: "Open link", .openURL),
        ActionDef("shell", "Your own", "Run a Terminal command…", cap: "Script", .shell),
        ActionDef("disable", "Your own", "Turn this key off", cap: "Off", .disable)
    ]

    static let byID: [String: ActionDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static func inGroup(_ g: String) -> [ActionDef] { all.filter { $0.group == g } }

    /// Short legend printed on the drawing's keycap.
    static func cap(for ref: ActionRef) -> (cap: String, glyph: String?) {
        guard let def = byID[ref.id] else { return ("?", nil) }
        switch def.kind {
        case .customShortcut:
            if let code = ref.params["code"], !code.isEmpty { return (Mods.text(ref.mods) + Keys.short(code), nil) }
        case .openApp:
            if let n = ref.params["name"]?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return (n, nil) }
        case .openURL:
            if let u = ref.params["url"]?.trimmingCharacters(in: .whitespaces), !u.isEmpty { return (shortURL(u), nil) }
        default: break
        }
        return (def.cap, def.glyph)
    }

    static func describe(_ ref: ActionRef) -> String {
        guard let def = byID[ref.id] else { return ref.id }
        if def.isCustom {
            let base = def.label.replacingOccurrences(of: "…", with: "")
            return "\(base) (\(cap(for: ref).cap))"
        }
        return def.label
    }

    static func shortURL(_ u: String) -> String {
        var s = u
        for p in ["https://", "http://", "www."] where s.lowercased().hasPrefix(p) { s = String(s.dropFirst(p.count)) }
        return s.split(whereSeparator: { "/?#".contains($0) }).first.map(String.init) ?? u
    }

    // Default shortcuts Rectangle ("Recommended" set) and macOS 15+ listen for.
    static let rectangleKeys: [WindowAction: (String, [String])] = [
        .left: ("left_arrow", ["ctrl", "opt"]), .right: ("right_arrow", ["ctrl", "opt"]),
        .top: ("up_arrow", ["ctrl", "opt"]), .bottom: ("down_arrow", ["ctrl", "opt"]),
        .topLeft: ("u", ["ctrl", "opt"]), .topRight: ("i", ["ctrl", "opt"]),
        .bottomLeft: ("j", ["ctrl", "opt"]), .bottomRight: ("k", ["ctrl", "opt"]),
        .leftThird: ("d", ["ctrl", "opt"]), .centerThird: ("f", ["ctrl", "opt"]), .rightThird: ("g", ["ctrl", "opt"]),
        .leftTwoThirds: ("e", ["ctrl", "opt"]), .rightTwoThirds: ("t", ["ctrl", "opt"]),
        .maximize: ("return_or_enter", ["ctrl", "opt"]), .center: ("c", ["ctrl", "opt"]),
        .restore: ("delete_or_backspace", ["ctrl", "opt"]),
        .nextDisplay: ("right_arrow", ["ctrl", "opt", "cmd"]), .previousDisplay: ("left_arrow", ["ctrl", "opt", "cmd"])
    ]
    static let macosKeys: [WindowAction: (String, [String])] = [
        .left: ("left_arrow", ["fn", "ctrl"]), .right: ("right_arrow", ["fn", "ctrl"]),
        .top: ("up_arrow", ["fn", "ctrl"]), .bottom: ("down_arrow", ["fn", "ctrl"]),
        .maximize: ("f", ["fn", "ctrl"]), .center: ("c", ["fn", "ctrl"]), .restore: ("r", ["fn", "ctrl"])
    ]

    static func engineSupports(_ w: WindowAction, _ engine: SnapEngine) -> Bool {
        switch engine {
        case .app: return true
        case .rectangle: return rectangleKeys[w] != nil
        case .macos: return macosKeys[w] != nil
        }
    }
}

// MARK: - Shell helpers

enum Shell {
    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func openTarget(_ t: String) -> String {
        if t.hasPrefix("~/") { return "~/" + quote(String(t.dropFirst(2))) }
        if t.hasPrefix("/") { return quote(t) }
        if let r = t.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression), r.lowerBound == t.startIndex { return quote(t) }
        return quote("https://" + t)
    }
}

// MARK: - Saved settings

struct ControlMapping: Codable, Equatable {
    var source: Source?
    var action: ActionRef?

    init(source: Source? = nil, action: ActionRef? = nil) { self.source = source; self.action = action }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try? c.decodeIfPresent(Source.self, forKey: .source)
        action = try? c.decodeIfPresent(ActionRef.self, forKey: .action)
    }
}

enum ShortcutEngine: String, Codable, CaseIterable {
    case native, karabiner
    var title: String { self == .native ? "macOS (no driver)" : "Karabiner" }
}

struct PadSettings: Codable, Equatable {
    var controls: [String: ControlMapping]
    var vendorID: Int?
    var productID: Int?
    var deviceName: String?
    var snapEngine: SnapEngine
    var enabled: Bool
    var shortcutEngine: ShortcutEngine = .native
    var laptopShortcutsEnabled: Bool = false
    var companion = CompanionPreferences()

    static func defaults() -> PadSettings {
        var c: [String: ControlMapping] = [:]
        for id in Controls.order { c[id] = ControlMapping() }
        c["Rccw"]?.action = ActionRef(id: "tab_prev")
        c["Rcw"]?.action = ActionRef(id: "tab_next")
        c["k10"]?.action = ActionRef(id: "win_left")
        c["k12"]?.action = ActionRef(id: "win_right")
        let starter:[String:String] = ["k1":"grove_connect","k2":"grove_viz","k3":"grove_media","k4":"grove_write","k5":"grove_code","k6":"grove_build","k7":"grove_setup","k8":"grove_claude","k9":"win_min","k10":"win_left","k11":"win_max","k12":"win_right","Lpress":"grove_guide","Rpress":"grove_chrome_viz"]
        for (key,action) in starter { c[key]?.action=ActionRef(id:action) }
        return PadSettings(controls: c, vendorID: nil, productID: nil, deviceName: nil, snapEngine: .app, enabled: true)
    }

    init(controls: [String: ControlMapping], vendorID: Int?, productID: Int?, deviceName: String?, snapEngine: SnapEngine, enabled: Bool) {
        self.controls = controls; self.vendorID = vendorID; self.productID = productID
        self.deviceName = deviceName; self.snapEngine = snapEngine; self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let d = PadSettings.defaults()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var controls = d.controls
        if let saved = try? c.decodeIfPresent([String: ControlMapping].self, forKey: .controls) {
            for (k, v) in saved where controls[k] != nil { controls[k] = v }
        }
        self.controls = controls
        vendorID = try? c.decodeIfPresent(Int.self, forKey: .vendorID)
        productID = try? c.decodeIfPresent(Int.self, forKey: .productID)
        deviceName = try? c.decodeIfPresent(String.self, forKey: .deviceName)
        snapEngine = (try? c.decodeIfPresent(SnapEngine.self, forKey: .snapEngine)) ?? .app
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        shortcutEngine = (try? c.decodeIfPresent(ShortcutEngine.self, forKey: .shortcutEngine)) ?? .native
        laptopShortcutsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .laptopShortcutsEnabled)) ?? false
        companion = (try? c.decodeIfPresent(CompanionPreferences.self, forKey: .companion)) ?? CompanionPreferences()
    }

    func mapping(_ id: String) -> ControlMapping { controls[id] ?? ControlMapping() }

    /// Controls that send exactly the same thing as another control.
    func clashes() -> [String: [String]] {
        var by: [String: [String]] = [:]
        for id in Controls.order { if let s = mapping(id).source { by[s.signature, default: []].append(id) } }
        var out: [String: [String]] = [:]
        for (_, ids) in by where ids.count > 1 { for id in ids { out[id] = ids.filter { $0 != id } } }
        return out
    }
}

// MARK: - Status of a single control

enum RowStatus: Equatable {
    case empty, learnedOnly, needsSource, clash([String]), unfinished, unsupported, ready

    var text: String {
        switch self {
        case .empty: return ""
        case .learnedOnly: return "Learned, no action yet"
        case .needsSource: return "Learn what it sends"
        case .clash(let others): return "Sends the same as " + others.map { Controls.info($0).name.lowercased() }.joined(separator: ", ")
        case .unfinished: return "Finish setting the action"
        case .unsupported: return "Not available with this window option"
        case .ready: return "Ready"
        }
    }
    var isProblem: Bool {
        switch self { case .needsSource, .clash, .unfinished, .unsupported: return true; default: return false }
    }
}

extension PadSettings {
    func status(_ id: String, clashes: [String: [String]]? = nil) -> RowStatus {
        let m = mapping(id)
        guard let act = m.action else { return m.source == nil ? .empty : .learnedOnly }
        guard m.source != nil else { return .needsSource }
        if let others = (clashes ?? self.clashes())[id] { return .clash(others) }
        let engine: SnapEngine = shortcutEngine == .native ? .app : snapEngine
        if let def = Actions.byID[act.id], case .window(let w) = def.kind, !Actions.engineSupports(w, engine) { return .unsupported }
        if KarabinerExport.toEvents(act, engine: engine) == nil { return .unfinished }
        if shortcutEngine == .native && !NativePlan.build(self).bindings.contains(where: { $0.control == id }) { return .unsupported }
        return .ready
    }
}
