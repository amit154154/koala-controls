import AppKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @State private var setupExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            Rectangle().fill(GroveTheme.line).frame(height: 1)
            HStack(alignment: .top, spacing: 26) {
                VStack(spacing: 14) {
                    PadView().frame(width: 300).padding(.leading, 4)
                    CornerControlsView()
                    Text("Hold either corner key, then tap its partner. Single keys run on release.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(GroveTheme.muted)
                    Spacer(minLength: 0)
                }.frame(width: 312)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if model.learnIndex != nil { LearnBar() }
                        if let action = GroveAction.from(model.settings.mapping(model.selection).action) {
                            GrovePreview(action: action)
                        } else if let id = model.settings.mapping(model.selection).action?.id, WindowArtwork.names[id] != nil {
                            WindowArtworkPreview(actionID: id)
                        }
                        if !model.accessibilityTrusted {
                            HStack {
                                Label("Allow Accessibility to bring your keys to life", systemImage: "hand.raised")
                                    .font(.callout).foregroundColor(GroveTheme.gold)
                                Spacer()
                                Button("Allow…") { model.requestAccessibility() }
                            }.padding(14).background(RoundedRectangle(cornerRadius: 10).fill(GroveTheme.panel))
                        }
                        InspectorView()
                        DisclosureGroup(isExpanded: $setupExpanded) { SetupView().padding(.top, 8) } label: {
                            Label("Keyboard & settings", systemImage: "slider.horizontal.3").font(.headline)
                        }.padding(16).background(RoundedRectangle(cornerRadius: 14).fill(GroveTheme.panel))
                    }.padding(.trailing, 6).padding(.bottom, 24)
                }
            }.padding(24)
            HStack(spacing: 8) {
                Image(systemName: model.actionFailed ? "exclamationmark.circle" : "leaf")
                    .foregroundColor(model.actionFailed ? GroveTheme.gold : GroveTheme.mint)
                Text(model.actionFeedback).font(.system(size: 12)).lineLimit(2)
                    .foregroundColor(model.actionFailed ? GroveTheme.gold : GroveTheme.muted)
                Spacer()
                Text("Koala grove").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundColor(GroveTheme.muted)
            }.padding(.horizontal, 24).padding(.vertical, 10).background(GroveTheme.panel)
        }
        .background(GroveTheme.background)
        .foregroundColor(GroveTheme.text)
        .tint(GroveTheme.mint)
        .preferredColorScheme(.dark)
        .frame(minWidth: 960, idealWidth: 1060, minHeight: 730, idealHeight: 800)
        .overlay(alignment: .bottom) { ToastView() }
    }
}

struct HeaderBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "leaf.fill").font(.system(size: 24)).foregroundColor(GroveTheme.mint)
                .frame(width: 44, height: 44).background(Circle().fill(GroveTheme.mint.opacity(0.09)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Mini Keyboard").font(.system(size: 27, weight: .bold, design: .rounded))
                Text("Your Koala workspace, one press away.").font(.callout).foregroundColor(GroveTheme.muted)
            }
            Spacer()
            Button("Koala TV") { try? TVMode.shared.show() }.controlSize(.large)
            Menu("More") { Button("Your adventure") { AdventureWindow.shared.show() } }.controlSize(.large)
            Button("Phone remote") { PhoneRemote.shared.showWindow() }.controlSize(.large)
            StatusPill(status: model.live)
            Button(model.learnIndex == nil ? "Learn keys" : "Stop learning") {
                if model.learnIndex == nil { model.learnStart() } else { model.learnStop() }
            }.controlSize(.large)
        }.padding(.horizontal, 24).padding(.vertical, 18)
    }
}

struct StatusPill: View {
    let status: LiveStatus
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.isGood ? Color.green : (status == .off ? Color.secondary : Color.orange))
                .frame(width: 8, height: 8)
            Text(status.text).font(.callout.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(GroveTheme.panel))
        .overlay(Capsule().strokeBorder(GroveTheme.line, lineWidth: 1))
        .frame(maxWidth: 320)
    }
}

