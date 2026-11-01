import AppKit
@main struct KoalaTVLauncher {
    static func main() {
        let app=NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let host=URL(fileURLWithPath:"/Applications/Mini Keyboard.app")
        guard FileManager.default.fileExists(atPath:host.path) else { return }
        NSWorkspace.shared.open([URL(string:"minikeyboard://tv")!],withApplicationAt:host,configuration:NSWorkspace.OpenConfiguration()) { _,_ in DispatchQueue.main.async { app.terminate(nil) } }
        app.run()
    }
}
