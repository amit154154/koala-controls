import AppKit
import SwiftUI

@main
enum MiniKeyboardMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let model = AppModel.shared
    private var window: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Karabiner runs `open -g minikeyboard://window/left` for window actions; this receives it.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildStatusItem()
        TVMode.shared.startDisplayWatching()
        let isDefaultLaunch = (notification.userInfo?["NSApplicationLaunchIsDefaultLaunchKey"] as? Bool) ?? true
        if isDefaultLaunch && !launchedAsLoginItem() && !TVMode.shared.shouldAutoStartOnLaunch {
            showWindow()
        }
        model.applyNow()
        PhoneRemote.shared.startIfEnabled()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if TVMode.shared.active {TVMode.shared.showControls()}else{showWindow()}
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        TVMode.shared.shutdown()
        model.shutdown()
    }

    private func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == AEEventID(kAEOpenApplication)
            && event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    // MARK: - URL events from Karabiner

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: text) else { return }
        handle(url)
    }

    private func handle(_ url: URL) {
        guard url.scheme == KarabinerExport.urlScheme else { return }
        switch url.host {
        case "window":
            if let action = WindowAction(rawValue: url.lastPathComponent) {
                if let def = Actions.all.first(where: { if case .window(let w) = $0.kind { return w == action }; return false }) {
                    NativeAction.perform(ActionRef(id:def.id),control:"URL relay",origin:.keyboardRelay)
                }
            }
        case "grove":
            if let action = GroveAction(rawValue: url.lastPathComponent) { NativeAction.perform(ActionRef(id:action.actionID),control:"URL relay",origin:.keyboardRelay) }
        case "tv":
            try? TVMode.shared.show()
        case "phone":
            PhoneRemote.shared.showWindow()
        case "open":
            showWindow()
        default:
            break
        }
    }

    // MARK: - Window

    @objc func showTV() { try? TVMode.shared.show() }

    @objc func showWindow() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1060, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "Mini Keyboard"
            w.contentView = NSHostingView(rootView: MainView().environmentObject(model))
            w.minSize = NSSize(width: 960, height: 730)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("MiniKeyboardMainWindow")
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        model.windowDidOpen()
    }

    func windowWillClose(_ notification: Notification) {
        model.learnStop()
        model.cancelDetect()
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Menus

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Mini Keyboard", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Mini Keyboard", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Mini Keyboard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Mini Keyboard")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: model.live.text, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let toggle = NSMenuItem(title: "Shortcuts on", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = model.settings.enabled ? .on : .off
        menu.addItem(toggle)

        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Mini Keyboard…", action: #selector(showWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let tv = NSMenuItem(title: "Open Koala TV…", action: #selector(showTV), keyEquivalent: ""); tv.target = self; menu.addItem(tv)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Mini Keyboard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    }

    @objc private func toggleEnabled() {
        model.settings.enabled.toggle()
    }
}
