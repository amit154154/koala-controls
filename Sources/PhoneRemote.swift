import AppKit
import SwiftUI
import Network
import Security

@MainActor final class PhoneRemote: ObservableObject {
    static let shared = PhoneRemote()
    static let port: UInt16 = 9472
    @Published var enabled = UserDefaults.standard.bool(forKey: "phoneRemoteEnabled")
    @Published var status = "Phone remote is off"
    @Published var address = ""
    @Published var pairingCode = ""
    @Published var peers: [RemotePeer] = []
    @Published var pendingName: String?
    @Published var pendingCheck = ""
    @Published var fingerprint = ""
    @Published var ready = false
    private var tls: RemoteTLS?
    private var listener: NWListener?
    private var connections: [UUID: RemoteHTTPConnection] = [:]
    private var codeExpires = Date.distantPast
    private var attempts = 0
    private var pending: (proof: String, name: String, expires: Date, token: String?)?
    private var jobs: [String: RemoteJob] = [:]
    private var commandBusy = false
    private var activeJob: String?
    private var rates: [String: (Date, Int)] = [:]
    private let actions = RemoteActions()
    private var generation = UUID()
    private var window: NSWindow?
    private var assets: [String: (Data, String)] = [:]
    private let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Mini Keyboard/Phone Remote", isDirectory: true)
    private var peersURL: URL { directory.appendingPathComponent("peers.json") }

