import AppKit
import ApplicationServices
import Carbon

struct LaptopBinding: Identifiable, Equatable {
    let key: String
    let keyCode: UInt32
    let control: String
    let action: ActionRef
    var id: String { control }
    var combo: String { "⌘⌥" + key }
    var title: String { Actions.byID[action.id]?.cap ?? "Shortcut" }
    var artwork: String? {
        GroveAction.from(action)?.rawValue ?? WindowArtwork.names[action.id]
    }
    var detail: String {
        switch action.id {
        case "grove_connect": return "Choose your instance"
        case "grove_viz": return "localhost:8300"
        case "grove_media": return "Music & streaming · iPad first"
        case "grove_write": return "Obsidian left · Slack right"
        case "grove_code": return "VS Code fills the display"
        case "grove_build": return "Zed left · Chrome right"
        case "grove_claude": return "2 chats · nvitop · shell"
        case "win_left": return "Focused window → left"
        case "win_max": return "Focused window fills its display"
        case "win_right": return "Focused window → right"
        case "win_min": return "Minimize to Dock"
        default: return Actions.describe(action)
        }
    }
}

enum LaptopPlan {
    static let modifiers: UInt32 = UInt32(cmdKey | optionKey)
    static let locations: [(key: String, code: String, control: String)] = [
        ("1", "1", "k1"), ("2", "2", "k2"), ("3", "3", "k3"),
        ("4", "4", "k4"), ("5", "5", "k5"), ("6", "6", "k6"),
        ("7", "7", "k8"), ("[", "open_bracket", "k10"),
        ("]", "close_bracket", "k11"), ("\\", "backslash", "k12"),
        ("P", "p", "k9")
    ]

    static func build(_ settings: PadSettings) -> [LaptopBinding] {
        locations.compactMap { location in
            guard let action = settings.mapping(location.control).action,
                  let definition = Actions.byID[action.id],
                  let keyCode = NativePlan.macCodes[location.code] else { return nil }
            // Prevent a custom action from recursively invoking any laptop shortcut.
            let output: (String, [String])?
            switch definition.kind {
            case .keys(let key, let mods): output = (key, mods)
            case .customShortcut: output = action.params["code"].map { ($0, action.mods) }
            default: output = nil
            }
            if let output = output, Set(output.1) == Set(["cmd", "opt"]),
               locations.contains(where: { $0.code == output.0 }) { return nil }
            return LaptopBinding(key: location.key, keyCode: keyCode, control: location.control, action: action)
        }
    }
}

/// Time-based modifier reminder. Holding modifiers alone never executes an action.
struct LaptopHoldState {
    static let delay: TimeInterval = 0.65
    private var began: TimeInterval?
    private var suppressed = false
    private(set) var visible = false

    mutating func update(flags: NSEvent.ModifierFlags, now: TimeInterval) -> Bool {
        let significant = flags.intersection([.command, .option, .control, .shift])
        guard significant == [.command, .option] else {
            began = nil; suppressed = false; visible = false
            return false
        }
        guard !suppressed else { return false }
        if began == nil { began = now }
        visible = now - (began ?? now) >= Self.delay
        return visible
    }

    mutating func cancelUntilRelease() { suppressed = true; began = nil; visible = false }
}

/// Separate from the device engine so these work when the USB pad is disconnected.
final class LaptopShortcuts {
    var onAction: ((LaptopBinding) -> Void)?
    var onGuideVisibility: ((Bool) -> Void)?
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var bindings: [LaptopBinding] = []
    private var heldKeys: Set<UInt32> = []
    private let chord = CornerInput()
    private var timer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var state = LaptopHoldState()
    private let guide = LaptopGuide()
    private var generation = 0
    private(set) var activeCount = 0
    private static let signature: OSType = 0x4b4f414c

