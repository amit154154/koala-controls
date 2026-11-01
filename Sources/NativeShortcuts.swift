import AppKit
import ApplicationServices
import Carbon
import IOKit.hid
import IOKit.hidsystem

struct NativeBinding {
    let control: String
    let sourceUsage: UInt64
    let relayUsage: UInt64
    let relayCode: UInt32
    let action: ActionRef
}

enum NativePlan {
    // Exclude F11 (Show Desktop) and F14/F15 (display brightness): macOS can
    // perform those actions even when Carbon hotkey registration succeeds.
    // Keep the other relay positions stable; replace only F14/F15 with F6/F7.
    static let slots: [(UInt64, UInt32)] = [(0x6c, 64), (0x6d, 79), (0x6e, 80), (0x6f, 90),
                                           (0x68, 105), (0x3f, 97), (0x40, 98), (0x6b, 106),
                                           (0x45, 111), (0x41, 100), (0x43, 109), (0x42, 101),
                                           (0x3d, 118), (0x3e, 96),
                                           // JIS keypad comma has no Mission Control or brightness behavior.
                                           (0x85, UInt32(kVK_JIS_KeypadComma)),
                                           (0x67, UInt32(kVK_ANSI_KeypadEquals))]
    // Append new controls so all existing relay keys stay stable.
    static let preferredOrder = ["Rccw", "Rcw", "k1", "k2", "k3", "k4", "k5", "k6", "k8", "k10", "k11", "k12", "k7", "Lpress", "Rpress", "k9"]
    static func sourceUsage(_ source: Source) -> UInt64? {
        switch source {
        case .key(let code, let mods): return mods.isEmpty ? usage(code).map { 0x700000000 | $0 } : nil
        // Consumer-page mute from the left knob. Rotating volume inputs are untouched.
        case .media("mute"): return 0xc000000e2
        default: return nil
        }
    }
    static let macCodes = Dictionary(uniqueKeysWithValues: Keys.fromMacKeyCode.map { ($0.value, UInt32($0.key)) })
    static func usage(_ code: String) -> UInt64? {
        if let i = Keys.letters.firstIndex(of: code) { return UInt64(4 + i) }
        if let i = Keys.digits.firstIndex(of: code) { return UInt64(0x1e + i) }
        if code.hasPrefix("f"), let n = Int(code.dropFirst()), (1...24).contains(n) {
            return UInt64(n <= 12 ? 0x39 + n : 0x5b + n)
        }
        return ["return_or_enter": 0x28, "escape": 0x29, "delete_or_backspace": 0x2a,
                "tab": 0x2b, "spacebar": 0x2c, "hyphen": 0x2d, "equal_sign": 0x2e,
                "open_bracket": 0x2f, "close_bracket": 0x30, "backslash": 0x31,
                "semicolon": 0x33, "quote": 0x34, "grave_accent_and_tilde": 0x35,
                "comma": 0x36, "period": 0x37, "slash": 0x38,
                "insert": 0x49, "home": 0x4a, "page_up": 0x4b, "delete_forward": 0x4c,
                "end": 0x4d, "page_down": 0x4e, "right_arrow": 0x4f, "left_arrow": 0x50,
                "down_arrow": 0x51, "up_arrow": 0x52][code]
    }
    static func build(_ settings: PadSettings) -> (bindings: [NativeBinding], skipped: [String]) {
        var bindings: [NativeBinding] = []
        var skipped: [String] = []
        var used: Set<UInt64> = []
        for id in preferredOrder + Controls.order.filter({ !preferredOrder.contains($0) }) {
            let mapping = settings.mapping(id)
            guard let action = mapping.action else { continue }
            func skip(_ reason: String) { skipped.append("\(Controls.capitalized(Controls.info(id).name)): \(reason)") }
            guard let source = mapping.source else { skip("not learned yet"); continue }
            guard let usage = sourceUsage(source) else {
                skip("this mode needs a plain keyboard key or the knob’s mute input"); continue
            }
            guard !settings.clashes().keys.contains(id), !used.contains(usage) else { skip("another control sends the same key"); continue }
            guard let def = Actions.byID[action.id], KarabinerExport.toEvents(action, engine: .app) != nil else { skip("finish the action first"); continue }
            switch def.kind {
            case .keys(let key, _):
                guard macCodes[key] != nil else { skip("output key is unavailable in this mode"); continue }
                guard !slots.contains(where: { $0.1 == macCodes[key] }) else { skip("The relay keys are reserved in this mode"); continue }
            case .customShortcut:
                guard let key = action.params["code"], macCodes[key] != nil else { skip("output key is unavailable in this mode"); continue }
                guard !slots.contains(where: { $0.1 == macCodes[key] }) else { skip("The relay keys are reserved in this mode"); continue }
            default: break
            }
            guard bindings.count < slots.count else { skip("macOS mode supports up to sixteen assigned controls"); continue }
            let slot = slots[bindings.count]
            bindings.append(NativeBinding(control: id, sourceUsage: usage,
                                          relayUsage: 0x700000000 | slot.0, relayCode: slot.1, action: action))
            used.insert(usage)
        }
        return (bindings, skipped)
    }
}

