import AppKit
import ApplicationServices
import Combine
import ServiceManagement
import IOKit.hid

enum DetectPurpose: Equatable { case source, action }

struct DetectTarget: Equatable {
    var id: String
    var purpose: DetectPurpose
}

enum BuilderScope { case source, action }

enum LiveStatus: Equatable {
    case starting, live(Int), laptop(Int), off, needsDevice, needsKarabiner, needsDriver, disconnected, needsEvents, needsApply, needsAccessibility, nothing, error(String)

    var text: String {
        switch self {
        case .starting: return "Starting…"
        case .live(let n): return n == 1 ? "Ready: 1 shortcut" : "Ready: \(n) shortcuts"
        case .laptop(let n): return "Laptop ready: \(n) shortcuts"
        case .off: return "Shortcuts are off"
        case .needsDevice: return "Choose your mini keyboard"
        case .needsKarabiner: return "Install Karabiner-Elements"
        case .needsDriver: return "Finish Karabiner driver setup"
        case .disconnected: return "Mini keyboard disconnected"
        case .needsEvents: return "Enable the mini keyboard"
        case .needsApply: return "Apply shortcuts again"
        case .needsAccessibility: return "Allow Accessibility"
        case .nothing: return "No shortcuts set yet"
        case .error(let m): return m
        }
    }
    var isGood: Bool { switch self { case .live, .laptop: return true; default: return false } }
}

