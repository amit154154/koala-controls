import Foundation
import CryptoKit
import Security

enum RemoteFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

enum RemoteSecret {
    static func random(_ count: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        precondition(SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func equal(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

struct RemoteHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    static func parse(_ data: Data) throws -> (RemoteHTTPRequest, Int)? {
        guard data.count <= 40_960 else { throw RemoteFailure.message("Request too large") }
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > 8192 { throw RemoteFailure.message("Headers too large") }; return nil
        }
        guard data.distance(from: data.startIndex, to: separator.lowerBound) <= 8192,
              let head = String(data: data[..<separator.lowerBound], encoding: .utf8) else { throw RemoteFailure.message("Invalid headers") }
        let lines = head.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard first.count == 3, ["GET", "POST"].contains(String(first[0])), first[2] == "HTTP/1.1",
              first[1].unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }), first[1].hasPrefix("/"), !first[1].hasPrefix("//"), !first[1].contains("%"), !first[1].contains(".."), !first[1].contains("\\") else { throw RemoteFailure.message("Invalid request") }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { throw RemoteFailure.message("Invalid header") }
            let key = String(line[..<colon]).lowercased()
            guard !key.isEmpty, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }), headers[key] == nil else { throw RemoteFailure.message("Duplicate header") }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !value.unicodeScalars.contains(where: { $0.value < 32 && $0.value != 9 || $0.value == 127 }) else { throw RemoteFailure.message("Invalid header value") }
            headers[key] = value
        }
        guard headers["host"] != nil, headers["transfer-encoding"] == nil else { throw RemoteFailure.message("Unsupported encoding") }
        let lengthText = headers["content-length"] ?? "0"
        guard !lengthText.isEmpty, lengthText.allSatisfy({ $0 >= "0" && $0 <= "9" }), let length = Int(lengthText), length <= 16_384,
              first[0] != "GET" || length == 0 else { throw RemoteFailure.message("Invalid body length") }
        let used = data.distance(from: data.startIndex, to: separator.upperBound) + length
        guard data.count >= used else { return nil }
        let end = data.index(separator.upperBound, offsetBy: length)
        return (RemoteHTTPRequest(method: String(first[0]), path: String(first[1]), headers: headers,
                                  body: data.subdata(in: separator.upperBound..<end)), used)
    }
    var object: [String: Any]? { (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] }
    var token: String? {
        let parts = (headers["cookie"] ?? "").components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        let found = parts.filter { $0.hasPrefix("__Host-koala_session=") }
        guard found.count == 1 else { return nil }
        let token = String(found[0].dropFirst("__Host-koala_session=".count))
        return token.count == 64 && token.allSatisfy({ $0.isHexDigit && $0.isASCII }) ? token : nil
    }
}

struct RemoteHTTPResponse {
    var code = 200
    var body: Data
    var type = "application/json; charset=utf-8"
    var headers: [String: String] = [:]
    static func json(_ object: [String: Any], code: Int = 200) -> Self {
        Self(code: code, body: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8))
    }
    static func error(_ message: String, code: Int = 400) -> Self { .json(["error": message], code: code) }
    func encoded(close: Bool) -> Data {
        var text = "HTTP/1.1 \(code) \(code == 200 ? "OK" : code == 202 ? "Accepted" : "Error")\r\n"
        var all = headers
        all["Content-Type"] = type; all["Content-Length"] = String(body.count)
        all["Connection"] = close ? "close" : "keep-alive"
        all["Cache-Control"] = "no-store"
        all["X-Content-Type-Options"] = "nosniff"
        all["Referrer-Policy"] = "no-referrer"
        all["Content-Security-Policy"] = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; media-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
        for (k, v) in all.sorted(by: { $0.key < $1.key }) { text += "\(k): \(v)\r\n" }
        return Data((text + "\r\n").utf8) + body
    }
}

struct RemotePeer: Codable, Identifiable {
    var id: String
    var name: String
    var tokenHash: String
    var paired: Date
    var lastSeen: Date
}

