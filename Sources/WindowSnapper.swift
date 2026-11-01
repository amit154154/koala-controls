import AppKit
import ApplicationServices

/// Moves and resizes the frontmost app's focused window, like Rectangle or BetterTouchTool do.
final class WindowSnapper {
    static let shared = WindowSnapper()

    private var previousFrames: [(window: AXUIElement, frame: CGRect)] = []
    private var lastPrompt = Date.distantPast

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func askForAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult func perform(_ action: WindowAction) -> Bool {
        guard AXIsProcessTrusted() else {
            if Date().timeIntervalSince(lastPrompt) > 10 {
                lastPrompt = Date()
                WindowSnapper.askForAccess()
            }
            return false
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = element(axApp, kAXFocusedWindowAttribute) ?? element(axApp, kAXMainWindowAttribute),
              let current = frame(of: window) else {
            NSSound.beep()
            return false
        }

        if action == .restore {
            if let i = previousFrames.lastIndex(where: { CFEqual($0.window, window) }) {
                let saved = previousFrames[i].frame
                previousFrames.remove(at: i)
                setFrame(window, saved)
                return true
            } else {
                NSSound.beep()
            }
            return false
        }

        let cocoaCurrent = flip(current)
        guard let screen = screen(containing: cocoaCurrent) else { return false }
        let vf = screen.visibleFrame
        var target: CGRect

        switch action {
        case .left: target = CGRect(x: vf.minX, y: vf.minY, width: vf.width / 2, height: vf.height)
        case .right: target = CGRect(x: vf.midX, y: vf.minY, width: vf.width / 2, height: vf.height)
        case .top: target = CGRect(x: vf.minX, y: vf.midY, width: vf.width, height: vf.height / 2)
        case .bottom: target = CGRect(x: vf.minX, y: vf.minY, width: vf.width, height: vf.height / 2)
        case .topLeft: target = CGRect(x: vf.minX, y: vf.midY, width: vf.width / 2, height: vf.height / 2)
        case .topRight: target = CGRect(x: vf.midX, y: vf.midY, width: vf.width / 2, height: vf.height / 2)
        case .bottomLeft: target = CGRect(x: vf.minX, y: vf.minY, width: vf.width / 2, height: vf.height / 2)
        case .bottomRight: target = CGRect(x: vf.midX, y: vf.minY, width: vf.width / 2, height: vf.height / 2)
        case .leftThird: target = CGRect(x: vf.minX, y: vf.minY, width: vf.width / 3, height: vf.height)
        case .centerThird: target = CGRect(x: vf.minX + vf.width / 3, y: vf.minY, width: vf.width / 3, height: vf.height)
        case .rightThird: target = CGRect(x: vf.minX + vf.width * 2 / 3, y: vf.minY, width: vf.width / 3, height: vf.height)
        case .leftTwoThirds: target = CGRect(x: vf.minX, y: vf.minY, width: vf.width * 2 / 3, height: vf.height)
        case .rightTwoThirds: target = CGRect(x: vf.minX + vf.width / 3, y: vf.minY, width: vf.width * 2 / 3, height: vf.height)
        case .maximize: target = vf
        case .almostMaximize: target = vf.insetBy(dx: vf.width * 0.05, dy: vf.height * 0.05)
        case .center:
            let w = min(cocoaCurrent.width, vf.width), h = min(cocoaCurrent.height, vf.height)
            target = CGRect(x: vf.midX - w / 2, y: vf.midY - h / 2, width: w, height: h)
        case .nextDisplay, .previousDisplay:
            let screens = NSScreen.screens.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
            guard screens.count > 1, let idx = screens.firstIndex(where: { $0 == screen }) else { NSSound.beep(); return false }
            let next = screens[(idx + (action == .nextDisplay ? 1 : screens.count - 1)) % screens.count].visibleFrame
            let rx = (cocoaCurrent.minX - vf.minX) / vf.width, ry = (cocoaCurrent.minY - vf.minY) / vf.height
            let w = min(cocoaCurrent.width / vf.width * next.width, next.width)
            let h = min(cocoaCurrent.height / vf.height * next.height, next.height)
            target = CGRect(x: next.minX + rx * next.width, y: next.minY + ry * next.height, width: w, height: h)
        case .restore:
            return false
        }

        remember(window, current)
        setFrame(window, flip(target.integral))
        return true
    }

    // MARK: - Accessibility helpers

    func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    func frame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let p = posRef, let s = sizeRef,
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    /// Size, then position, then size again, so windows moving between displays end up right.
    func setFrame(_ window: AXUIElement, _ rect: CGRect) {
        var size = rect.size
        var origin = rect.origin
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s) }
        if let p = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p) }
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s) }
    }

    private func remember(_ window: AXUIElement, _ frame: CGRect) {
        // Keep the size from before the first snap, so Restore goes back to the original.
        if previousFrames.contains(where: { CFEqual($0.window, window) }) { return }
        previousFrames.append((window, frame))
        if previousFrames.count > 40 { previousFrames.removeFirst(previousFrames.count - 40) }
    }

    // MARK: - Coordinates
    // Accessibility uses a top-left origin on the main display; AppKit uses bottom-left. The flip is its own inverse.

    func flip(_ r: CGRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    func screen(containing r: CGRect) -> NSScreen? {
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for s in NSScreen.screens {
            let i = s.frame.intersection(r)
            let area = i.isNull ? 0 : i.width * i.height
            if area > bestArea { bestArea = area; best = s }
        }
        return best ?? NSScreen.main
    }
}
