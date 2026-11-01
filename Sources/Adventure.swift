import Foundation
import Combine

enum ShortcutOrigin: String, Codable {
    case miniKeyboard, macKeyboard, phone, app, keyboardRelay
    var title: String { switch self {
    case .miniKeyboard: return "Mini keyboard"
    case .macKeyboard: return "Mac keyboard"
    case .phone: return "iPhone remote"
    case .app: return "App"
    case .keyboardRelay: return "Relay key · origin unverified"
    } }
}

enum AdventureRules {
    static func canonical(_ id: String) -> String { id == "grove_chrome_viz" ? "grove_viz" : id }
    static func threshold(_ level: Int, player: Bool) -> Int { let l = max(1, min(10_000, level)); return (player ? 20 : 5) * l * (l - 1) }
    static func level(_ xp: Int, player: Bool) -> Int {
        let factor: Double = player ? 20.0 : 5.0
        let uses = Double(max(0, xp))
        let root = (1.0 + sqrt(1.0 + 4.0 * uses / factor)) / 2.0
        return max(1, Int(root))
    }
    static func tier(_ level: Int) -> Int { level >= 10 ? 4 : level >= 5 ? 3 : level >= 3 ? 2 : level >= 2 ? 1 : 0 }
    static func title(_ level: Int) -> String { level >= 15 ? "Keeper of the cosmic grove" : level >= 10 ? "Koala of questionable power" : level >= 5 ? "Certified chaos coordinator" : level >= 3 ? "Branch manager" : level >= 2 ? "Eucalyptus enthusiast" : "Tiny paws, big plans" }
    static let accents = ["Your original adventure", "Leaf trail", "Star burst", "Golden orbit", "Cosmic grove"]
    static func flavor(_ id: String) -> String {
        switch canonical(id) {
        case "grove_connect": return "Portal passport"
        case "grove_viz": return "Stonks, but make it koala"
        case "grove_media": return "Courtside koala"
        case "grove_write": return "Paper-plane postmaster"
        case "grove_code": return "One more line, one more leaf"
        case "grove_build": return "Slime eviction specialist"
        case "grove_setup": return "Three-screen orchestra"
        case "grove_claude": return "Two brains, zero spare branches"
        case "win_min": return "Professional hide-and-seek"
        case "win_left", "win_right", "win_tl", "win_tr", "win_bl", "win_br", "win_max": return "Window parkour"
        default: return "Little shortcut, big adventure"
        }
    }
    static func movement(_ id: String) -> Bool {
        id.hasPrefix("win_") || id.hasPrefix("space_") || ["grove_write","grove_code","grove_build","grove_setup","app_hide"].contains(id)
    }
}

struct ShortcutClick: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let action: String
    let name: String
    let trigger: String
    let origin: ShortcutOrigin
    let keyboardConnected: Bool
    var result: String
}
struct AdventureRecord: Codable {
    let schema: Int
    let event: String
    let timestamp: Date
    let click: ShortcutClick
}
struct AdventureNotice: Codable, Identifiable {
    let id: String
    let scope: String
    let action: String
    let name: String
    let level: Int
    let unlocked: String
}
struct AdventureMastery {
    var uses = 0
    var level: Int { AdventureRules.level(uses, player: false) }
}

/// Local shortcut journal. Never receives ordinary keystrokes, typed text, URLs,
/// app-window titles, shell contents or phone credentials.
final class AdventureStore: ObservableObject {
    static let shared = AdventureStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mini Keyboard/Adventure"))
    let directory: URL
    var journalURL: URL { directory.appendingPathComponent("shortcut-clicks.jsonl") }
    @Published private(set) var totalClicks = 0
    @Published private(set) var xp = 0
    @Published private(set) var mastery: [String: AdventureMastery] = [:]
    @Published private(set) var recent: [ShortcutClick] = []
    @Published private(set) var notices: [AdventureNotice] = []
    @Published private(set) var error: String?
    var padConnected: () -> Bool = { false }
    var onCelebration: (([AdventureNotice], ShortcutOrigin) -> Void)?
    private var pending: [String: ShortcutClick] = [:]
    private var finished: Set<String> = []
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var handle: FileHandle?
    var playerLevel: Int { AdventureRules.level(xp, player: true) }