struct RemoteJob {
    let id: String
    let peer: String
    let fingerprint: String
    let created: Date
    var status: String
    var message: String
    var extra: [String: Any] = [:]
    var json: [String: Any] { ["id": id, "status": status, "message": message].merging(extra) { _, b in b } }
}

enum RemoteCommandPolicy {
    static let kinds: Set<String> = ["tv", "key", "corner", "media", "arrangeMedia", "focusMedia", "pointer", "click", "scroll", "text", "special", "focusApp", "volume"]
    static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    static func validate(_ o: [String: Any], now: Date = Date()) throws -> String {
        guard let id = o["id"] as? String, UUID(uuidString: id) != nil,
              let kind = o["kind"] as? String, kinds.contains(kind),
              let timestamp = number(o["timestamp"]), timestamp.isFinite,
              abs(timestamp - now.timeIntervalSince1970) <= 20 else { throw RemoteFailure.message("This action expired. Tap again after reconnecting.") }
        if kind == "tv" {
            guard let control = o["control"] as? String, ["macScreen","automaticTV","rememberTV","av","captions","captionSettings","captionPreview","audioRefresh","audioOutput","audioVolume","audioMute","audioConnect","audioSettings","home","exit","display","refresh","setup","resume","resumeOpen","refreshOpen","trackpad","share","focus","focusMedia","hideMedia","select","media","game","controllers","bluetooth","back","up","down","left","right","playPause","previous","next","tab","shiftTab","fullscreen"].contains(control) else { throw RemoteFailure.message("Unknown TV control") }
            if ["macScreen","automaticTV"].contains(control){let key=control=="macScreen" ? "blank":"enabled";guard let v=o[key] as? NSNumber,CFGetTypeID(v)==CFBooleanGetTypeID() else{throw RemoteFailure.message("Invalid TV display toggle")}}
            if control == "captions" {guard let v=o["enabled"] as? NSNumber,CFGetTypeID(v)==CFBooleanGetTypeID() else{throw RemoteFailure.message("Invalid captions toggle")}}
            if control == "audioMute" {guard let v=o["muted"] as? NSNumber,CFGetTypeID(v)==CFBooleanGetTypeID() else{throw RemoteFailure.message("Invalid mute toggle")}}
            if control == "audioVolume" {guard let v=number(o["value"]),(0...1).contains(v) else{throw RemoteFailure.message("Invalid volume")}}
            if control == "audioOutput" {guard let v=o["output"] as? String,UUID(uuidString:v) != nil else{throw RemoteFailure.message("Unknown sound output")}}
            if control == "audioConnect" {guard let v=o["headphones"] as? String,UUID(uuidString:v) != nil else{throw RemoteFailure.message("Unknown paired headphones")}}
            if control == "captionSettings" {
                let options=["source":["chrome","appleTV","spotify"],"size":["small","medium","large"],"position":["top","bottom"],"style":["forest","contrast"]]
                guard options.keys.contains(where:{o[$0] != nil}) || o["language"] != nil else{throw RemoteFailure.message("Missing caption setting")}
                for (key,allowed) in options {if let value=o[key]{guard let v=value as? String,allowed.contains(v) else{throw RemoteFailure.message("Invalid caption setting")}}}
                if let value=o["language"] {guard let v=value as? String,(2...32).contains(v.utf8.count),v.utf8.allSatisfy({(65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0==45 || $0==95}) else{throw RemoteFailure.message("Invalid caption language")}}
            }
            if ["media","focusMedia","hideMedia"].contains(control) { guard let service = o["service"] as? String, ["youtubeMusic","spotify","youtube","gdn","netflix","hbo","nba","appleTV"].contains(service) else { throw RemoteFailure.message("Unknown TV service") } }
            if control == "resumeOpen" {guard let id=o["item"] as? String,UUID(uuidString:id) != nil else{throw RemoteFailure.message("Unknown open item")}}
            if control == "game" { guard let id = o["game"] as? String, (9...16).contains(id.utf8.count), id.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) else { throw RemoteFailure.message("Unknown game") } }
            if let display = o["display"] { guard let value = display as? String, value == "auto" || UInt32(value) != nil else { throw RemoteFailure.message("Invalid TV display") } }
        }
        if kind == "corner" { guard let corner = o["corner"] as? String, ["topLeft","topRight","bottomLeft","bottomRight"].contains(corner) else { throw RemoteFailure.message("Unknown window corner") } }
        if kind == "key" { guard let n = number(o["key"]), n.rounded() == n, (1...12).contains(n) else { throw RemoteFailure.message("Unknown key") } }
        if kind == "media" || kind == "focusMedia" {
            guard let service = o["service"] as? String, ["youtubeMusic", "spotify", "youtube", "gdn", "netflix", "hbo", "nba", "appleTV"].contains(service) else { throw RemoteFailure.message("Unknown media service") }
        }
        if ["pointer", "scroll"].contains(kind) {
            for k in ["dx", "dy"] { guard let v = number(o[k]), v.isFinite, abs(v) <= 300 else { throw RemoteFailure.message("Invalid pointer movement") } }
        }
        if kind == "text" { guard let text = o["text"] as? String, !text.isEmpty, text.utf16.count <= 2000 else { throw RemoteFailure.message("Send up to 2,000 characters at a time.") } }
        if kind == "special" { guard let key = o["special"] as? String, ["escape", "return", "undo", "previousTab", "nextTab", "previousSpace", "nextSpace"].contains(key) else { throw RemoteFailure.message("Unknown control") } }
        if kind == "click" { guard let button = o["button"] as? String, ["left", "right"].contains(button) else { throw RemoteFailure.message("Unknown mouse button") } }
        if kind == "volume" { guard let v = number(o["value"]), v.isFinite, (0...1).contains(v) else { throw RemoteFailure.message("Invalid volume") } }
        return kind
    }
}