/// Uses Apple's built-in device-scoped remapping and normal registered hotkeys.
/// It never seizes a keyboard. A device-scoped observer identifies only mapped pad inputs; ordinary typing is never recorded.
final class NativeShortcuts {
    private struct Mapping: Codable, Hashable {
        var source: UInt64
        var destination: UInt64
        var json: [String: NSNumber] { ["HIDKeyboardModifierMappingSrc": NSNumber(value: source), "HIDKeyboardModifierMappingDst": NSNumber(value: destination)] }
        var pair: [String: UInt64] { ["source": source, "destination": destination] }
    }
    private struct SavedService: Codable {
        var registryID: UInt64
        var original: [Mapping]
        var installed: [Mapping]
    }
    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
    }
    static var inputMonitoringAllowed: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    var onAction: ((String) -> Void)?
    private var client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var bindings: [NativeBinding] = []
    private var heldKeys: Set<UInt32> = []
    private let chord = CornerInput()
    private let witness = PadInputWitness()
    private var origins: [String:ShortcutOrigin] = [:]
    private var saved: [SavedService] = []
    private(set) var activeCount = 0
    private(set) var startAttempts = 0
    var activeServiceIDs: [UInt64] { saved.map(\.registryID) }
    private var vendor: Int?
    private var product: Int?
    private var generation = 0
    private let journal: URL
    private static let signature: OSType = 0x4d4e4b42

    init(directory: URL) {
        journal = directory.appendingPathComponent("native-mappings.json")
        if let data = try? Data(contentsOf: journal), let recovery = try? JSONDecoder().decode([SavedService].self, from: data) { saved = recovery }
        restoreMappings()
    }

    private func services() -> [IOHIDServiceClient] {
        // An unscheduled simple client can retain removed services across sleep/USB
        // reconnects. A fresh snapshot sees the new registry IDs and live properties.
        client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        return IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
    }
    private func registryID(_ service: IOHIDServiceClient) -> UInt64 { (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value ?? 0 }
    private func matches(_ service: IOHIDServiceClient, vendor: Int, product: Int) -> Bool {
        (IOHIDServiceClientCopyProperty(service, "VendorID" as CFString) as? Int) == vendor
            && (IOHIDServiceClientCopyProperty(service, "ProductID" as CFString) as? Int) == product
            && (IOHIDServiceClientConformsTo(service, 1, 6) != 0 || IOHIDServiceClientConformsTo(service, 12, 1) != 0)
    }
    private func mappings(_ service: IOHIDServiceClient) -> [Mapping] {
        let array = IOHIDServiceClientCopyProperty(service, "UserKeyMapping" as CFString) as? [[String: NSNumber]] ?? []
        return array.compactMap {
            guard let source = $0["HIDKeyboardModifierMappingSrc"], let dest = $0["HIDKeyboardModifierMappingDst"] else { return nil }
            return Mapping(source: source.uint64Value, destination: dest.uint64Value)
        }
    }
    @discardableResult private func setMappings(_ values: [Mapping], on service: IOHIDServiceClient) -> Bool {
        let accepted = IOHIDServiceClientSetProperty(service, "UserKeyMapping" as CFString, values.map(\.json) as CFArray)
        return accepted && Set(mappings(service)) == Set(values)
    }
    private func saveJournal() throws {
        try JSONEncoder().encode(saved).write(to: journal, options: .atomic)
    }

    static func restoring(current: [[String: UInt64]], original: [[String: UInt64]], installed: [[String: UInt64]]) -> [[String: UInt64]] {
        var restored = current
        for pair in installed where current.contains(pair) {
            restored.removeAll { $0 == pair }
            restored += original.filter { $0["source"] == pair["source"] }
        }
        return restored
    }

    private func restoreMappings() {
        var pending: [SavedService] = []
        let currentServices = services()
        for entry in saved {
            // A disconnected service no longer has any live mapping to restore.
            guard let service = currentServices.first(where: { registryID($0) == entry.registryID }) else { continue }
            let before = mappings(service)
            let restored = Self.restoring(current: before.map(\.pair), original: entry.original.map(\.pair), installed: entry.installed.map(\.pair))
            let current = restored.compactMap { pair -> Mapping? in
                guard let source = pair["source"], let destination = pair["destination"] else { return nil }
                return Mapping(source: source, destination: destination)
            }
            if Set(current) != Set(before), !setMappings(current, on: service) { pending.append(entry) }
        }
        saved = pending
        if saved.isEmpty { try? FileManager.default.removeItem(at: journal) }
        else { try? saveJournal() }
    }

    func stop() {
        generation += 1
        witness.stop(); chord.cancel(); origins.removeAll()
        // Restore physical keys before releasing the registered shortcuts.
        restoreMappings()
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let handler = handler { RemoveEventHandler(handler) }
        handler = nil
        bindings.removeAll(); heldKeys.removeAll()
        activeCount = 0
        vendor = nil; product = nil
    }

    func start(settings: PadSettings, bindings: [NativeBinding]) throws {
        startAttempts += 1
        stop()
        guard saved.isEmpty else {
            throw Failure.message(Self.inputMonitoringAllowed
                ? "The keyboard connection changed while restoring mappings. Retrying automatically…"
                : "Allow Input Monitoring to restore the previous keyboard mapping.")
        }
        guard let v = settings.vendorID, let p = settings.productID else { throw Failure.message("Choose a specific mini keyboard first.") }
        let selected = services().filter { matches($0, vendor: v, product: p) }
        guard !selected.isEmpty else { throw Failure.message("Connect the selected mini keyboard.") }
        guard AXIsProcessTrusted() else { throw Failure.message("Allow Accessibility for Mini Keyboard.") }
        // A cached property can echo our requested map even when the HID filter rejects it.
        guard Self.inputMonitoringAllowed else { throw Failure.message("Allow Input Monitoring for Mini Keyboard, then Apply again.") }
        self.bindings = bindings
        chord.onTrigger = { [weak self] trigger in self?.dispatch(trigger) }
        do {
            var eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                              EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context -> OSStatus in
                guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<NativeShortcuts>.fromOpaque(context).takeUnretainedValue()
                var id = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard result == noErr, id.signature == NativeShortcuts.signature, Int(id.id) < owner.bindings.count else { return OSStatus(eventNotHandledErr) }
                let binding = owner.bindings[Int(id.id)]
                let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
                if released { owner.heldKeys.remove(id.id) }
                else if !owner.heldKeys.insert(id.id).inserted { return noErr }
                let generation = owner.generation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak owner] in
                    guard let owner = owner, owner.generation == generation, owner.activeCount > 0 else { return }
                    if !released { owner.origins[binding.control] = owner.witness.origin(for: binding.control) }
                    let chordKey = CornerChordState.defaults[binding.control] == binding.action.id
                    if chordKey { if released { owner.chord.release(binding.control) } else { owner.chord.press(binding.control) } }
                    else if !released { owner.dispatch(.single(binding.control)) }
                }
                return noErr
            }, eventTypes.count, &eventTypes, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw Failure.message("Could not register shortcut handler (\(status)).") }
            for (index, binding) in bindings.enumerated() {
                var key: EventHotKeyRef?
                let result = RegisterEventHotKey(binding.relayCode, 0, EventHotKeyID(signature: Self.signature, id: UInt32(index)), GetApplicationEventTarget(), 0, &key)
                guard result == noErr, let key = key else { throw Failure.message("A reserved function key is already in use (\(result)).") }
                hotKeys.append(key)
            }
            let installed = bindings.map { Mapping(source: $0.sourceUsage, destination: $0.relayUsage) }
            let sources = Set(installed.map(\.source))
            for service in selected {
                let original = mappings(service)
                saved.append(SavedService(registryID: registryID(service), original: original, installed: installed))
                try saveJournal() // Save recovery information before touching the live device.
                let merged = original.filter { !sources.contains($0.source) } + installed
                guard setMappings(merged, on: service) else {
                    throw Failure.message(Self.inputMonitoringAllowed
                        ? "The keyboard connection changed while applying shortcuts. Retrying automatically…"
                        : "Allow Input Monitoring for Mini Keyboard, then Apply again.")
                }
            }
            vendor = v; product = p
            activeCount = bindings.count
            witness.start(vendor: v, product: p, bindings: bindings)
        } catch {
            stop()
            throw error
        }
    }

    private func dispatch(_ trigger: CornerTrigger) {
        switch trigger {
        case .single(let control):
            guard let selected = bindings.first(where: { $0.control == control }) else { return }
            NativeAction.perform(selected.action,control:control,origin:origins[control] ?? .keyboardRelay)
            onAction?(control)
        case .corner(let corner):
            let origin: ShortcutOrigin = chord.held.allSatisfy { origins[$0] == .miniKeyboard } ? .miniKeyboard : .keyboardRelay
            NativeAction.perform(ActionRef(id:corner.actionID),control:corner.pad,origin:origin)
            onAction?(corner.actionID)
        }
    }

    var connectionChanged: Bool {
        guard let vendor = vendor, let product = product else { return false }
        let current = services().filter { matches($0, vendor: vendor, product: product) }
        if Set(current.map { registryID($0) }) != Set(saved.map(\.registryID)) { return true }
        // Some hubs reset UserKeyMapping without changing the registry ID.
        return current.contains { service in
            guard let entry = saved.first(where: { $0.registryID == registryID(service) }) else { return true }
            return !Set(entry.installed).isSubset(of: Set(mappings(service)))
        }
    }
}

