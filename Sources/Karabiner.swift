import Foundation

enum KarabinerExport {
    static let ruleDescription = "Mini Keyboard app shortcuts"
    /// Rule names from the earlier web version, removed so they don't fight with this app.
    static let legacyDescriptions = ["Mini keyboard shortcuts"]
    static let urlScheme = "minikeyboard"

    static func keyEvent(_ code: String, _ mods: [String]) -> [String: Any] {
        var e: [String: Any] = ["key_code": code]
        let m = Mods.sorted(mods).compactMap { Mods.karabinerTo[$0] }
        if !m.isEmpty { e["modifiers"] = m }
        return e
    }

    /// Karabiner "to" events for an action, or nil if the action isn't complete / possible.
    static func toEvents(_ ref: ActionRef, engine: SnapEngine) -> [[String: Any]]? {
        guard let def = Actions.byID[ref.id] else { return nil }
        switch def.kind {
        case .keys(let code, let mods):
            return [keyEvent(code, mods)]
        case .consumer(let code):
            return [["consumer_key_code": code]]
        case .window(let w):
            switch engine {
            case .app:
                return [["shell_command": "open -g \(urlScheme)://window/\(w.rawValue)"]]
            case .rectangle:
                guard let k = Actions.rectangleKeys[w] else { return nil }
                return [keyEvent(k.0, k.1)]
            case .macos:
                guard let k = Actions.macosKeys[w] else { return nil }
                return [keyEvent(k.0, k.1)]
            }
        case .customShortcut:
            guard let code = ref.params["code"], !code.isEmpty else { return nil }
            return [keyEvent(code, ref.mods)]
        case .openApp:
            guard let n = ref.params["name"]?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty else { return nil }
            return [["shell_command": "open -a " + Shell.quote(n)]]
        case .openURL:
            guard let u = ref.params["url"]?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty else { return nil }
            return [["shell_command": "open " + Shell.openTarget(u)]]
        case .shell:
            guard let c = ref.params["cmd"]?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { return nil }
            return [["shell_command": c]]
        case .workspace(let action):
            return [["shell_command": "open -g \(urlScheme)://grove/\(action.rawValue)"]]
        case .disable:
            return [["key_code": "vk_none"]]
        }
    }

    static func fromEvents(_ src: Source) -> [[String: Any]] {
        switch src {
        case .media(let id):
            guard let m = Media.byID[id] else { return [] }
            var out: [[String: Any]] = [["consumer_key_code": m.consumer]]
            if let twin = m.twin { out.append(["key_code": twin]) }
            return out
        case .key(let code, let mods):
            let mandatory = Mods.sorted(mods).compactMap { Mods.karabinerFrom[$0] }
            var f: [String: Any] = ["key_code": code]
            f["modifiers"] = mandatory.isEmpty ? ["optional": ["any"]] : ["mandatory": mandatory]
            return [f]
        }
    }

    struct Result {
        var rule: [String: Any]
        var count: Int
        var skipped: [String]
    }

    static func build(_ s: PadSettings) -> Result {
        var conditions: [[String: Any]] = []
        if let v = s.vendorID {
            var ident: [String: Any] = ["vendor_id": v]
            if let p = s.productID { ident["product_id"] = p }
            conditions.append(["type": "device_if", "identifiers": [ident]])
        }
        var manipulators: [[String: Any]] = []
        var count = 0
        var skipped: [String] = []
        for id in Controls.order {
            let m = s.mapping(id)
            guard let act = m.action else { continue }
            let name = Controls.capitalized(Controls.info(id).name)
            guard let src = m.source else { skipped.append("\(name): not learned yet"); continue }
            guard let to = toEvents(act, engine: s.snapEngine) else {
                var unsupported = false
                if let def = Actions.byID[act.id], case .window(let w) = def.kind, !Actions.engineSupports(w, s.snapEngine) { unsupported = true }
                skipped.append("\(name): " + (unsupported ? "not available with this window option" : "action isn’t finished"))
                continue
            }
            for from in fromEvents(src) {
                var mnp: [String: Any] = [
                    "description": "\(name) → \(Actions.describe(act))",
                    "type": "basic",
                    "from": from,
                    "to": to
                ]
                if !conditions.isEmpty { mnp["conditions"] = conditions }
                manipulators.append(mnp)
            }
            count += 1
        }
        return Result(rule: ["description": ruleDescription, "manipulators": manipulators], count: count, skipped: skipped)
    }
}