    init() {
        if let data = try? Data(contentsOf: peersURL), let p = try? JSONDecoder().decode([RemotePeer].self, from: data) { peers = p }
    }
    func startIfEnabled() { if enabled { start() } }
    func start() {
        guard listener == nil else { return }
        enabled = true; UserDefaults.standard.set(true, forKey: "phoneRemoteEnabled")
        status = "Preparing secure local connection…"
        let g = UUID(); generation = g
        let certDirectory = directory.appendingPathComponent("TLS", isDirectory: true)
        Task {
            do {
                let identity = try await Task.detached { try RemoteTLS.prepare(in: certDirectory) }.value
                guard generation == g, enabled else { return }
                tls = identity; fingerprint = identity.fingerprint; address = "https://\(identity.host):\(Self.port)"
                let options = NWProtocolTLS.Options()
                guard let id = sec_identity_create(identity.identity) else { throw RemoteFailure.message("TLS identity unavailable") }
                sec_protocol_options_set_local_identity(options.securityProtocolOptions, id)
                sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
                let params = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
                params.includePeerToPeer = false
                let server = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
                server.service = NWListener.Service(name: "Koala Remote", type: "_koalaremote._tcp")
                server.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                    guard let self = self else { return }
                    switch state {
                    case .ready: self.ready = true; self.status = "Ready for your phone"; self.newPairingCode()
                    case .failed(let error): self.status = "Phone connection: \(error.localizedDescription)"; self.ready = false; self.listener?.cancel(); self.listener = nil
                    default: break
                    }
                }
                }
                server.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection) } }
                listener = server; loadAssets(); server.start(queue: .main)
            } catch { if generation == g { ready = false; status = error.localizedDescription } }
        }
    }
    func stop() {
        generation = UUID(); enabled = false; UserDefaults.standard.set(false, forKey: "phoneRemoteEnabled")
        listener?.cancel(); listener = nil; Array(connections.values).forEach { $0.close() }; connections.removeAll()
        pending = nil; pendingName = nil; pairingCode = ""; ready = false; status = "Phone remote is off"
    }
    func newPairingCode() {
        let raw = RemoteSecret.random(4)
        pairingCode = String(format: "%06u", (UInt32(raw, radix: 16) ?? 0) % 1_000_000)
        codeExpires = Date().addingTimeInterval(300); attempts = 0; pending = nil; pendingName = nil
    }
    func approve() {
        guard let p = pending, p.expires > Date() else { pending = nil; pendingName = nil; return }
        let token = RemoteSecret.random()
        peers.append(RemotePeer(id: UUID().uuidString, name: p.name, tokenHash: RemoteSecret.hash(token), paired: Date(), lastSeen: Date()))
        pending = (p.proof, p.name, p.expires, token); pendingName = nil; persistPeers()
        pairingCode = ""; codeExpires = .distantPast; status = "\(p.name) approved"
    }
    func deny() { pending = nil; pendingName = nil; status = "Pairing request declined" }
    func revoke(_ peer: RemotePeer) { peers.removeAll { $0.id == peer.id }; persistPeers(); status = "\(peer.name) disconnected" }
    private func persistPeers() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let data = try? JSONEncoder().encode(peers) { try? data.write(to: peersURL, options: .atomic); try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: peersURL.path) }
    }
    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 570, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Koala Remote"; w.contentView = NSHostingView(rootView: PhoneRemoteView(remote: self))
            w.isReleasedWhenClosed = false; w.center(); window = w
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func revealProfile() { if let url = tls?.profileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    func shareProfile() { if let url = tls?.profileURL { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [url]) } }
    func copyAddress() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(address, forType: .string) }
    var qr: NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(address.utf8), forKey: "inputMessage"); filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 7, y: 7)), let cg = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: 176, height: 176))
    }
    private func accept(_ connection: NWConnection) {
        guard connections.count < 32, enabled else { connection.cancel(); return }
        let c = RemoteHTTPConnection(connection)
        connections[c.id] = c
        c.onRequest = { [weak self] request in self?.handle(request) ?? .error("Remote unavailable", code: 503) }
        c.onClose = { [weak self, weak c] in if let c = c { self?.connections.removeValue(forKey: c.id) } }
        c.start()
    }
    private func loadAssets() {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("PhoneRemote"),
              let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        let types = ["html": "text/html; charset=utf-8", "css": "text/css", "js": "text/javascript", "json": "application/json", "webmanifest": "application/manifest+json", "png": "image/png", "jpg": "image/jpeg", "webp": "image/webp", "wav": "audio/wav"]
        for case let url as URL in enumerator {
            guard let type = types[url.pathExtension], let data = try? Data(contentsOf: url), data.count < 8_000_000 else { continue }
            assets["/" + String(url.path.dropFirst(root.path.count + 1))] = (data, type)
        }
        assets["/"] = assets["/index.html"]
    }
    private func handle(_ r: RemoteHTTPRequest) -> RemoteHTTPResponse {
        guard enabled, let tls = tls else { return .error("Phone remote is off", code: 503) }
        if let rejection = RemoteOriginPolicy.rejection(r, host: tls.host, port: Self.port) { return .error("Request origin rejected", code: rejection) }
        if r.method == "GET", let asset = assets[r.path] { return RemoteHTTPResponse(body: asset.0, type: asset.1) }
        guard r.path.hasPrefix("/api/"), r.headers["x-koala-client"] == "1" else { return .error("Not found", code: 404) }
        if r.method == "POST", r.path == "/api/pair" {
            guard codeExpires > Date(), attempts < 8 else { return .error("Generate a new pairing code on your Mac.", code: 403) }
            attempts += 1
            guard let o = r.object, let code = o["code"] as? String, RemoteSecret.equal(code, pairingCode), pending == nil,
                  let name = o["name"] as? String, (1...40).contains(name.count), !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return .error("Check the pairing code, or generate a new one.", code: 403) }
            let proof = RemoteSecret.random(); pending = (RemoteSecret.hash(proof), name, Date().addingTimeInterval(120), nil)
            pendingName = name; pendingCheck = String(proof.prefix(4)).uppercased(); showWindow()
            return .json(["proof": proof, "check": pendingCheck, "message": "Approve this phone in Mini Keyboard on your Mac."])
        }
        if r.method == "POST", r.path == "/api/pair-status" {
            guard let proof = r.object?["proof"] as? String, let p = pending, p.expires > Date(), RemoteSecret.equal(RemoteSecret.hash(proof), p.proof) else { return .error("Pairing expired or declined. Generate a new code on your Mac.", code: 403) }
            guard let token = p.token else { return .json(["status": "waiting"]) }
            pending = nil
            var result = RemoteHTTPResponse.json(["status": "paired"])
            result.headers["Set-Cookie"] = "__Host-koala_session=\(token); Path=/; Max-Age=7776000; Secure; HttpOnly; SameSite=Strict"
            return result
        }
        guard let token = r.token, let index = peers.firstIndex(where: { RemoteSecret.equal($0.tokenHash, RemoteSecret.hash(token)) && Date().timeIntervalSince($0.paired) < 7_776_000 }) else { return .error("Pair this phone with Mini Keyboard on your Mac.", code: 401) }
        let peer = peers[index]
        peers[index].lastSeen = Date()
        let rate = rates[peer.id] ?? (.distantPast, 0)
        let next = Date().timeIntervalSince(rate.0) < 1 ? (rate.0, rate.1 + 1) : (Date(), 1)
        rates[peer.id] = next
        guard next.1 <= 80 else { return .error("Too many requests. Pause briefly and retry.", code: 429) }
        if r.method == "GET", r.path == "/api/state" {
            var data = actions.snapshot(); data["peer"] = peer.name; data["busy"] = commandBusy || GroveActions.shared.isRunningLayout
            return .json(data)
        }
        if r.method == "POST", r.path == "/api/media-state" {
            do { let screen = try actions.screen(r.object?["display"] as? String, media: true); actions.refreshMedia(on: screen); return .json(actions.snapshot()) }
            catch { return .error(error.localizedDescription) }
        }
        if r.method == "GET", r.path.hasPrefix("/api/job/") {
            let id = String(r.path.dropFirst("/api/job/".count))
            guard let job = jobs[peer.id + ":" + id] else { return .error("Action result is unavailable. It was not retried.", code: 404) }
            return .json(job.json)
        }
        if r.method == "POST", r.path == "/api/command", let object = r.object {
            do {
                let kind = try RemoteCommandPolicy.validate(object)
                let id = object["id"] as! String, key = peer.id + ":" + id
                let fingerprint = RemoteSecret.hash(String(data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), encoding: .utf8)!)
                if let prior = jobs[key] {
                    guard prior.fingerprint == fingerprint else { return .error("This request ID was already used.", code: 409) }
                    return .json(prior.json)
                }
                let fast = ["pointer", "scroll", "click", "volume", "special", "text", "focusApp"].contains(kind)
                let activity = actions.activity(object,kind:kind)
                let click = activity.map { AdventureStore.shared.begin(action:$0.action,name:$0.name,trigger:$0.trigger,origin:.phone) }
                guard !commandBusy else { if let click = click { AdventureStore.shared.finish(click,success:false) }; return .error("An action is still running. Wait for it to finish.", code:409) }
                if !fast { commandBusy = true; activeJob = key }
                jobs[key] = RemoteJob(id: id, peer: peer.id, fingerprint: fingerprint, created: Date(), status: "running", message: "Working on your Mac…")
                if jobs.count > 256 {
                    let old = jobs.filter { $0.key != activeJob }.sorted { $0.value.created < $1.value.created }.prefix(jobs.count - 256).map(\.key)
                    old.forEach { jobs.removeValue(forKey: $0) }
                }
                actions.execute(object, kind: kind) { [weak self] message, failed, extra in
                    guard let self = self else { return }
                    self.jobs[key]?.status = failed ? "failed" : "completed"; self.jobs[key]?.message = message; self.jobs[key]?.extra = extra
                    if let click = click {
                        let earned = AdventureStore.shared.finish(click,success:!failed)
                        self.jobs[key]?.extra["earned"] = earned.map { ["id":$0.id,"scope":$0.scope,"action":$0.action,"name":$0.name,"level":$0.level,"unlocked":$0.unlocked] as [String:Any] }
                    }
                    if self.activeJob == key { self.activeJob = nil; self.commandBusy = false }
                    if !message.isEmpty { self.status = message }
                    let n = object["key"] as? Int ?? (kind == "media" ? 3 : 0)
                    if object["feedback"] as? String == "mac", !failed, kind == "corner", let activity = activity { ShortcutFeedback.shared.react(actionID:activity.action,control:"phone corner") }
                    if object["feedback"] as? String == "mac", !failed, n > 0,
                       let action = AppModel.shared.settings.mapping("k\(n)").action { ShortcutFeedback.shared.react(actionID: action.id, control: "k\(n)") }
                }
                return .json(jobs[key]!.json, code: fast ? 200 : 202)
            } catch { return .error(error.localizedDescription) }
        }
        return .error("Not found", code: 404)
    }
}

