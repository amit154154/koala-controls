import Foundation

@main
enum Regression {
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError(message) }
    }
    static func main() throws {
        let combo: [[String: Any]] = [
            ["DeviceUsagePage": 1, "DeviceUsage": 2],
            ["DeviceUsagePage": 1, "DeviceUsage": 6],
            ["DeviceUsagePage": 12, "DeviceUsage": 1]
        ]
        let usb: [String: Any] = ["Product": "USB Composite Device", "VendorID": 4489, "ProductID": 34882,
                                  "PrimaryUsagePage": 1, "PrimaryUsage": 6, "DeviceUsagePairs": combo]
        let bt: [String: Any] = ["Product": "MINI-KEYBOARD", "Manufacturer": "CXKJ", "VendorID": 1452, "ProductID": 556,
                                 "PrimaryUsagePage": 1, "PrimaryUsage": 2, "DeviceUsagePairs": combo]
        let apple: [String: Any] = ["Product": "Magic Keyboard", "Manufacturer": "Apple Inc.", "VendorID": 76, "ProductID": 615,
                                    "PrimaryUsagePage": 1, "PrimaryUsage": 6]
        let virtual: [String: Any] = ["Product": "Karabiner DriverKit VirtualHIDKeyboard", "Manufacturer": "pqrs.org",
                                      "PrimaryUsagePage": 1, "PrimaryUsage": 6]
        let snapshot = HIDDevices.snapshot(properties: [usb, bt, apple, virtual, usb])
        check(snapshot.keyboards.count == 2, "Keep both mini-keyboard transports; exclude real Apple and virtual devices")
        check(snapshot.virtualKeyboardReady, "Detect the virtual keyboard")
        check(!HIDDevices.snapshot(properties: [usb, bt]).virtualKeyboardReady, "An installed app alone is not a working driver")
        let pad = snapshot.keyboards.first { $0.vendorID == 4489 }!
        check(pad.interfaces.count == 1, "Deduplicate registry interfaces")
        check(pad.interfaces.first!.isPointingDevice, "Detect composite mouse interface")
        check(snapshot.keyboards.contains { $0.vendorID == 1452 }, "Do not hide a mini keyboard that borrows Apple's vendor ID")

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let config = KarabinerConfig(directory: temp)
        let original: [String: Any] = ["global": ["show_in_menu_bar": false], "profiles": [
            ["name": "Other", "selected": false, "devices": [["identifiers": ["vendor_id": 99], "ignore": true]]],
            ["name": "Default", "selected": true,
             "devices": [["identifiers": pad.interfaces.first!.json, "ignore": true, "manipulate_caps_lock_led": false],
                         ["identifiers": ["vendor_id": 999, "product_id": 123, "is_keyboard": true], "ignore": true]],
             "complex_modifications": ["parameters": ["basic.to_if_alone_timeout_milliseconds": 700],
                                       "rules": [["description": "Unrelated rule", "manipulators": []]]]]
        ]]
        let data = try JSONSerialization.data(withJSONObject: original, options: [.sortedKeys])
        try data.write(to: config.fileURL)
        check(!config.eventsEnabled(for: pad), "An ignored pad is not ready")
        var settings = PadSettings.defaults()
        settings.vendorID = 4489
        settings.productID = 34882
        settings.snapEngine = .macos
        settings.controls["Rccw", default: ControlMapping()].source = .key(code: "4", mods: [])
        settings.controls["Rcw", default: ControlMapping()].source = .key(code: "6", mods: [])
        settings.controls["k10", default: ControlMapping()].source = .key(code: "a", mods: [])
        settings.controls["k12", default: ControlMapping()].source = .key(code: "i", mods: [])
        let result = KarabinerExport.build(settings)
        check(result.count == 4, "Preserve all four assignments")
        try config.write(rule: result.rule, enabling: pad)
        check(config.eventsEnabled(for: pad), "Enable the selected composite keyboard")
        check(config.isInstalled(), "Install shortcut rule")
        check(try! Data(contentsOf: config.backupURL) == data, "Keep original config backup")
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: config.fileURL)) as! [String: Any]
        let profiles = saved["profiles"] as! [[String: Any]]
        check(NSDictionary(dictionary: profiles[0]).isEqual(to: (original["profiles"] as! [[String: Any]])[0]), "Preserve other profiles")
        let entries = profiles[1]["devices"] as! [[String: Any]]
        check(entries.count == 2, "Update existing interface without duplication")
        check(entries[0]["manipulate_caps_lock_led"] as? Bool == false, "Preserve device-specific preferences")
        check(entries[1]["ignore"] as? Bool == true, "Do not enable other keyboards")
        let cm = profiles[1]["complex_modifications"] as! [String: Any]
        check((cm["rules"] as! [[String: Any]]).count == 2, "Preserve unrelated rule")
        check((cm["parameters"] as! [String: Int])["basic.to_if_alone_timeout_milliseconds"] == 700, "Preserve parameters")
        let beforeReapply = try Data(contentsOf: config.fileURL)
        try config.write(rule: result.rule, enabling: pad)
        check(try! Data(contentsOf: config.fileURL) == beforeReapply, "Reapplying does not duplicate rules or devices")
        try config.write(rule: nil)
        check(!config.isInstalled(), "Learning/off removes our rule")
        let off = try JSONSerialization.jsonObject(with: Data(contentsOf: config.fileURL)) as! [String: Any]
        let offProfiles = off["profiles"] as! [[String: Any]]
        let offRules = (offProfiles[1]["complex_modifications"] as! [String: Any])["rules"] as! [[String: Any]]
        check(offRules.count == 1 && offRules[0]["description"] as? String == "Unrelated rule", "Off preserves unrelated shortcuts")
        if CommandLine.arguments.count > 1 {
            let output = ["title": "Mini Keyboard regression", "rules": [result.rule]] as [String: Any]
            try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        let current = HIDDevices.snapshot()
        print("Regression checks passed. Connected candidates: \(current.keyboards.map { "\($0.name) [\($0.id)]" }); virtual keyboard ready: \(current.virtualKeyboardReady)")
    }
}