    func start(bindings: [LaptopBinding]) throws {
        stop()
        guard AXIsProcessTrusted() else { throw GroveError.message("Allow Accessibility for laptop shortcuts.") }
        guard !bindings.isEmpty else { return }
        self.bindings = bindings
        chord.onTrigger = { [weak self] trigger in self?.dispatch(trigger) }
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        do {
            let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context -> OSStatus in
                guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<LaptopShortcuts>.fromOpaque(context).takeUnretainedValue()
                var id = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                               nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard result == noErr, id.signature == LaptopShortcuts.signature, Int(id.id) < owner.bindings.count else {
                    return OSStatus(eventNotHandledErr)
                }
                let binding = owner.bindings[Int(id.id)]
                let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
                if released { owner.heldKeys.remove(id.id) }
                else if !owner.heldKeys.insert(id.id).inserted { return noErr }
                owner.cancelGuide()
                if CornerChordState.defaults[binding.control] == binding.action.id {
                    if released { owner.chord.release(binding.control) } else { owner.chord.press(binding.control) }
                } else if !released { owner.dispatch(.single(binding.control)) }
                return noErr
            }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard result == noErr else { throw GroveError.message("Could not enable laptop shortcuts (\(result)).") }
            for (index, binding) in bindings.enumerated() {
                var ref: EventHotKeyRef?
                let result = RegisterEventHotKey(binding.keyCode, LaptopPlan.modifiers,
                    EventHotKeyID(signature: Self.signature, id: UInt32(index)), GetApplicationEventTarget(), 0, &ref)
                guard result == noErr, let ref = ref else {
                    throw GroveError.message("\(binding.combo) is already registered by another app. Laptop shortcuts are off.")
                }
                hotKeys.append(ref)
            }
            activeCount = bindings.count
            // Only used to dismiss the reminder after another key; no text is read or saved.
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in self?.cancelGuide() }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.cancelGuide(); return event
            }
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateGuide() }
            timer.tolerance = 0.02
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } catch { stop(); throw error }
    }

    private func dispatch(_ trigger: CornerTrigger) {
        let generation = self.generation
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.generation == generation, self.activeCount > 0 else { return }
            switch trigger {
            case .single(let control):
                guard let binding = self.bindings.first(where: { $0.control == control }) else { return }
                NativeAction.perform(binding.action, control: binding.combo, origin: .macKeyboard)
                self.onAction?(binding)
            case .corner(let corner):
                NativeAction.perform(ActionRef(id:corner.actionID), control:"⌘⌥ " + corner.laptop, origin:.macKeyboard)
                if let first = self.bindings.first { self.onAction?(LaptopBinding(key:corner.laptop,keyCode:first.keyCode,control:corner.actionID,action:ActionRef(id:corner.actionID))) }
            }
        }
    }

    private func updateGuide() {
        guard activeCount > 0, AXIsProcessTrusted(), !IsSecureEventInputEnabled() else {
            cancelGuide(); return
        }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue))
        let wasVisible = state.visible
        let visible = state.update(flags: flags, now: ProcessInfo.processInfo.systemUptime)
        if visible && !wasVisible {
            guide.show(bindings: bindings)
            onGuideVisibility?(true)
        } else if !visible && wasVisible {
            guide.hide(); onGuideVisibility?(false)
        }
        if !flags.contains(.command) || !flags.contains(.option) { chord.drain(); heldKeys.removeAll() }
    }

    func dismissGuide() { cancelGuide() }

    private func cancelGuide() {
        let wasVisible = state.visible
        state.cancelUntilRelease()
        guide.hide()
        if wasVisible { onGuideVisibility?(false) }
    }

    func stop() {
        generation += 1
        chord.cancel()
        timer?.invalidate(); timer = nil
        if let globalMonitor = globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor = localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
        cancelGuide(); state = LaptopHoldState()
        hotKeys.forEach { UnregisterEventHotKey($0) }; hotKeys.removeAll()
        if let handler = handler { RemoveEventHandler(handler) }
        handler = nil; bindings.removeAll(); heldKeys.removeAll(); activeCount = 0
    }
}
