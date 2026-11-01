import SwiftUI

struct CompanionSettingsView: View {
  @EnvironmentObject var model: AppModel
  @State private var previewStyle = CompanionStyle.basketball
  @State private var previewRare = false
  @State private var shot = BasketballShot.swish

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        GroveArtwork(name: "companion").frame(width: 60, height: 60)
        VStack(alignment: .leading, spacing: 4) {
          Text("A little adventure with every shortcut").font(.callout.weight(.semibold))
          Text("Hoops, portals, mob battles and tiny celebrations beside your pointer.")
            .font(.caption).foregroundColor(.secondary)
        }
      }
      Toggle("Play MapleStory sounds", isOn: $model.settings.companion.sound)
      Text("Movement shuffles eight chosen sounds. 001 and 011 are reserved for shortcut and player level-ups.")
        .font(.caption).foregroundColor(.secondary)
      HStack {
        Text("Sound volume").font(.callout)
        Slider(value: $model.settings.companion.volume, in: 0...1).accessibilityLabel(
          "Companion sound volume")
        Text("\(Int(model.settings.companion.volume * 100))%")
          .font(.caption).monospacedDigit().frame(width: 36)
      }.disabled(!model.settings.companion.sound)
      Toggle("Show the koala animation", isOn: $model.settings.companion.animationEnabled)
      Toggle("Occasional rare reactions", isOn: $model.settings.companion.rareAnimations)
      Text(
        "Rare reactions leave a few normal ones between surprises. Basketball sometimes misses, too."
      )
      .font(.caption).foregroundColor(.secondary)
      Picker("Battle opponent", selection: $model.settings.companion.opponent) {
        Text("Shuffle all nine mobs").tag("random")
        ForEach(CompanionMob.allCases, id: \.self) { mob in Text(mob.title).tag(mob.rawValue) }
      }
      Text("Button 6 fights this opponent. Shuffle meets every mob before repeating.")
        .font(.caption).foregroundColor(.secondary)
      Divider()
      Text("Try the animations").font(.callout.weight(.semibold))
      Picker("Shortcut", selection: $previewStyle) {
        ForEach(CompanionStyle.allCases.filter { $0 != .hop }, id: \.self) { style in
          Text(style.title).tag(style)
        }
      }
      if previewStyle == .basketball {
        Picker("Shot", selection: $shot) {
          Text("Swish").tag(BasketballShot.swish)
          Text("Miss").tag(BasketballShot.miss)
          Text("Rare dunk").tag(BasketballShot.dunk)
        }.pickerStyle(.segmented)
      } else {
        Toggle("Preview the rare version", isOn: $previewRare)
      }
      HStack {
        Button("Play animation") {
          let rare = previewStyle == .basketball ? shot == .dunk : previewRare
          let opponent =
            CompanionMob(rawValue: model.settings.companion.opponent) ?? CompanionMob.allCases
            .randomElement()!
          ShortcutFeedback.shared.play(previewStyle, rare: rare, mob: opponent, shot: shot)
        }
        .disabled(!model.settings.companion.animationEnabled && !model.settings.companion.sound)
        Text("Just the reaction; your windows stay put.").font(.caption).foregroundColor(.secondary)
      }
      Text(
        "Knob turns stay quiet. Window snaps stay under half a second. Reduce Motion uses a gentle fade."
      )
      .font(.caption).foregroundColor(.secondary)
    }
  }
}