/// Retry failures even after start() cleared the old connection's IDs.
struct NativeReconnectPolicy {
    private var failures = 0
    private var nextAttempt = Date.distantPast
    mutating func finished(success: Bool, now: Date = Date()) {
        if success { failures = 0; nextAttempt = .distantPast }
        else {
            failures += 1
            nextAttempt = now.addingTimeInterval(min(15, 2.5 * pow(2, Double(min(3, failures - 1)))))
        }
    }
    func shouldRetry(enabled: Bool, connected: Bool, allowed: Bool, paused: Bool,
                     activeCount: Int, bindingCount: Int, now: Date = Date()) -> Bool {
        enabled && connected && allowed && !paused && activeCount == 0
            && bindingCount > 0 && now >= nextAttempt
    }
}

enum NativeAction {
    static func perform(_ action: ActionRef, control: String? = nil, origin: ShortcutOrigin = .app) {
        guard let def = Actions.byID[action.id] else { return }
        let click = AdventureStore.shared.begin(action: action.id, name: def.cap, trigger: control ?? "App", origin: origin)
        guard AXIsProcessTrusted() else { AdventureStore.shared.finish(click,success:false); return }
        var success = false
        var asynchronous = false
        defer { if !asynchronous { AdventureStore.shared.finish(click,success:success) } }
        let pointer = NSEvent.mouseLocation
        let feedback = { ShortcutFeedback.shared.react(actionID: action.id, control: control, pointer: pointer) }
        switch def.kind {
        case .workspace(let action):
            asynchronous = true
            GroveActions.shared.perform(action, onAccepted: feedback) { _, failed in AdventureStore.shared.finish(click,success:!failed) }
        case .window(let window): success = WindowSnapper.shared.perform(window); if success { feedback() }
        case .keys(let code, let mods): success = NativePlan.macCodes[code] != nil; if success { feedback(); sendKey(code, mods: mods) }
        case .customShortcut: if let code = action.params["code"], NativePlan.macCodes[code] != nil { success = true; feedback(); sendKey(code, mods: action.mods) }
        case .consumer(let code):
            guard let media = Media.all.first(where: { $0.consumer == code }),
                  let nx = Media.fromNXKeyType.first(where: { $0.value == media.id })?.key else { return }
            success = true; feedback()
            for down in [true, false] {
                let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
                let data = (nx << 16) | ((down ? 0xa : 0xb) << 8)
                NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                   context: nil, subtype: 8, data1: data, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
            }
        case .openApp:
            if let name = action.params["name"] {
                feedback()
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open"); process.arguments = ["-a", name]
                do { try process.run(); success = true } catch { success = false }
            }
        case .openURL:
            if var raw = action.params["url"] {
                if !raw.contains(":") && !raw.hasPrefix("/") { raw = "https://" + raw }
                if let url = raw.hasPrefix("/") ? URL(fileURLWithPath: raw) : URL(string: raw) { success = NSWorkspace.shared.open(url); if success { feedback() } }
            }
        case .shell:
            if let command = action.params["cmd"] {
                feedback()
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh"); process.arguments = ["-c", command]
                do { try process.run(); success = true } catch { success = false }
            }
        case .disable: break
        }
    }
    static func sendKey(_ code: String, mods: [String]) {
        guard let keyCode = NativePlan.macCodes[code] else { return }
        var flags: CGEventFlags = []
        for mod in mods {
            switch mod {
            case "cmd": flags.insert(.maskCommand)
            case "ctrl": flags.insert(.maskControl)
            case "opt": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            case "fn": flags.insert(.maskSecondaryFn)
            default: break
            }
        }
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }
}
