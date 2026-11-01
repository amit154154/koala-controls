import Foundation

@main enum RemoteRegression {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows { count += 1; let result = try value(); precondition(result, message) }
    static func rejects(_ message: String, _ body: () throws -> Void) { count += 1; do { try body(); preconditionFailure(message) } catch {} }
    static func main() throws {
        func request(_ text: String) throws -> RemoteHTTPRequest? { try RemoteHTTPRequest.parse(Data(text.utf8))?.0 }
        let get = "GET /api/state HTTP/1.1\r\nHost: mac.local:9472\r\nX-Koala-Client: 1\r\n\r\n"
        try check(request(get)?.path == "/api/state", "Valid GET")
        try check(request(String(get.dropLast())) == nil, "Fragmented headers wait")
        let post = "POST /api/command HTTP/1.1\r\nHost: mac.local:9472\r\nContent-Length: 2\r\n\r\n{}"
        try check(request(post)?.object != nil, "JSON body")
        try check(request(String(post.dropLast())) == nil, "Fragmented body waits")
        try check(RemoteHTTPRequest.parse(Data((get+get).utf8))?.1 == get.utf8.count, "Reports bytes consumed so connection can reject pipelining")
        for bad in [get.replacingOccurrences(of:"GET /",with:"DELETE /"),get.replacingOccurrences(of:"/api/state",with:"//evil"),get.replacingOccurrences(of:"/api/state",with:"/../private"),get.replacingOccurrences(of:"/api/state",with:"/%2e%2e/private"),get.replacingOccurrences(of:"/api/state",with:"/foo\\bar"),get.replacingOccurrences(of:"/api/state",with:"/foo\tbar"),get.replacingOccurrences(of:"Host:",with:"Host: duplicate\r\nHost:"),get.replacingOccurrences(of:"Host:",with:"Transfer-Encoding: chunked\r\nHost:"),get.replacingOccurrences(of:"Host:",with:"Content-Length: 1\r\nHost:"),get.replacingOccurrences(of:"Host:",with:" Host:"),get.replacingOccurrences(of:"Host:",with:"X-Bad: a\nb\r\nHost:"),post.replacingOccurrences(of:"Length: 2",with:"Length: -1"),post.replacingOccurrences(of:"Length: 2",with:"Length: 20000"),String(repeating:"x",count:9000)] { rejects("Malformed HTTP must fail") { _ = try request(bad) } }
        var reusedBuffer = Data((get+post).utf8)
        reusedBuffer.removeFirst(get.utf8.count)
        try check(RemoteHTTPRequest.parse(reusedBuffer)?.0.object != nil, "Keep-alive Data buffer preserves nonzero indices")
        let token=RemoteSecret.random(); check(token.count==64, "256-bit tokens"); check(RemoteSecret.equal(token,token),"Token equality"); check(!RemoteSecret.equal(token,String(token.dropLast())),"Token length"); check(RemoteSecret.hash(token) != token,"Store only hash")
        let cookie=get.replacingOccurrences(of:"X-Koala-Client: 1",with:"Cookie: __Host-koala_session=\(token)")
        try check(request(cookie)?.token == token,"Read secure session cookie")
        try check(request(cookie.replacingOccurrences(of:token,with:token+"; __Host-koala_session="+token))?.token == nil,"Duplicate cookies rejected")
        try check(request(cookie.replacingOccurrences(of:token,with:"invalid"))?.token == nil,"Invalid token rejected")
        func origin(_ headers:[String:String],method:String="POST") -> Int? { RemoteOriginPolicy.rejection(RemoteHTTPRequest(method:method,path:"/api/command",headers:headers,body:Data()),host:"mac.local",port:9472) }
        let valid=["host":"mac.local:9472","origin":"https://mac.local:9472","content-type":"application/json; charset=utf-8","sec-fetch-site":"same-origin"]
        check(origin(valid)==nil,"Same origin JSON allowed")
        for pair in [("host","evil.test:9472"),("origin","https://evil.test"),("origin","null"),("content-type","text/plain"),("content-type","application/jsonx"),("sec-fetch-site","cross-site")] { var h=valid;h[pair.0]=pair.1; check(origin(h) != nil,"Reject foreign provenance") }
        var noOrigin=valid;noOrigin.removeValue(forKey:"origin");check(origin(noOrigin)==403,"POST needs origin")
        check(origin(["host":"mac.local:9472"],method:"GET")==nil,"Initial navigation allowed without Origin")
        let now=Date(timeIntervalSince1970:1000)
        func command(_ kind:String,_ extra:[String:Any]=[:])->[String:Any] { ["id":UUID().uuidString,"kind":kind,"timestamp":1000.0].merging(extra){_,b in b} }
        try check(RemoteCommandPolicy.validate(command("key",["key":12]),now:now)=="key","Known shortcut")
        for o in [command("key",["key":13]),command("key",["key":1.5]),command("key",["key":true]),command("shell"),command("key",["key":1,"timestamp":900]),command("key",["key":1,"timestamp":true]),command("key",["key":1,"id":"no"]),command("pointer",["dx":301,"dy":0]),command("pointer",["dx":true,"dy":0]),command("pointer",["dx":Double.nan,"dy":0]),command("media",["service":"https://evil.test"]),command("text",["text":String(repeating:"a",count:2001)]),command("volume",["value":1.2]),command("special",["special":"arbitrary"])] { rejects("Unsafe commands rejected") { _ = try RemoteCommandPolicy.validate(o,now:now) } }
        try check(RemoteCommandPolicy.validate(command("text",["text":"Koala 🐨 שלום"]),now:now)=="text","Unicode allowed")
        for direction in ["previousSpace", "nextSpace"] {
            try check(RemoteCommandPolicy.validate(command("special",["special":direction]),now:now)=="special", "Desktop navigation is accepted without a window-focus token")
        }
        let left = try RemoteSpaceShortcut.resolve("previousSpace",preferences:[:]), right = try RemoteSpaceShortcut.resolve("nextSpace",preferences:["81":["enabled":true]])
        check(left.code==123 && right.code==124 && left.flags==262144 && right.flags==262144,"Default and enabled-only entries use Control-arrows")
        let custom = try RemoteSpaceShortcut.resolve("nextSpace",preferences:["81":["enabled":true,"value":["type":"standard","parameters":[65535,124,786432]]]])
        check(custom.code==124 && custom.flags==786432,"Respect the configured Mission Control modifiers")
        rejects("Disabled global shortcut must not send arrows into an app") { _ = try RemoteSpaceShortcut.resolve("previousSpace",preferences:["79":["enabled":false]]) }
        rejects("Malformed preference is not silently replaced") { _ = try RemoteSpaceShortcut.resolve("nextSpace",preferences:["81":["value":["type":"standard","parameters":[65535,-1,262144]]]]) }
        rejects("Only left/right global navigation is exposed") { _ = try RemoteSpaceShortcut.resolve("unknown",preferences:[:]) }
        let response=String(data:RemoteHTTPResponse.json(["status":"completed"]).encoded(close:true),encoding:.utf8)!
        check(response.contains("frame-ancestors 'none'") && response.contains("Cache-Control: no-store") && response.contains("nosniff"),"Browser hardening headers")
        let tmp=FileManager.default.temporaryDirectory.appendingPathComponent("koala-tls-test-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:tmp) }
        let tls=try RemoteTLS.prepare(in:tmp), again=try RemoteTLS.prepare(in:tmp)
        check(tls.fingerprint==again.fingerprint,"CA survives restart without renewed trust")
        check(tls.host.hasSuffix(".local"),"Bonjour address")
        let mode=(try FileManager.default.attributesOfItem(atPath:tmp.appendingPathComponent("ca.key").path)[.posixPermissions]) as! NSNumber
        check(mode.intValue==0o600,"Private key owner-only")
        let profile=try PropertyListSerialization.propertyList(from:Data(contentsOf:tls.profileURL),format:nil) as! [String:Any]
        let content=profile["PayloadContent"] as! [[String:Any]]
        check(content.count==1 && content[0]["PayloadType"] as? String == "com.apple.security.root","Trust profile contains no device-management payload")
        print("\(count) remote security and TLS checks passed")
    }
}