enum KarabinerConfigError: LocalizedError {
    case unreadable(String)
    var errorDescription: String? {
        switch self { case .unreadable(let why): return why }
    }
}

/// Reads and writes ~/.config/karabiner/karabiner.json. Karabiner reloads it on its own when it changes.
struct KarabinerConfig {
    var directory: URL

    static var standard: KarabinerConfig {
        KarabinerConfig(directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/karabiner", isDirectory: true))
    }

    var fileURL: URL { directory.appendingPathComponent("karabiner.json") }
    var backupURL: URL { directory.appendingPathComponent("karabiner.json.before-mini-keyboard") }

    private func load() throws -> [String: Any] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return ["profiles": [["name": "Default profile", "selected": true, "complex_modifications": ["rules": []]] as [String: Any]]]
        }
        let data = try Data(contentsOf: fileURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KarabinerConfigError.unreadable("Karabiner’s settings file isn’t in the expected format, so it was left untouched.")
        }
        return root
    }

    private func save(_ root: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: fileURL.path) && !fm.fileExists(atPath: backupURL.path) {
            try? fm.copyItem(at: fileURL, to: backupURL)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: fileURL, options: .atomic)
    }

    private static func selectedProfileIndex(_ profiles: [[String: Any]]) -> Int {
        profiles.firstIndex { ($0["selected"] as? Bool) == true } ?? 0
    }

    private static func isOurs(_ rule: [String: Any]) -> Bool {
        guard let d = rule["description"] as? String else { return false }
        return d == KarabinerExport.ruleDescription || KarabinerExport.legacyDescriptions.contains(d)
    }

    /// Puts our rule first in the selected profile (replacing any older copy), or removes it when rule is nil.
    func write(rule: [String: Any]?, enabling device: HIDDeviceInfo? = nil) throws {
        var root = try load()
        var profiles = root["profiles"] as? [[String: Any]] ?? []
        if profiles.isEmpty { profiles = [["name": "Default profile", "selected": true]] }
        let idx = KarabinerConfig.selectedProfileIndex(profiles)
        var profile = profiles[idx]
        var cm = profile["complex_modifications"] as? [String: Any] ?? [:]
        var rules = cm["rules"] as? [[String: Any]] ?? []
        let before = rules.count
        rules.removeAll(where: KarabinerConfig.isOurs)
        if rule == nil && rules.count == before { return }   // nothing to remove, don't touch the file
        if let rule = rule { rules.insert(rule, at: 0) }
        cm["rules"] = rules
        profile["complex_modifications"] = cm
        if rule != nil, let device = device {
            // Composite keyboard/mouse devices are ignored by default in Karabiner.
            // Enable only the selected pad's interfaces, retaining all other settings.
            var entries = profile["devices"] as? [[String: Any]] ?? []
            for ident in device.interfaces.sorted(by: { $0.sortKey < $1.sortKey }) {
                if let i = entries.firstIndex(where: { ident.matches($0["identifiers"] as? [String: Any] ?? [:]) }) {
                    entries[i]["ignore"] = false
                } else {
                    entries.append(["identifiers": ident.json, "ignore": false])
                }
            }
            profile["devices"] = entries
        }
        profiles[idx] = profile
        root["profiles"] = profiles
        try save(root)
    }

    func eventsEnabled(for device: HIDDeviceInfo) -> Bool {
        guard let root = try? load(), let profiles = root["profiles"] as? [[String: Any]], !profiles.isEmpty else { return false }
        let entries = profiles[Self.selectedProfileIndex(profiles)]["devices"] as? [[String: Any]] ?? []
        return device.interfaces.allSatisfy { ident in
            let entry = entries.first { ident.matches($0["identifiers"] as? [String: Any] ?? [:]) }
            return !(entry?["ignore"] as? Bool ?? ident.isPointingDevice)
        }
    }

    /// True when our rule is in the selected profile.
    func isInstalled() -> Bool {
        guard let root = try? load(), let profiles = root["profiles"] as? [[String: Any]], !profiles.isEmpty else { return false }
        let p = profiles[KarabinerConfig.selectedProfileIndex(profiles)]
        let rules = (p["complex_modifications"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
        return rules.contains { ($0["description"] as? String) == KarabinerExport.ruleDescription }
    }
}
