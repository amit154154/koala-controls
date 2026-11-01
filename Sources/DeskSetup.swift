import AppKit
import ApplicationServices

struct DeskPlan {
    enum Layout: Equatable {
        case notesChat, code, build, obsidian
        var apps: [(id: String, name: String)] {
            switch self {
            case .notesChat: return GroveAction.write.apps
            case .code: return GroveAction.code.apps
            case .build: return GroveAction.build.apps
            case .obsidian: return [("md.obsidian", "Obsidian")]
            }
        }
    }
    struct Step: Equatable { let displayID: CGDirectDisplayID; let layout: Layout }
    let steps: [Step]
    let mediaDisplayID: CGDirectDisplayID?

    static func build(_ displays: [MediaDisplay]) -> DeskPlan {
        let ipad = displays.first(where: \.isIPad)
        let builtIn = displays.first(where: \.builtIn)
        let external = displays.filter { !$0.builtIn && !$0.isIPad }.sorted {
            if $0.frame.midX != $1.frame.midX { return $0.frame.midX < $1.frame.midX }
            if $0.frame.midY != $1.frame.midY { return $0.frame.midY > $1.frame.midY }
            return $0.id < $1.id
        }
        var steps: [Step] = []
        if let builtIn = builtIn {
            steps.append(Step(displayID: builtIn.id, layout: external.isEmpty ? .obsidian : .notesChat))
        }
        if let middle = external.first { steps.append(Step(displayID: middle.id, layout: .code)) }
        if external.count >= 2 { steps.append(Step(displayID: external[1].id, layout: .build)) }
        return DeskPlan(steps: steps, mediaDisplayID: ipad?.id)
    }
}

enum DeskSetup {
    /// Captured display IDs are revalidated throughout; a disappearing monitor never
    /// redirects a later layout onto the MacBook or iPad.
    @MainActor static func run(_ plan: DeskPlan, actions: GroveActions) async -> [String] {
        guard AXIsProcessTrusted() else { return ["Allow Accessibility for Mini Keyboard to arrange your desk."] }
        guard !plan.steps.isEmpty else { return ["No work display is available."] }
        var errors: [String] = []
        var preferred: (NSRunningApplication, AXUIElement)?
        for step in plan.steps {
            do {
                guard NSScreen.screens.contains(where: { MediaScreens.id($0) == step.displayID }) else {
                    throw GroveError.message("A work display disconnected; press key 7 again after reconnecting it.")
                }
                var windows: [(NSRunningApplication, AXUIElement)] = []
                for spec in step.layout.apps {
                    let app = try await actions.launch(spec.id, name: spec.name)
                    let window = try await actions.window(for: app, name: spec.name)
                    windows.append((app, window))
                }
                for (index, pair) in windows.enumerated() {
                    guard let screen = NSScreen.screens.first(where: { MediaScreens.id($0) == step.displayID }) else {
                        throw GroveError.message("A work display disconnected; press key 7 again after reconnecting it.")
                    }
                    let frames = GrovePlan.frames(in: screen.visibleFrame, count: windows.count)
                    try await actions.place(pair.1, app: pair.0, name: step.layout.apps[index].name, frame: frames[index])
                }
                if preferred == nil || step.layout == .code { preferred = windows.first }
            } catch { errors.append(error.localizedDescription) }
        }
        if let preferred = preferred {
            preferred.0.activate(options: [.activateIgnoringOtherApps])
            _ = AXUIElementPerformAction(preferred.1, kAXRaiseAction as CFString)
        }
        return errors
    }
}
