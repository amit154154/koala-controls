import AppKit

@main enum ReconnectMediaRegression {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }
    static func main() throws {
        let settingsData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let settings = try JSONDecoder().decode(PadSettings.self, from: settingsData)
        let plan = NativePlan.build(settings)
        check(plan.bindings.count == 16 && plan.skipped.isEmpty, "All saved pad assignments remain usable")
        check(LaptopPlan.build(settings).count == 11, "Laptop shortcuts remain available independently")
        let before = try JSONSerialization.jsonObject(with: settingsData) as! NSDictionary
        let after = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! NSDictionary
        check(before["controls"] as! NSDictionary == after["controls"] as! NSDictionary, "Learned keys and assignments survive")

        let epoch = Date(timeIntervalSince1970: 0)
        var retry = NativeReconnectPolicy()
        func ready(_ now: Double, enabled: Bool = true, connected: Bool = true, allowed: Bool = true,
                   paused: Bool = false, active: Int = 0, bindings: Int = 16) -> Bool {
            retry.shouldRetry(enabled: enabled, connected: connected, allowed: allowed, paused: paused,
                activeCount: active, bindingCount: bindings, now: epoch.addingTimeInterval(now))
        }
        check(ready(0), "A failed start with no stored device IDs can recover")
        retry.finished(success: false, now: epoch)
        check(!ready(2) && ready(2.5), "Wait for the HID event service to appear after device discovery")
        retry.finished(success: false, now: epoch.addingTimeInterval(2.5))
        check(!ready(7) && ready(7.5), "Repeated failure backs off")
        for _ in 0..<8 { retry.finished(success: false, now: epoch.addingTimeInterval(10)) }
        check(!ready(24.9) && ready(25), "Retry delay caps at fifteen seconds, never abandons reconnection")
        retry.finished(success: true, now: epoch.addingTimeInterval(26))
        check(ready(26), "A later disconnect can recover immediately after success")
        check(!ready(30,enabled:false) && !ready(30,connected:false) && !ready(30,allowed:false)
              && !ready(30,paused:true) && !ready(30,active:16) && !ready(30,bindings:0), "Do not interrupt disabled, learning, disconnected, unpermitted or healthy configurations")

        let installed: [[String: UInt64]] = [["source":1,"destination":101],["source":2,"destination":102]]
        let original: [[String: UInt64]] = [["source":1,"destination":9],["source":3,"destination":303]]
        let current = installed + [["source":3,"destination":333]]
        let restored = NativeShortcuts.restoring(current:current,original:original,installed:installed)
        check(restored == [["source":3,"destination":333],["source":1,"destination":9]], "Restore only this app's mappings and preserve independent edits")
        check(NativeShortcuts.restoring(current:[],original:original,installed:installed).isEmpty, "An already reset mapping needs no restoration write")

        for screen in [CGRect(x:0,y:0,width:1102,height:718), CGRect(x:-1103,y:-513,width:1103,height:719), CGRect(x:2200,y:50,width:742,height:1102)] {
            check(MediaTilingPlan.frames(in:screen,count:0).isEmpty, "No empty layout windows")
            check(MediaTilingPlan.frames(in:screen,count:1) == [screen], "First media fills the iPad")
            for count in 2...7 {
                let frames = MediaTilingPlan.frames(in:screen,count:count)
                check(frames.count == count, "Every media service gets a tile")
                check(frames.allSatisfy { screen.contains($0) && $0.width > 0 && $0.height > 0 }, "All tiles stay inside the actual iPad coordinates")
                for i in frames.indices {
                    for j in frames.indices where j > i {
                        let overlap = frames[i].intersection(frames[j])
                        check(overlap.isNull || overlap.width * overlap.height == 0, "No overlapping media tiles")
                    }
                }
                check(abs(frames.reduce(0) { $0 + $1.width * $1.height } - screen.width * screen.height) < 1, "Use the entire screen, including an odd final row")
                check(MediaTilingPlan.belongs(frames[0],to:screen), "Find media already on the iPad after restart")
            }
            let halves = MediaTilingPlan.frames(in:screen,count:2)
            check(halves[0].minX == screen.minX && halves[1].maxX == screen.maxX && halves[0].height == screen.height, "Two media windows sit side by side")
        }
        check(!MediaTilingPlan.belongs(CGRect(x:0,y:0,width:200,height:200),to:CGRect(x:500,y:0,width:1000,height:700)), "Leave media on other screens alone")
        print("PASS: reconnect retries/backoff, reset mapping restoration, preserved 16 pad/11 laptop assignments, 1–7 media layout coverage, no overlaps, negative coordinates, media display membership.")
    }
}
