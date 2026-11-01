import AppKit
import IOKit

struct TVGame: Identifiable {
    let id: String
    let title: String
    let path: URL
    let available: Bool
    let icon: NSImage?
    let backdrop: NSImage?
    var json: [String: Any] { ["id": id, "title": title, "available": available, "art": icon != nil] }
}

/// Only reads RPCS3's own library and bounded metadata. Never scans unrelated folders.
enum TVLibrary {
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/rpcs3")
    static func load(root: URL = root) -> [TVGame] {
        let fm = FileManager.default
        var games: [String: TVGame] = [:]
        let mapping = (try? String(contentsOf: root.appendingPathComponent("games.yml"))) ?? ""
        for line in mapping.components(separatedBy: .newlines) {
            guard let colon = line.range(of: ": ") else { continue }
            let id = String(line[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard validID(id) else { continue }
            var path = String(line[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
            if path.hasPrefix("\""), path.hasSuffix("\"") { path.removeFirst(); path.removeLast(); path = path.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\") }
            guard path.hasPrefix("/"), !path.contains("\0") else { continue }
            let url = URL(fileURLWithPath: path)
            let available = fm.fileExists(atPath: path)
            let iso = available && url.pathExtension.lowercased() == "iso" ? TVISO(url) : nil
            let folder = url.pathExtension.lowercased() == "iso" ? root.appendingPathComponent("dev_hdd0/game/" + id) : url.appendingPathComponent("PS3_GAME")
            let sfo = iso?.file("PARAM.SFO") ?? (try? Data(contentsOf: folder.appendingPathComponent("PARAM.SFO")))
            let metadata = sfo.map(TVSFO.strings) ?? [:]
            let fallback = url.deletingPathExtension().lastPathComponent.components(separatedBy: " (USA)").first ?? id
            let title = metadata["TITLE"] ?? fallback
            let iconData = iso?.file("ICON0.PNG") ?? (try? Data(contentsOf: folder.appendingPathComponent("ICON0.PNG")))
            games[id] = TVGame(id: id, title: title, path: url, available: available, icon: iconData.flatMap(NSImage.init(data:)), backdrop: iso?.file("PIC1.PNG").flatMap(NSImage.init(data:)))
        }
        let installed = root.appendingPathComponent("dev_hdd0/game")
        for folder in (try? fm.contentsOfDirectory(at: installed, includingPropertiesForKeys: nil)) ?? [] {
            let id = folder.lastPathComponent
            guard validID(id), games[id] == nil,
                  let bytes = try? Data(contentsOf: folder.appendingPathComponent("PARAM.SFO")) else { continue }
            let sfo = TVSFO.strings(bytes)
            // Updates, data packs and digital manuals are not playable library entries.
            guard sfo["CATEGORY"] == "HG", let title = sfo["TITLE"], !title.localizedCaseInsensitiveContains("manual"), fm.fileExists(atPath: folder.appendingPathComponent("USRDIR/EBOOT.BIN").path) else { continue }
            games[id] = TVGame(id: id, title: title, path: folder, available: true,
                icon: NSImage(contentsOf: folder.appendingPathComponent("ICON0.PNG")), backdrop: NSImage(contentsOf: folder.appendingPathComponent("PIC1.PNG")))
        }
        return games.values.sorted { a, b in a.available != b.available ? a.available : a.title.localizedStandardCompare(b.title) == .orderedAscending }
    }
    static func validID(_ id: String) -> Bool { (9...16).contains(id.utf8.count) && id.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) } }
}

enum TVSFO {
    static func strings(_ data: Data) -> [String: String] {
        let b = [UInt8](data)
        guard b.count >= 20, Array(b.prefix(4)) == [0,80,83,70] else { return [:] }
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o+1]) << 8 }
        func u32(_ o: Int) -> Int { Int(b[o]) | Int(b[o+1]) << 8 | Int(b[o+2]) << 16 | Int(b[o+3]) << 24 }
        let keys = u32(8), values = u32(12), count = u32(16)
        guard count <= 512, keys <= b.count, values <= b.count, 20 + count * 16 <= b.count else { return [:] }
        var result: [String: String] = [:]
        for i in 0..<count {
            let o = 20 + i*16, start = keys + u16(o), length = u32(o+4), offset = values + u32(o+12)
            guard u16(o+2) == 0x204, start < b.count, offset <= b.count, length <= b.count - offset else { continue }
            let key = String(bytes: b[start...].prefix(while: { $0 != 0 }), encoding: .utf8)
            let value = String(bytes: b[offset..<(offset+length)].prefix(while: { $0 != 0 }), encoding: .utf8)
            if let key = key, let value = value { result[key] = value }
        }
        return result
    }
}