@MainActor final class RemoteHTTPConnection {
    let id = UUID()
    let connection: NWConnection
    var onRequest: ((RemoteHTTPRequest) -> RemoteHTTPResponse)?
    var onClose: (() -> Void)?
    private var buffer = Data()
    private var timer: Timer?
    private var count = 0
    private var closed = false
    init(_ connection: NWConnection) { self.connection = connection }
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
            switch state { case .ready: self?.receive(); case .failed, .cancelled: self?.close(); default: break }
        }
        }
        armTimeout(); connection.start(queue: .main)
    }
    private func armTimeout() { timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in Task { @MainActor in self?.close() } } }
    private func receive() {
        guard !closed else { return }
        armTimeout()
        connection.receive(minimumIncompleteLength: 1, maximumLength: 20_480) { [weak self] data, _, done, error in
            Task { @MainActor in
            guard let self = self, !self.closed else { return }
            if let data = data { self.buffer.append(data) }
            if error != nil { self.close(); return }
            do {
                if let (request, used) = try RemoteHTTPRequest.parse(self.buffer) {
                    self.buffer.removeFirst(used); self.count += 1
                    // No pipelined requests: one outstanding action per HTTP connection.
                    guard self.buffer.isEmpty else { self.send(.error("Pipelining is not supported"), close: true); return }
                    let response = self.onRequest?(request) ?? .error("Unavailable", code: 503)
                    self.send(response, close: done || request.headers["connection"]?.lowercased() == "close" || self.count > 100)
                } else if done { self.close() } else { self.receive() }
            } catch { self.send(.error("Malformed request"), close: true) }
        }
    }
    }
    private func send(_ response: RemoteHTTPResponse, close: Bool) {
        armTimeout()
        // A processed send is not proof that TLS bytes reached the peer. Mark the
        // final context to flush the full response and write-close in order.
        // https://developer.apple.com/documentation/network/nwconnection/contentcontext/finalmessage
        connection.send(content: response.encoded(close: close), contentContext: close ? .finalMessage : .defaultMessage,
                        isComplete: true, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self = self, !self.closed else { return }
                if error != nil { self.close() }
                else if close { self.armTimeout(); self.awaitPeerClose() }
                else { self.receive() }
            }
        })
    }
    private func awaitPeerClose() {
        guard !closed else { return }
        // The write side has sent its FIN. Let a normal HTTP client finish reading
        // before cancellation; a noncooperating peer is bounded by the idle timer.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] _, _, done, error in
            Task { @MainActor in
                guard let self = self, !self.closed else { return }
                if done || error != nil { self.close() } else { self.awaitPeerClose() }
            }
        }
    }
    func close() { guard !closed else { return }; closed = true; timer?.invalidate(); connection.cancel(); onClose?() }
}

