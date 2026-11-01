import Foundation
import IOKit

/// Karabiner distinguishes composite interfaces by these flags as well as their IDs.
struct HIDDeviceIdentifier: Hashable {
    let vendorID: Int
    let productID: Int
    let isKeyboard: Bool
    let isPointingDevice: Bool
    let isConsumer: Bool

    var sortKey: String { "\(isKeyboard):\(isPointingDevice):\(isConsumer)" }
    var json: [String: Any] {
        var value: [String: Any] = ["vendor_id": vendorID, "product_id": productID]
        if isKeyboard { value["is_keyboard"] = true }
        if isPointingDevice { value["is_pointing_device"] = true }
        if isConsumer { value["is_consumer"] = true }
        return value
    }

    func matches(_ value: [String: Any]) -> Bool {
        (value["vendor_id"] as? Int ?? 0) == vendorID
            && (value["product_id"] as? Int ?? 0) == productID
            && (value["is_keyboard"] as? Bool ?? false) == isKeyboard
            && (value["is_pointing_device"] as? Bool ?? false) == isPointingDevice
            && (value["is_consumer"] as? Bool ?? false) == isConsumer
    }
}

struct HIDDeviceInfo: Hashable, Identifiable {
    let vendorID: Int
    let productID: Int
    let name: String
    var interfaces: Set<HIDDeviceIdentifier>
    var id: String { "\(vendorID):\(productID)" }
    var hexIDs: String { String(format: "0x%04X / 0x%04X", vendorID, productID) }
}

/// Reads device metadata only; no input monitoring permission or key capture is needed.
enum HIDDevices {
    struct Snapshot {
        var keyboards: [HIDDeviceInfo]
        var virtualKeyboardReady: Bool
    }

    static func snapshot() -> Snapshot { snapshot(properties: registryProperties()) }

    static func snapshot(properties: [[String: Any]]) -> Snapshot {
        var byID: [String: HIDDeviceInfo] = [:]
        var virtualKeyboardReady = false
        for p in properties {
            let product = (p["Product"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let maker = (p["Manufacturer"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let isKarabiner = product.localizedCaseInsensitiveContains("karabiner")
                || maker.localizedCaseInsensitiveContains("pqrs")
            // PrimaryUsage can be Mouse even when this device also sends keyboard keys.
            var usages = p["DeviceUsagePairs"] as? [[String: Any]] ?? []
            usages.append(["DeviceUsagePage": p["PrimaryUsagePage"] ?? 0, "DeviceUsage": p["PrimaryUsage"] ?? 0])
            func hasUsage(_ page: Int, _ values: [Int]) -> Bool {
                usages.contains { ($0["DeviceUsagePage"] as? Int) == page && values.contains($0["DeviceUsage"] as? Int ?? -1) }
            }
            let keyboard = hasUsage(1, [6, 7])
            let pointing = hasUsage(1, [1, 2])
            let consumer = hasUsage(12, [1]) && !keyboard && !pointing
            if isKarabiner {
                if keyboard { virtualKeyboardReady = true }
                continue
            }
            guard keyboard || consumer else { continue }
            // Some mini keyboards borrow Apple's vendor ID. Filter actual Apple devices
            // by their manufacturer, never by vendor ID alone.
            if maker.lowercased().hasPrefix("apple") { continue }
            guard let vid = p["VendorID"] as? Int, let pid = p["ProductID"] as? Int else { continue }
            var name = product.isEmpty ? (maker.isEmpty ? "Unnamed keyboard" : maker) : product
            if !maker.isEmpty && !product.isEmpty && !product.localizedCaseInsensitiveContains(maker) {
                name = "\(product) (\(maker))"
            }
            let ident = HIDDeviceIdentifier(vendorID: vid, productID: pid,
                                            isKeyboard: keyboard, isPointingDevice: pointing, isConsumer: consumer)
            let key = "\(vid):\(pid)"
            if var existing = byID[key] {
                existing.interfaces.insert(ident)
                byID[key] = existing
            } else {
                byID[key] = HIDDeviceInfo(vendorID: vid, productID: pid, name: name, interfaces: [ident])
            }
        }
        return Snapshot(keyboards: byID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }, virtualKeyboardReady: virtualKeyboardReady)
    }

    private static func registryProperties() -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [[String: Any]] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let p = properties?.takeRetainedValue() as? [String: Any] { result.append(p) }
            IOObjectRelease(service)
        }
        return result
    }
}