final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings: PadSettings = PadSettings.defaults() {
        didSet {
            guard settings != oldValue else { return }
            ShortcutFeedback.shared.preferences = settings.companion
            if !settings.enabled { ShortcutFeedback.shared.stop() }
            var previous = oldValue
            previous.companion = settings.companion
            settingsChanged(reapply: previous != settings)
        }
    }
    @Published var selection: String = "k2"
    @Published var detect: DetectTarget?
    @Published var learnIndex: Int?
    @Published var manualSource: Set<String> = []
    @Published var devices: [HIDDeviceInfo] = []
    @Published var live: LiveStatus = .starting {
        didSet { if live != oldValue { writeDiagnostic() } }
    }
    @Published var skipped: [String] = []
    @Published var accessibilityTrusted: Bool = AXIsProcessTrusted()
    @Published var inputMonitoringAllowed = NativeShortcuts.inputMonitoringAllowed
    @Published var karabinerInstalled: Bool = false
    @Published var karabinerDriverReady: Bool = false
    @Published var toast: String?
    @Published var knobAngle: [String: Double] = ["L": -28, "R": -28]
    @Published var lastNativeAction: String?
    @Published var nativeError: String?
    @Published var actionFeedback = "Your grove is ready."
    @Published var actionFailed = false
    @Published var laptopStatus = "Laptop shortcuts off"
    private var laptopGuideVisible = false
    private var padGuideVisible = false
    private let padGuide = PadGuide()

    private var draftMods: [String: [String]] = [:]
    private var monitor: Any?
    private var applyTimer: Timer?
    private var toastTimer: Timer?
    private var pollTimer: Timer?
    private var ignoreUntil = Date.distantPast
    private var pendingModifier: UInt16?
    private var sawKeyDown = false
    private var lastCapture: (sig: String, time: Date)?
    private var learnedCount = 0
    private var ruleSuspended = false
    private let settingsURL: URL
    private let native: NativeShortcuts
    private let laptop = LaptopShortcuts()
    private var reconnectPolicy = NativeReconnectPolicy()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mini Keyboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        settingsURL = support.appendingPathComponent("settings.json")
        native = NativeShortcuts(directory: support)
        if let data = try? Data(contentsOf: settingsURL), let saved = try? JSONDecoder().decode(PadSettings.self, from: data) {
            settings = saved
        }
        ShortcutFeedback.shared.preferences = settings.companion
        AdventureStore.shared.padConnected = { [weak self] in
            guard let self = self, let v = self.settings.vendorID, let p = self.settings.productID else { return false }
            return HIDDevices.snapshot().keyboards.contains { $0.vendorID == v && $0.productID == p }
        }
        AdventureStore.shared.onCelebration = { notices, origin in
            if origin != .phone { AdventureCelebration.shared.enqueue(notices) }
        }
        karabinerInstalled = AppModel.karabinerIsInstalled()
        native.onAction = { [weak self] id in
            guard let self = self else { return }
            if self.settings.mapping(id).action?.id != "grove_guide" { self.padGuide.hide() }
            self.nudgeKnob(id)
            self.lastNativeAction = Actions.describe(Actions.byID[id] != nil ? ActionRef(id:id) : self.settings.mapping(id).action ?? ActionRef(id: "disable"))
            self.writeDiagnostic()
        }
        GroveActions.shared.onStatus = { [weak self] message, failed in
            self?.actionFeedback = message
            self?.actionFailed = failed
            self?.writeDiagnostic()
        }
        GroveActions.shared.onPadGuide = { [weak self] in
            guard let self = self else { return }
            self.laptop.dismissGuide()
            self.padGuide.toggle(settings: self.settings)
        }
        padGuide.onVisibility = { [weak self] visible in
            self?.padGuideVisible = visible; self?.writeDiagnostic()
        }
        laptop.onAction = { [weak self] binding in
            self?.padGuide.hide()
            self?.lastNativeAction = binding.title
            self?.writeDiagnostic()
        }
        laptop.onGuideVisibility = { [weak self] visible in
            if visible { self?.padGuide.hide() }
            self?.laptopGuideVisible = visible
            self?.writeDiagnostic()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in self?.refreshEnvironment() }
    }

    // MARK: - Derived

    var clashes: [String: [String]] { settings.clashes() }

    var learnTargetID: String? {
        guard let i = learnIndex, i < Controls.order.count else { return nil }
        return Controls.order[i]
    }

    var learnInstruction: String {
        guard let id = learnTargetID else { return "" }
        let c = Controls.info(id)
        if let knob = c.knob {
            let side = knob == "L" ? "left" : "right"
            if id.hasSuffix("ccw") { return "Turn the \(side) knob to the left, one click" }
            if id.hasSuffix("cw") { return "Turn the \(side) knob to the right, one click" }
            return "Press the \(side) knob straight down"
        }
        return "Press the " + c.name.replacingOccurrences(of: " key", with: "") + " key"
    }

    var deviceTag: String {
        guard let v = settings.vendorID else { return "" }
        return "\(v):\(settings.productID ?? 0)"
    }

    // MARK: - Saving and applying

    private func settingsChanged(reapply: Bool = true) {
        persist()
        guard reapply else { return }
        applyTimer?.invalidate()
        applyTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in self?.applyNow() }
    }

    private func persist() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(settings) { try? data.write(to: settingsURL, options: .atomic) }
    }

    private func writeDiagnostic() {
        let data: [String: Any] = ["mode": settings.shortcutEngine.rawValue, "status": live.text,
                                  "activeShortcuts": native.activeCount, "accessibilityAllowed": AXIsProcessTrusted(),
                                  "inputMonitoringAllowed": NativeShortcuts.inputMonitoringAllowed,
                                  "nativeStartAttempts": native.startAttempts, "nativeServiceIDs": native.activeServiceIDs,
                                  "companionReactionCount": ShortcutFeedback.shared.reactionCount,
                                  "companionLastStyle": ShortcutFeedback.shared.lastStyle?.rawValue ?? "",
                                  "companionLastReaction": ShortcutFeedback.shared.lastReaction?.description ?? "",
                                  "lastAction": lastNativeAction ?? "", "skipped": skipped,
                                  "actionFeedback": actionFeedback, "actionFailed": actionFailed,
                                  "laptopShortcuts": laptop.activeCount, "laptopStatus": laptopStatus,
                                  "laptopGuideVisible": laptopGuideVisible, "padGuideVisible": padGuideVisible]
        if let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: settingsURL.deletingLastPathComponent().appendingPathComponent("runtime-status.json"), options: .atomic)
        }
    }

    /// Writes our rule into Karabiner's settings. Karabiner picks the change up by itself.
    func applyNow() {
        padGuide.hide()
        let config = KarabinerConfig.standard
        karabinerInstalled = AppModel.karabinerIsInstalled()
        refreshDevices()
        let result = KarabinerExport.build(settings)
        skipped = result.skipped
        if ruleSuspended { return }      // paused while learning keys; re-applied when learning ends
        applyLaptop()
        if settings.shortcutEngine == .native {
            applyNative()
            return
        }
        native.stop()
        do {
            if !settings.enabled {
                try config.write(rule: nil)
                live = .off
            } else if settings.vendorID == nil {
                try config.write(rule: nil)      // never apply without a device filter: it would change the Mac's own keyboard
                live = .needsDevice
            } else if result.count == 0 {
                try config.write(rule: nil)
                live = .nothing
            } else {
                try config.write(rule: result.rule, enabling: selectedDevice)
                updateLiveStatus()
            }
        } catch {
            live = .error(error.localizedDescription)
        }
    }

    static func karabinerIsInstalled() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: "/Applications/Karabiner-Elements.app")
            || fm.fileExists(atPath: "/Library/Application Support/org.pqrs/Karabiner-Elements")
    }

    private func applyLaptop() {
        laptop.stop()
        guard settings.enabled && settings.laptopShortcutsEnabled && detect == nil else {
            laptopStatus = "Laptop shortcuts off"; writeDiagnostic(); return
        }
        guard AXIsProcessTrusted() else {
            laptopStatus = "Allow Accessibility for laptop shortcuts"; writeDiagnostic(); return
        }
        do {
            try laptop.start(bindings: LaptopPlan.build(settings))
            laptopStatus = "\(laptop.activeCount) laptop shortcuts ready · hold ⌘⌥ for the guide"
        } catch { laptopStatus = error.localizedDescription }
        writeDiagnostic()
    }

    func refreshEnvironment() {
        let trusted = AXIsProcessTrusted()
        let inputAllowed = NativeShortcuts.inputMonitoringAllowed
        let permissionChanged = trusted != accessibilityTrusted || inputAllowed != inputMonitoringAllowed
        if inputAllowed != inputMonitoringAllowed { inputMonitoringAllowed = inputAllowed }
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        if settings.shortcutEngine == .native {
            let wasConnected = selectedDevice != nil
            refreshDevices()
            if !ruleSuspended {
                if permissionChanged { applyNow() }
                else if native.connectionChanged || wasConnected != (selectedDevice != nil)
                    || reconnectPolicy.shouldRetry(enabled: settings.enabled, connected: selectedDevice != nil,
                        allowed: trusted && inputAllowed, paused: ruleSuspended, activeCount: native.activeCount,
                        bindingCount: NativePlan.build(settings).bindings.count) {
                    // Reconnect the pad without interrupting laptop hotkeys or their guide.
                    applyNative()
                }
            }
            return
        }
        let installed = AppModel.karabinerIsInstalled()
        if installed != karabinerInstalled {
            karabinerInstalled = installed
            applyNow()
        } else {
            refreshDevices()
            if !ruleSuspended {
                if case .error = live { return }
                updateLiveStatus()
            }
        }
    }

    private var selectedDevice: HIDDeviceInfo? { devices.first { $0.id == deviceTag } }

    private func applyNative() {
        defer { reconnectPolicy.finished(success: native.activeCount > 0) }
        native.stop()
        nativeError = nil
        let plan = NativePlan.build(settings)
        skipped = plan.skipped
        do {
            // Remove only this app's rule; retain all unrelated Karabiner configuration.
            try KarabinerConfig.standard.write(rule: nil)
            if !settings.enabled { live = .off; return }
            guard settings.vendorID != nil, settings.productID != nil else {
                live = laptop.activeCount > 0 ? .laptop(laptop.activeCount) : .needsDevice; return
            }
            guard selectedDevice != nil else {
                live = laptop.activeCount > 0 ? .laptop(laptop.activeCount) : .disconnected; return
            }
            guard !plan.bindings.isEmpty else { live = .nothing; return }
            guard AXIsProcessTrusted() else { live = .needsAccessibility; return }
            try native.start(settings: settings, bindings: plan.bindings)
            live = .live(native.activeCount)
        } catch {
            nativeError = error.localizedDescription
            live = .error(error.localizedDescription)
        }
    }

    func shutdown() {
        ShortcutFeedback.shared.stop()
        padGuide.hide()
        applyTimer?.invalidate()
        pollTimer?.invalidate()
        if settings.shortcutEngine == .native {
            removeMonitor()
            native.stop()
        } else { learnStop() }
        laptop.stop()
    }

    private func updateLiveStatus() {
        let result = KarabinerExport.build(settings)
        if !settings.enabled { live = .off }
        else if settings.vendorID == nil { live = .needsDevice }
        else if result.count == 0 { live = .nothing }
        else if !karabinerInstalled { live = .needsKarabiner }
        else if !karabinerDriverReady { live = .needsDriver }
        else if let device = selectedDevice {
            let config = KarabinerConfig.standard
            if !config.isInstalled() { live = .needsApply }
            else if !config.eventsEnabled(for: device) { live = .needsEvents }
            else { live = .live(result.count) }
        } else { live = laptop.activeCount > 0 ? .laptop(laptop.activeCount) : .disconnected }
    }

    func windowDidOpen() {
        refreshEnvironment()
        refreshDevices()
    }

    // MARK: - Devices

    func refreshDevices() {
        let snapshot = HIDDevices.snapshot()
        if devices != snapshot.keyboards { devices = snapshot.keyboards }
        if karabinerDriverReady != snapshot.virtualKeyboardReady { karabinerDriverReady = snapshot.virtualKeyboardReady }
    }

    func selectDevice(_ tag: String) {
        if tag.isEmpty {
            settings.vendorID = nil; settings.productID = nil; settings.deviceName = nil
            return
        }
        if let d = devices.first(where: { $0.id == tag }) {
            settings.vendorID = d.vendorID; settings.productID = d.productID; settings.deviceName = d.name
        }
    }

    static func parseNumber(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasPrefix("0x") { return Int(t.dropFirst(2), radix: 16) }
        return Int(t)
    }

    func setVendorText(_ s: String) { settings.vendorID = AppModel.parseNumber(s); settings.deviceName = nil }
    func setProductText(_ s: String) { settings.productID = AppModel.parseNumber(s); settings.deviceName = nil }

    // MARK: - Editing

    func select(_ id: String) {
        if learnIndex == nil && detect != nil { cancelDetect() }
        selection = id
    }

    func setAction(_ id: String, _ actionID: String) {
        if detect == DetectTarget(id: id, purpose: .action) { cancelDetect() }
        settings.controls[id, default: ControlMapping()].action = actionID.isEmpty ? nil : ActionRef(id: actionID)
    }

    func setParam(_ id: String, _ key: String, _ value: String) {
        settings.controls[id, default: ControlMapping()].action?.params[key] = value
    }

    func param(_ id: String, _ key: String) -> String {
        settings.mapping(id).action?.params[key] ?? ""
    }

    func setSource(_ id: String, _ source: Source?) {
        settings.controls[id, default: ControlMapping()].source = source
    }

    func pickMedia(_ id: String, _ media: String) {
        manualSource.remove(id)
        if detect?.id == id { cancelDetect() }
        setSource(id, .media(media))
    }

    func openManual(_ id: String) {
        if detect != nil { cancelDetect() }
        manualSource.insert(id)
    }

    func closeManual(_ id: String) {
        manualSource.remove(id)
        draftMods[id] = nil
    }

    func builderMods(_ id: String, _ scope: BuilderScope) -> [String] {
        switch scope {
        case .action: return settings.mapping(id).action?.mods ?? []
        case .source:
            if case .key(_, let mods)? = settings.mapping(id).source { return mods }
            return draftMods[id] ?? []
        }
    }

    func builderCode(_ id: String, _ scope: BuilderScope) -> String {
        switch scope {
        case .action: return settings.mapping(id).action?.params["code"] ?? ""
        case .source:
            if case .key(let code, _)? = settings.mapping(id).source { return code }
            return ""
        }
    }

    func toggleBuilderMod(_ id: String, _ scope: BuilderScope, _ m: String) {
        let current = builderMods(id, scope)
        let next = current.contains(m) ? current.filter { $0 != m } : current + [m]
        switch scope {
        case .action:
            settings.controls[id, default: ControlMapping()].action?.mods = Mods.sorted(next)
        case .source:
            if case .key(let code, _)? = settings.mapping(id).source {
                setSource(id, .key(code: code, mods: Mods.sorted(next)))
            } else {
                draftMods[id] = next
                objectWillChange.send()
            }
        }
    }

    func setBuilderKey(_ id: String, _ scope: BuilderScope, _ code: String) {
        switch scope {
        case .action:
            settings.controls[id, default: ControlMapping()].action?.params["code"] = code
        case .source:
            setSource(id, code.isEmpty ? nil : .key(code: code, mods: Mods.sorted(builderMods(id, .source))))
        }
    }

    func resetLayout() {
        var fresh = PadSettings.defaults()
        fresh.vendorID = settings.vendorID
        fresh.productID = settings.productID
        fresh.deviceName = settings.deviceName
        fresh.snapEngine = settings.snapEngine
        fresh.shortcutEngine = settings.shortcutEngine
        fresh.laptopShortcutsEnabled = settings.laptopShortcutsEnabled
        cancelDetect()
        learnIndex = nil
        manualSource = []
        selection = "R"
        settings = fresh
        showToast("Back to the default layout.")
    }

    // MARK: - Learning what a key sends

    func toggleDetect(_ id: String) {
        let t = DetectTarget(id: id, purpose: .source)
        if detect == t { cancelDetect() } else { startDetect(t) }
    }

    func toggleRecord(_ id: String) {
        let t = DetectTarget(id: id, purpose: .action)
        if detect == t { cancelDetect() } else { startDetect(t) }
    }

    func startDetect(_ target: DetectTarget) {
        padGuide.hide()
        removeMonitor()
        laptop.stop()
        laptopStatus = "Laptop shortcuts paused while learning"
        if target.purpose == .source {
            manualSource.remove(target.id)
            // Pause our Karabiner rule so the app sees what the key really sends, not what it's mapped to.
            if !ruleSuspended {
                ruleSuspended = true
                native.stop()
                try? KarabinerConfig.standard.write(rule: nil)
            }
        }
        detect = target
        ignoreUntil = Date().addingTimeInterval(0.2)
        pendingModifier = nil
        sawKeyDown = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .systemDefined]) { [weak self] event in
            guard let self = self, self.detect != nil else { return event }
            self.handle(event)
            return nil
        }
    }

    func cancelDetect() {
        removeMonitor()
        if detect != nil { detect = nil }
        if ruleSuspended {
            ruleSuspended = false
            applyNow()
        } else { applyLaptop() }
    }

    private func removeMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard Date() >= ignoreUntil else { return }
        switch event.type {
        case .keyDown:
            if event.isARepeat { return }
            sawKeyDown = true
            guard let code = Keys.fromMacKeyCode[event.keyCode] else {
                showToast("That key can’t be read here. Pick it from the list instead.")
                return
            }
            capture(.key(code: code, mods: AppModel.mods(from: event.modifierFlags)))
        case .flagsChanged:
            let kc = event.keyCode
            guard let code = Keys.fromMacKeyCode[kc] else { return }
            if kc == 0x39 { capture(.key(code: code, mods: [])); return }          // caps lock
            if AppModel.isModifierDown(kc, event.modifierFlags) {
                pendingModifier = kc
                sawKeyDown = false
            } else if pendingModifier == kc && !sawKeyDown {
                pendingModifier = nil
                capture(.key(code: code, mods: []))
            }
        case .systemDefined:
            guard event.subtype.rawValue == 8 else { return }
            let data1 = event.data1
            let keyType = (data1 & 0xFFFF0000) >> 16
            let keyState = (data1 & 0xFF00) >> 8
            guard keyState == 0x0A, let media = Media.fromNXKeyType[keyType] else { return }
            capture(.media(media))
        default:
            break
        }
    }

    static func mods(from flags: NSEvent.ModifierFlags) -> [String] {
        var m: [String] = []
        if flags.contains(.control) { m.append("ctrl") }
        if flags.contains(.option) { m.append("opt") }
        if flags.contains(.shift) { m.append("shift") }
        if flags.contains(.command) { m.append("cmd") }
        return m
    }

    static func isModifierDown(_ keyCode: UInt16, _ f: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case 0x38, 0x3C: return f.contains(.shift)
        case 0x3B, 0x3E: return f.contains(.control)
        case 0x3A, 0x3D: return f.contains(.option)
        case 0x37, 0x36: return f.contains(.command)
        case 0x3F: return f.contains(.function)
        default: return false
        }
    }

    private func capture(_ src: Source) {
        guard let target = detect else { return }

        if target.purpose == .action {
            guard case .key(let code, let mods) = src else {
                showToast("That’s a media key. Choose it under Media instead.")
                return
            }
            if code.hasPrefix("left_") || code.hasPrefix("right_") || code == "fn" || code == "caps_lock" {
                showToast("Hold the modifier keys and press another key, like ⌘⇧4.")
                return
            }
            var m = settings.mapping(target.id)
            if m.action == nil { m.action = ActionRef(id: "custom") }
            m.action?.params["code"] = code
            m.action?.mods = Mods.sorted(mods)
            settings.controls[target.id] = m
            cancelDetect()
            return
        }

        // A knob sends a burst of clicks; ignore repeats of the one just learned.
        let sig = src.signature
        if learnIndex != nil, let last = lastCapture, last.sig == sig, Date().timeIntervalSince(last.time) < 0.9 { return }
        lastCapture = (sig, Date())
        setSource(target.id, src)
        nudgeKnob(target.id)
        if learnIndex != nil {
            learnAdvance(learned: true)
            return
        }
        cancelDetect()
        showToast("\(Controls.capitalized(Controls.info(target.id).name)) sends \(src.text).")
    }

    private func nudgeKnob(_ id: String) {
        guard let k = Controls.info(id).knob else { return }
        let delta: Double = id.hasSuffix("ccw") ? -24 : (id.hasSuffix("cw") ? 24 : 0)
        knobAngle[k, default: -28] += delta
    }

    // MARK: - Learn all keys

    func learnStart() {
        learnedCount = 0
        learnIndex = 0
        lastCapture = nil
        learnGo()
    }

    private func learnGo() {
        guard let id = learnTargetID else { learnFinish(); return }
        selection = Controls.info(id).knob ?? id
        startDetect(DetectTarget(id: id, purpose: .source))
        ignoreUntil = Date().addingTimeInterval(0.35)
    }

    private func learnAdvance(learned: Bool) {
        if learned { learnedCount += 1 }
        learnIndex = (learnIndex ?? 0) + 1
        if (learnIndex ?? 0) >= Controls.order.count { learnFinish() } else { learnGo() }
    }

    func learnSkip() { learnAdvance(learned: false) }

    func learnPickMedia(_ media: String) {
        guard let id = learnTargetID else { return }
        setSource(id, .media(media))
        lastCapture = (Source.media(media).signature, Date.distantPast)
        nudgeKnob(id)
        learnAdvance(learned: true)
    }

    private func learnFinish() {
        let n = learnedCount
        learnIndex = nil
        cancelDetect()
        showToast("Done. Learned \(n) of \(Controls.order.count).")
    }

    func learnStop() {
        learnIndex = nil
        cancelDetect()
    }

    // MARK: - Permissions and other apps

    func requestAccessibility() {
        WindowSnapper.askForAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
    }

    func openKarabiner() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Karabiner-Elements.app"))
    }

    var openAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                showToast("Couldn’t change Open at login: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toast = message
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: false) { [weak self] _ in self?.toast = nil }
    }
}
