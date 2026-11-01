import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LabeledRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(width: 84, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
    }
}

struct SourceChips: View {
    let source: Source?
    var body: some View {
        if let s = source {
            switch s {
            case .media(let id):
                Chip(text: Media.byID[id]?.label ?? id)
            case .key(let code, let mods):
                HStack(spacing: 4) {
                    ForEach(Mods.sorted(mods), id: \.self) { m in
                        Chip(text: Mods.glyph[m] ?? m).help(Mods.name[m] ?? m)
                    }
                    Chip(text: Keys.short(code))
                }
            }
        } else {
            Text("Not learned yet").italic().foregroundColor(.secondary)
        }
    }
}

struct InspectorView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let sel = model.selection
        VStack(alignment: .leading, spacing: 0) {
            if sel == "L" || sel == "R" {
                Text(sel == "L" ? "Left knob" : "Right knob")
                    .font(.system(size: 22, weight: .bold).width(.expanded))
                Text("Each turn direction and the press can do something different.")
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                ForEach(0..<Controls.knobParts.count, id: \.self) { i in
                    Divider().padding(.vertical, 14)
                    ControlRowView(id: sel + Controls.knobParts[i].suffix, title: Controls.knobParts[i].title)
                }
            } else {
                let info = Controls.info(sel)
                Text(Controls.capitalized(info.name))
                    .font(.system(size: 22, weight: .bold).width(.expanded))
                Text("Key \(info.keyNumber ?? 0) of 12.")
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                Divider().padding(.vertical, 14)
                ControlRowView(id: sel, title: "Press")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(GroveTheme.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(GroveTheme.line, lineWidth: 1))
    }
}

struct ControlRowView: View {
    @EnvironmentObject var model: AppModel
    let id: String
    let title: String

    private var statusColor: Color {
        let st = model.settings.status(id, clashes: model.clashes)
        if st == .ready { return .green }
        return st.isProblem ? .orange : .secondary
    }

    var body: some View {
        let m = model.settings.mapping(id)
        let status = model.settings.status(id, clashes: model.clashes)
        let listening = model.detect == DetectTarget(id: id, purpose: .source)
        let isKnobTurn = Controls.info(id).knob != nil && !id.hasSuffix("press")

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(status.text).font(.callout).foregroundColor(statusColor).multilineTextAlignment(.trailing)
            }

            LabeledRow("It sends") {
                HStack(spacing: 8) {
                    if listening {
                        Text(isKnobTurn ? "Turn it one click now…" : "Press it now…")
                            .fontWeight(.semibold)
                            .foregroundColor(Pad.amber)
                    } else {
                        SourceChips(source: m.source)
                    }
                    Button(listening ? "Cancel" : "Detect") { model.toggleDetect(id) }
                    Menu("Pick from a list") {
                        Section("Media keys (knobs often send these)") {
                            ForEach(Media.all, id: \.id) { media in
                                Button(media.label) { model.pickMedia(id, media.id) }
                            }
                        }
                        Divider()
                        Button("Choose a key by hand…") { model.openManual(id) }
                        Button("Forget it") { model.setSource(id, nil); model.closeManual(id) }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            if listening {
                LabeledRow("") {
                    Text("Nothing showing up? It probably changes the volume or media. Pick that from the list instead.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if model.manualSource.contains(id) {
                LabeledRow("") { ShortcutBuilder(scope: .source, id: id) }
            }

            LabeledRow("Make it do") { ActionPicker(id: id) }

            ActionParams(id: id)
        }
    }
}

struct ActionPicker: View {
    @EnvironmentObject var model: AppModel
    let id: String

    var body: some View {
        let engine = model.settings.snapEngine
        Picker("", selection: Binding(get: { model.settings.mapping(id).action?.id ?? "" },
                                      set: { model.setAction(id, $0) })) {
            Text("Nothing new (leave as is)").tag("")
            ForEach(Actions.groups, id: \.self) { group in
                Section(group) {
                    ForEach(Actions.inGroup(group), id: \.id) { a in
                        Text(ActionPicker.label(a, engine)).tag(a.id)
                    }
                }
            }
        }
        .labelsHidden()
        .frame(maxWidth: 320)
    }

    static func label(_ a: ActionDef, _ engine: SnapEngine) -> String {
        if case .window(let w) = a.kind, !Actions.engineSupports(w, engine) {
            return a.label + " (not with \(engine.title))"
        }
        return a.label
    }
}

struct ActionParams: View {
    @EnvironmentObject var model: AppModel
    let id: String

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { model.param(id, key) }, set: { model.setParam(id, key, $0) })
    }

    var body: some View {
        if let ref = model.settings.mapping(id).action, let def = Actions.byID[ref.id] {
            switch def.kind {
            case .customShortcut:
                LabeledRow("") {
                    VStack(alignment: .leading, spacing: 6) {
                        ShortcutBuilder(scope: .action, id: id)
                        Text("Press Record, then press the shortcut on your Mac’s keyboard.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            case .openApp:
                LabeledRow("") {
                    HStack {
                        TextField("App name, like Slack", text: binding("name"))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                        Button("Choose…") { chooseApp() }
                    }
                }
            case .openURL:
                LabeledRow("") {
                    TextField("https://… or ~/Documents/file.pdf", text: binding("url"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }
            case .shell:
                LabeledRow("") {
                    TextField("A Terminal command, like: say hello", text: binding("cmd"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 320)
                }
            case .window(let w):
                if !Actions.engineSupports(w, model.settings.snapEngine) {
                    LabeledRow("") {
                        Text("Not available with \(model.settings.snapEngine.title) snapping. Choose “This app” under Window snapping.")
                            .font(.callout)
                            .foregroundColor(.orange)
                    }
                }
            default:
                EmptyView()
            }
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            model.setParam(id, "name", url.deletingPathExtension().lastPathComponent)
        }
    }
}

struct ShortcutBuilder: View {
    @EnvironmentObject var model: AppModel
    let scope: BuilderScope
    let id: String

    var body: some View {
        let mods = model.builderMods(id, scope)
        let code = model.builderCode(id, scope)
        let modList = scope == .action ? ["ctrl", "opt", "shift", "cmd", "fn"] : ["ctrl", "opt", "shift", "cmd"]
        let recording = model.detect == DetectTarget(id: id, purpose: .action)

        HStack(spacing: 6) {
            ForEach(modList, id: \.self) { m in
                Toggle(isOn: Binding(get: { mods.contains(m) }, set: { _ in model.toggleBuilderMod(id, scope, m) })) {
                    Text(Mods.glyph[m] ?? m).frame(minWidth: 16)
                }
                .toggleStyle(.button)
                .help(Mods.name[m] ?? m)
            }
            Picker("", selection: Binding(get: { code }, set: { model.setBuilderKey(id, scope, $0) })) {
                Text("Choose a key").tag("")
                ForEach(0..<Keys.groups.count, id: \.self) { gi in
                    Section(Keys.groups[gi].title) {
                        ForEach(Keys.groups[gi].codes, id: \.self) { c in
                            Text(Keys.long(c)).tag(c)
                        }
                    }
                }
            }
            .labelsHidden()
            .frame(width: 170)
            if scope == .action {
                Button(recording ? "Press it now… (cancel)" : "Record") { model.toggleRecord(id) }
            } else {
                Button("Done") { model.closeManual(id) }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
}