struct PhoneRemoteView: View {
    @ObservedObject var remote: PhoneRemote
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack { GroveArtwork(name: "companion").frame(width: 64, height: 64); VStack(alignment: .leading) { Text("Koala Remote").font(.system(size: 28, weight: .bold, design: .rounded)); Text("Your grove, from your phone.").foregroundColor(GroveTheme.muted) }; Spacer() }
                Text(remote.status).font(.callout).foregroundColor(GroveTheme.mint).textSelection(.enabled)
                if !remote.enabled || !remote.ready { Button(remote.enabled ? "Retry connection" : "Enable phone remote") { remote.start() }.controlSize(.large) }
                if remote.ready {
                    Text("1. Trust this Mac on your iPhone").font(.headline)
                    Text("AirDrop the setup profile to your iPhone 11. On the phone, install it in Settings → General → VPN & Device Management, then enable Koala Remote in General → About → Certificate Trust Settings. This is a local certificate for this Mac; it does not manage your phone.").font(.callout).foregroundColor(GroveTheme.muted)
                    HStack { Button("AirDrop setup profile…") { remote.shareProfile() }; Button("Show setup file") { remote.revealProfile() } }
                    DisclosureGroup("Certificate fingerprint") { Text(remote.fingerprint).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }
                    Divider()
                    Text("2. Open Koala Remote in Safari").font(.headline)
                    HStack(spacing: 20) { if let qr = remote.qr { Image(nsImage: qr).interpolation(.none).resizable().frame(width: 160, height: 160).padding(8).background(Color.white).cornerRadius(12) }; VStack(alignment: .leading, spacing: 12) { Text(remote.address).font(.callout).textSelection(.enabled); Button("Copy address") { remote.copyAddress() }; Text("Use the same Wi-Fi as this Mac. Add it to the Home Screen from Safari’s Share menu.").font(.caption).foregroundColor(GroveTheme.muted) } }
                    Text("3. Pair the phone").font(.headline)
                    HStack { Text(remote.pairingCode.isEmpty ? "••••••" : remote.pairingCode).font(.system(size: 32, weight: .bold, design: .monospaced)).textSelection(.enabled); Spacer(); Button("New pairing code") { remote.newPairingCode() } }
                    Text("Codes expire after five minutes. Approve the matching request below.").font(.caption).foregroundColor(GroveTheme.muted)
                    if let name = remote.pendingName {
                        VStack(alignment: .leading, spacing: 9) { Text("Pair \(name)?").font(.headline); Text("Check code: \(remote.pendingCheck). This phone can run shortcuts and control your Mac’s pointer and text input.").font(.callout); HStack { Button("Approve phone") { remote.approve() }.buttonStyle(.borderedProminent); Button("Decline") { remote.deny() } } }.padding(14).background(GroveTheme.panel).cornerRadius(12)
                    }
                    if !remote.peers.isEmpty {
                        Divider(); Text("Paired phones").font(.headline)
                        ForEach(remote.peers) { peer in HStack { Text(peer.name); Spacer(); Button("Revoke access") { remote.revoke(peer) } } }
                    }
                    Divider(); Button("Turn off phone remote") { remote.stop() }
                }
            }.padding(25)
        }.background(GroveTheme.background).foregroundColor(GroveTheme.text).tint(GroveTheme.mint).preferredColorScheme(.dark).frame(minWidth: 530, minHeight: 650)
    }
}