/// Minimal ISO9660 reader for the PS3_GAME artwork already present on a local disc image.
final class TVISO {
    private let handle: FileHandle
    private let game: (Int, Int)
    init?(_ url: URL) {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        handle = h
        guard let pvd = Self.read(h, at: 16*2048, count: 2048), pvd.count == 2048,
              Array(pvd[1..<6]) == [67,68,48,48,49],
              let entry = Self.entries(h, extent: Self.int(pvd,158), size: Self.int(pvd,166)).first(where: { $0.0 == "PS3_GAME" }) else { try? h.close(); return nil }
        game = (entry.1, entry.2)
    }
    deinit { try? handle.close() }
    func file(_ name: String) -> Data? {
        guard ["PARAM.SFO", "ICON0.PNG", "PIC1.PNG"].contains(name),
              let item = Self.entries(handle, extent: game.0, size: game.1).first(where: { $0.0 == name }), item.2 <= 8_000_000 else { return nil }
        return Self.read(handle, at: item.1*2048, count: item.2)
    }
    private static func int(_ b: Data, _ o: Int) -> Int { Int(b[o]) | Int(b[o+1]) << 8 | Int(b[o+2]) << 16 | Int(b[o+3]) << 24 }
    private static func read(_ h: FileHandle, at: Int, count: Int) -> Data? {
        guard at >= 0, count > 0, count <= 8_000_000 else { return nil }
        do { try h.seek(toOffset: UInt64(at)); let d = try h.read(upToCount: count); return d?.count == count ? d : nil } catch { return nil }
    }
    private static func entries(_ h: FileHandle, extent: Int, size: Int) -> [(String, Int, Int)] {
        guard size <= 2_000_000, let b = read(h, at: extent*2048, count: size) else { return [] }
        var p = 0, result: [(String, Int, Int)] = []
        while p < b.count {
            let length = Int(b[p]); if length == 0 { p = (p/2048+1)*2048; continue }
            guard length >= 34, p + length <= b.count, 33 + Int(b[p+32]) <= length else { break }
            let name = String(decoding: b[(p+33)..<(p+33+Int(b[p+32]))], as: UTF8.self).components(separatedBy: ";")[0]
            result.append((name, int(b,p+2), int(b,p+10))); p += length
        }
        return result
    }
}

struct TVControllerInfo {
    let name: String
    let transport: String
}
enum TVControllers {
    static func connected() -> [TVControllerInfo] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var found: [String: TVControllerInfo] = [:]
        while case let device = IOIteratorNext(iterator), device != 0 {
            defer { IOObjectRelease(device) }
            var raw: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(device, &raw, kCFAllocatorDefault, 0) == KERN_SUCCESS, let p = raw?.takeRetainedValue() as? [String: Any] else { continue }
            let page = p["PrimaryUsagePage"] as? Int ?? 0, usage = p["PrimaryUsage"] as? Int ?? 0
            let name = p["Product"] as? String ?? "Controller", lower = name.lowercased()
            guard (page == 1 && [4,5].contains(usage)) || lower.contains("dualsense") || lower.contains("dualshock") || lower.contains("playstation") else { continue }
            let transport = p["Transport"] as? String ?? "Connected"
            found[name + transport] = TVControllerInfo(name: name, transport: transport)
        }
        return found.values.sorted { $0.name < $1.name }
    }
}