    init(directory: URL) {
        self.directory = directory
        encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if !FileManager.default.fileExists(atPath: journalURL.path) { FileManager.default.createFile(atPath: journalURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            // Replay is the source of truth; a damaged final line cannot erase history.
            let data = try Data(contentsOf: journalURL)
            var valid = Data()
            for line in data.split(separator: 10) {
                if let record = try? decoder.decode(AdventureRecord.self, from: Data(line)) { apply(record); valid.append(line); valid.append(10) }
                else { error = "Recovered the readable journal entries. A damaged copy is saved beside the log." }
            }
            if valid != data {
                let recovery = directory.appendingPathComponent("journal-recovery-\(UUID().uuidString).jsonl")
                try data.write(to:recovery,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:recovery.path)
                try valid.write(to: journalURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath: journalURL.path)
            }
            handle = try FileHandle(forWritingTo: journalURL); try handle?.seekToEnd()
        } catch { self.error = "Shortcut history could not be opened: \(error.localizedDescription)" }
    }
    deinit { try? handle?.close() }
    private func append(_ record: AdventureRecord) -> Bool {
        do {
            guard let handle = handle else { return false }
            var data = try encoder.encode(record); data.append(10)
            try handle.write(contentsOf: data)
            apply(record); return true
        } catch { self.error = "Shortcut history could not be saved: \(error.localizedDescription)"; return false }
    }
    private func apply(_ record: AdventureRecord) {
        let click = record.click
        if record.event == "click", pending[click.id] == nil, !finished.contains(click.id) {
            pending[click.id] = click; totalClicks += 1
            recent.insert(click, at: 0); recent = Array(recent.prefix(40))
        } else if record.event == "result", pending.removeValue(forKey: click.id) != nil, finished.insert(click.id).inserted {
            if let i = recent.firstIndex(where: { $0.id == click.id }) { recent[i] = click }
            if click.result == "completed" { xp += 1; mastery[click.action, default: AdventureMastery()].uses += 1 }
        }
    }
    @discardableResult func begin(action: String, name: String, trigger: String, origin: ShortcutOrigin, now: Date = Date()) -> String {
        let click = ShortcutClick(id: UUID().uuidString, timestamp: now, action: AdventureRules.canonical(action), name: name, trigger: trigger, origin: origin, keyboardConnected: padConnected(), result: "requested")
        _ = append(AdventureRecord(schema:1,event:"click",timestamp:now,click:click)); return click.id
    }
    @discardableResult func finish(_ id: String, success: Bool, now: Date = Date()) -> [AdventureNotice] {
        guard var click = pending[id] else { return [] }
        let oldPlayer = playerLevel, oldSkill = mastery[click.action]?.level ?? 1
        click.result = success ? "completed" : "failed"
        guard append(AdventureRecord(schema:1,event:"result",timestamp:now,click:click)), success else { return [] }
        var earned: [AdventureNotice] = []
        let newSkill = mastery[click.action]!.level
        if newSkill > oldSkill {
            let newTier = AdventureRules.tier(newSkill)
            earned.append(AdventureNotice(id:UUID().uuidString,scope:"shortcut",action:click.action,name:click.name,level:newSkill,unlocked:newTier > AdventureRules.tier(oldSkill) ? AdventureRules.accents[newTier] : "Mastery grew. The koala requests a snack."))
        }
        if playerLevel > oldPlayer { earned.append(AdventureNotice(id:UUID().uuidString,scope:"player",action:click.action,name:AdventureRules.title(playerLevel),level:playerLevel,unlocked:"The whole grove noticed.")) }
        if !earned.isEmpty { notices = Array((notices + earned).suffix(12)); onCelebration?(earned,click.origin) }
        return earned
    }
    func tier(for action: String) -> Int { AdventureRules.tier(mastery[AdventureRules.canonical(action)]?.level ?? 1) }
    func snapshot() -> [String: Any] {
        let next = AdventureRules.threshold(playerLevel+1,player:true), floor = AdventureRules.threshold(playerLevel,player:true)
        return ["clicks":totalClicks,"xp":xp,"level":playerLevel,"title":AdventureRules.title(playerLevel),"next":next,"floor":floor,
            "skills":mastery.keys.sorted().map { id -> [String:Any] in
                let m = mastery[id]!; return ["id":id,"uses":m.uses,"level":m.level,"next":AdventureRules.threshold(m.level+1,player:false),"floor":AdventureRules.threshold(m.level,player:false),"tier":tier(for:id),"flavor":AdventureRules.flavor(id)]
            },"notices":notices.map { ["id":$0.id,"scope":$0.scope,"action":$0.action,"name":$0.name,"level":$0.level,"unlocked":$0.unlocked] as [String:Any] },
            "recent":recent.prefix(12).map { ["id":$0.id,"timestamp":ISO8601DateFormatter().string(from:$0.timestamp),"name":$0.name,"source":$0.origin.title,"keyboardConnected":$0.keyboardConnected,"result":$0.result] as [String:Any] },"error":error as Any? ?? NSNull()]
    }
}