struct LearnBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let i = model.learnIndex, i < Controls.order.count {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.learnInstruction).font(.system(size: 16, weight: .bold))
                    Spacer()
                    Text("\(i + 1) / \(Controls.order.count)").foregroundColor(.secondary).monospacedDigit()
                }
                Text("If nothing happens here but your Mac changed the volume or the music, click what happened:")
                    .font(.callout)
                    .foregroundColor(.secondary)
                HStack {
                    ForEach(["vol_down", "vol_up", "mute", "play"], id: \.self) { m in
                        Button(Media.byID[m]?.label ?? m) { model.learnPickMedia(m) }
                    }
                    Button("Skip") { model.learnSkip() }
                    Spacer()
                    Button("Stop") { model.learnStop() }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Pad.amber.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Pad.amber, lineWidth: 1))
        }
    }
}

struct SetupBlock<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.bottom, 6)
            Text(title).font(.headline)
            content
        }
        .padding(.top, 10)
    }
}

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var showManualIDs = false
    @State private var confirmReset = false

    private var deviceBinding: Binding<String> {
        Binding(get: { model.deviceTag }, set: { model.selectDevice($0) })
    }
    private var vendorText: Binding<String> {
        Binding(get: { model.settings.vendorID.map { String($0) } ?? "" }, set: { model.setVendorText($0) })
    }
    private var productText: Binding<String> {
        Binding(get: { model.settings.productID.map { String($0) } ?? "" }, set: { model.setProductText($0) })
    }
    private var loginBinding: Binding<Bool> {
        Binding(get: { model.openAtLogin }, set: { model.openAtLogin = $0 })
    }

    private var snapExplanation: String {
        switch model.settings.snapEngine {
        case .app: return "Mini Keyboard moves the windows itself. Nothing else to install."
        case .rectangle: return "Sends Rectangle’s default shortcuts (⌃⌥← and ⌃⌥→ for the halves). Rectangle has to be running."
        case .macos: return "Sends Apple’s tiling shortcuts (fn⌃← and fn⌃→). Some Macs ignore fn coming from Karabiner."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings").font(.system(size: 18, weight: .bold).width(.expanded))

            SetupBlock("Koala companion") { CompanionSettingsView() }

            SetupBlock("MacBook shortcuts") {
                Toggle("Enable Command + Option shortcuts", isOn: $model.settings.laptopShortcutsEnabled)
                Text("Hold ⌘⌥ for a moment to see your koala shortcut guide. Press 1–7, P minimize, [ left, ] fill, or \\ right. Works with the mini keyboard disconnected.")
                    .font(.callout).foregroundColor(.secondary)
                Text(model.laptopStatus).font(.caption).foregroundColor(GroveTheme.mint)
                Text("These replace Fold / Unfold (⌘⌥[ / ]) in VS Code and Zed, and auto-indent (⌘⌥\\) in Obsidian. ⌘⌥P also replaces Finder’s Show/Hide Path Bar. Turn this off to restore those shortcuts.")
                    .font(.caption).foregroundColor(.secondary)
            }

            SetupBlock("Shortcut mode") {
                Picker("", selection: $model.settings.shortcutEngine) {
                    ForEach(ShortcutEngine.allCases, id: \.self) { engine in Text(engine.title).tag(engine) }
                }.pickerStyle(.segmented).labelsHidden()
                if model.settings.shortcutEngine == .native {
                    Text("Uses macOS’s built-in remapping for the selected keyboard. Keep Mini Keyboard running. No Karabiner driver is needed.")
                        .font(.callout).foregroundColor(.secondary)
                    Text("Supports up to sixteen assigned controls that send plain keys or the knob’s mute input. Uses F4–F20 (excluding F11, F14 and F15) and keypad comma/equals as relay keys. The relay keys currently in use can trigger the same actions on another keyboard. Unassigned pad controls keep their original behavior.")
                        .font(.caption).foregroundColor(.secondary)
                    if let action = model.lastNativeAction {
                        Label("Last action: \(action)", systemImage: "keyboard").font(.callout)
                    }
                    if let error = model.nativeError { Text(error).font(.callout).foregroundColor(.orange) }
                    Label(model.inputMonitoringAllowed ? "Input Monitoring allowed" : "Needs Input Monitoring for the keypad",
                          systemImage: model.inputMonitoringAllowed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.callout).foregroundColor(model.inputMonitoringAllowed ? .green : .orange)
                    HStack {
                        Button("Apply shortcuts again") { model.applyNow() }
                        Button("Input Monitoring…") { model.requestInputMonitoring() }
                    }
                }
            }

            SetupBlock("Your mini keyboard") {
                HStack {
                    Picker("", selection: deviceBinding) {
                        Text("Choose…").tag("")
                        ForEach(model.devices) { d in
                            Text("\(d.name)  \(d.hexIDs)").tag(d.id)
                        }
                        if model.settings.vendorID != nil && !model.devices.contains(where: { $0.id == model.deviceTag }) {
                            Text("\(model.settings.deviceName ?? "Saved device") (not connected)").tag(model.deviceTag)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360)
                    Button("Refresh") { model.refreshDevices() }
                }
                if model.settings.vendorID == nil {
                    Text("Pick it so the shortcuts only apply to the mini keyboard, not your Mac’s own keyboard.")
                        .font(.callout)
                        .foregroundColor(.orange)
                }
                DisclosureGroup("Enter the IDs by hand", isExpanded: $showManualIDs) {
                    HStack {
                        TextField("vendor_id", text: vendorText).textFieldStyle(.roundedBorder).frame(width: 120)
                        TextField("product_id", text: productText).textFieldStyle(.roundedBorder).frame(width: 120)
                        Text("From Karabiner-EventViewer → Devices").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
                .font(.callout)
            }

            SetupBlock("Window snapping") {
                if model.settings.shortcutEngine == .karabiner {
                Picker("", selection: $model.settings.snapEngine) {
                    ForEach(SnapEngine.allCases, id: \.self) { e in Text(e.title).tag(e) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
                Text(snapExplanation).font(.callout).foregroundColor(.secondary)
                } else {
                    Text("Mini Keyboard moves windows directly and sends your tab shortcuts using Accessibility.")
                        .font(.callout).foregroundColor(.secondary)
                }
                if model.settings.shortcutEngine == .native || model.settings.snapEngine == .app {
                    if model.accessibilityTrusted {
                        Label("Accessibility allowed", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.callout)
                    } else {
                        HStack {
                            Label("Needs Accessibility for shortcuts and windows", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.callout)
                            Button("Allow…") { model.requestAccessibility() }
                        }
                    }
                }
            }

            if model.settings.shortcutEngine == .karabiner {
            SetupBlock("Karabiner-Elements") {
                if model.karabinerInstalled {
                    HStack {
                        Label("Installed", systemImage: "checkmark.circle.fill").foregroundColor(.green).font(.callout)
                        Button("Open Karabiner") { model.openKarabiner() }
                    }
                    if !model.karabinerDriverReady {
                        Label("The virtual keyboard driver is not running.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange).font(.callout)
                        Text("Open Karabiner → Setup and finish Driver Extension setup. Shortcuts cannot run until its virtual keyboard is available.")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Label("Virtual keyboard is available", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green).font(.callout)
                    }
                    Text("Applying shortcuts enables “Modify events” for your selected mini keyboard, including its composite keyboard interface.")
                        .font(.caption).foregroundColor(.secondary)
                    Button("Apply shortcuts again") { model.applyNow() }
                } else {
                    Text("Mini Keyboard uses this free app to catch keys from the mini keyboard only. Install it, open it once and allow what it asks for.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    if let url = URL(string: "https://karabiner-elements.pqrs.org/") {
                        Link("Download Karabiner-Elements", destination: url)
                    }
                }
            }
            }
                if !model.skipped.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.skipped, id: \.self) { s in
                            Text("Left out: \(s)").font(.caption).foregroundColor(.orange)
                        }
                    }
                }
            SetupBlock("General") {
                Toggle("Shortcuts on", isOn: $model.settings.enabled)
                Toggle("Open at login", isOn: loginBinding)
                Button("Start over with the default layout…") { confirmReset = true }
                    .confirmationDialog("Clear every shortcut you set?", isPresented: $confirmReset) {
                        Button("Start over", role: .destructive) { model.resetLayout() }
                    }
            }
        }
    }
}

struct ToastView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let t = model.toast {
            Text(t)
                .font(.callout.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.82)))
                .padding(.bottom, 18)
                .transition(.opacity)
        }
    }
}