// Keep request provenance independent of cookies; no cross-origin control endpoint is exposed.
enum RemoteOriginPolicy {
    static func rejection(_ r: RemoteHTTPRequest, host: String, port: UInt16) -> Int? {
        let requested = r.headers["host"]?.lowercased() ?? ""
        guard ["\(host):\(port)", "localhost:\(port)", "127.0.0.1:\(port)"].contains(requested) else { return 421 }
        if let origin = r.headers["origin"], origin != "https://" + requested { return 403 }
        if let site = r.headers["sec-fetch-site"], !["same-origin", "none"].contains(site) { return 403 }
        if r.method == "POST" {
            guard r.headers["origin"] == "https://" + requested,
                  r.headers["content-type"]?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else { return 403 }
        }
        return nil
    }
}

/// Read the user's Mission Control shortcut; missing entries use macOS defaults.
/// Keep this independent of the active window, since Spaces may contain no windows.
enum RemoteSpaceShortcut {
    static func resolve(_ direction: String, preferences: [String: Any]) throws -> (code: UInt16, flags: UInt64) {
        guard ["previousSpace", "nextSpace"].contains(direction) else { throw RemoteFailure.message("Unknown desktop direction") }
        let previous = direction == "previousSpace"
        let entry = preferences[previous ? "79" : "81"] as? [String: Any]
        let help = "Enable Move left/right a space in System Settings → Keyboard → Keyboard Shortcuts → Mission Control."
        if entry?["enabled"] as? Bool == false { throw RemoteFailure.message(help) }
        guard let value = entry?["value"] as? [String: Any] else { return (previous ? 123 : 124, 1 << 18) }
        guard value["type"] as? String == "standard", let params = value["parameters"] as? [Any], params.count == 3,
              let code = RemoteCommandPolicy.number(params[1]), code.rounded() == code, (0...127).contains(code),
              let flags = RemoteCommandPolicy.number(params[2]), flags.rounded() == flags, (0...Double(UInt32.max)).contains(flags) else {
            throw RemoteFailure.message(help)
        }
        return (UInt16(code), UInt64(flags))
    }
}
