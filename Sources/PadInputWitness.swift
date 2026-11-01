import Foundation
import IOKit.hid

/// Observe only the selected device and only its mapped inputs, for provenance.
/// No seize option and no observation of typing on other keyboards.
final class PadInputWitness {
    private var manager: IOHIDManager?
    private var known: [UInt64:String] = [:]
    private var presses: [String:TimeInterval] = [:]
    func start(vendor: Int, product: Int, bindings: [NativeBinding]) {
        stop()
        for b in bindings { known[b.sourceUsage] = b.control; known[b.relayUsage] = b.control }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager,[kIOHIDVendorIDKey:vendor,kIOHIDProductIDKey:product] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(manager,{ context,_,_,value in
            guard let context = context, IOHIDValueGetIntegerValue(value) != 0 else { return }
            let owner = Unmanaged<PadInputWitness>.fromOpaque(context).takeUnretainedValue()
            let element = IOHIDValueGetElement(value)
            let usage = UInt64(IOHIDElementGetUsagePage(element)) << 32 | UInt64(IOHIDElementGetUsage(element))
            if let control = owner.known[usage] { owner.presses[control] = ProcessInfo.processInfo.systemUptime }
        },Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager,CFRunLoopGetMain(),CFRunLoopMode.commonModes.rawValue)
        if IOHIDManagerOpen(manager,IOOptionBits(kIOHIDOptionsTypeNone)) != kIOReturnSuccess { stop() }
    }
    func origin(for control: String) -> ShortcutOrigin {
        guard let time = presses.removeValue(forKey: control), ProcessInfo.processInfo.systemUptime-time < 0.3 else { return .keyboardRelay }
        return .miniKeyboard
    }
    func stop() {
        if let manager = manager { IOHIDManagerUnscheduleFromRunLoop(manager,CFRunLoopGetMain(),CFRunLoopMode.commonModes.rawValue); IOHIDManagerClose(manager,IOOptionBits(kIOHIDOptionsTypeNone)) }
        manager = nil; known.removeAll(); presses.removeAll()
    }
    deinit { stop() }
}
