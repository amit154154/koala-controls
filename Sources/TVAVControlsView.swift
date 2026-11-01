import SwiftUI

struct TVAVControlsView:View {
    @ObservedObject var audio=TVAudio.shared
    @ObservedObject var captions=TVLiveCaptions.shared
    var close:()->Void
    var body:some View {
        VStack(spacing:0){
            HStack(spacing:13){TVBrandMark(size:52);VStack(alignment:.leading,spacing:3){Text("Audio & Captions").font(.system(size:27,weight:.bold,design:.rounded));Text("Your evening, loud and clear.").font(.system(size:14)).foregroundColor(TVStyle.muted)};Spacer();Button(action:close){Image(systemName:"xmark").font(.system(size:17,weight:.semibold)).padding(5)}.buttonStyle(TVSoftButton()).accessibilityLabel("Close audio and captions")}.padding(24)
            ScrollView{
                VStack(alignment:.leading,spacing:23){captionControls;Divider().overlay(TVStyle.mint.opacity(0.15));audioControls}
                    .padding(.horizontal,26).padding(.bottom,26)
            }
        }.background(TVStyle.background).foregroundColor(TVStyle.text).tint(TVStyle.mint).preferredColorScheme(.dark)
    }
    private func set(_ key:String,_ value:String){audio.perform{try captions.configure([key:value])}}
    private var captionControls:some View {
        VStack(alignment:.leading,spacing:16){
            HStack{Label("Live captions",systemImage:"captions.bubble.fill").font(.system(size:21,weight:.bold,design:.rounded));Spacer();Toggle("Live captions",isOn:Binding(get:{captions.enabled},set:{if $0{captions.start()}else{captions.stop()}})).labelsHidden().toggleStyle(.switch).disabled(!captions.supported)}
            HStack(spacing:14){Image(systemName:"waveform").font(.system(size:27)).foregroundColor(TVStyle.mint);Text("A little koala. Every word in reach.").font(.system(size:21,weight:.semibold)).multilineTextAlignment(.center).frame(maxWidth:.infinity)}.padding(22).background(Color.black.opacity(0.32)).cornerRadius(15)
            HStack{Picker("Listen to",selection:Binding(get:{captions.source.rawValue},set:{set("source",$0)})){ForEach(TVCaptionSource.allCases,id:\.rawValue){Text($0.title).tag($0.rawValue)}};Spacer(minLength:18);Button("Preview on TV"){captions.preview()}.buttonStyle(TVSoftButton())}
            Text(captions.source.explanation).font(.system(size:13)).foregroundColor(TVStyle.muted).fixedSize(horizontal:false,vertical:true)
            HStack(spacing:20){Picker("Language",selection:Binding(get:{captions.language},set:{set("language",$0)})){ForEach(captions.locales,id:\.self){Text(Locale.current.localizedString(forIdentifier:$0) ?? $0).tag($0)}};Picker("Text",selection:Binding(get:{captions.size},set:{set("size",$0)})){Text("Small").tag("small");Text("Medium").tag("medium");Text("Large").tag("large")}.frame(width:190)}
            HStack(spacing:20){Picker("Position",selection:Binding(get:{captions.position},set:{set("position",$0)})){Text("Bottom").tag("bottom");Text("Top").tag("top")}.pickerStyle(.segmented);Picker("Style",selection:Binding(get:{captions.style},set:{set("style",$0)})){Text("Forest glass").tag("forest");Text("Black").tag("contrast")}.pickerStyle(.segmented)}
            HStack(spacing:10){
                if captions.preparing{ProgressView().controlSize(.small)}else{Image(systemName:captions.error ? "exclamationmark.circle":captions.enabled ? "waveform.circle.fill":"lock.shield").foregroundColor(captions.error ? TVStyle.gold:TVStyle.mint)}
                Text(captions.status).font(.system(size:13)).foregroundColor(captions.error ? TVStyle.gold:TVStyle.muted).fixedSize(horizontal:false,vertical:true)
                Spacer();if captions.enabled {Capsule().fill(TVStyle.mint.opacity(0.3)).frame(width:50,height:5).overlay(alignment:.leading){Capsule().fill(TVStyle.mint).frame(width:max(2,min(50,captions.level*500)),height:5)}}
            }
            if captions.preparing,captions.progress>0,captions.progress<1{ProgressView(value:captions.progress).tint(TVStyle.mint)}
            Text("Finished phrases appear together after a short buffer. Recognized on this Mac, with no microphone or saved transcript. Captions can make mistakes.").font(.system(size:12)).foregroundColor(TVStyle.muted)
        }.font(.system(size:14))
    }
    private var audioControls:some View {
        VStack(alignment:.leading,spacing:15){
            HStack{Label("Sound output",systemImage:"speaker.wave.2.fill").font(.system(size:21,weight:.bold,design:.rounded));Spacer();Button {audio.refresh(pairedDevices:true)}label:{Label("Refresh",systemImage:"arrow.clockwise")}.buttonStyle(TVSoftButton()).disabled(audio.connecting)}
            VStack(spacing:0){ForEach(audio.outputs){output in
                Button{audio.perform{try audio.choose(output.id)}}label:{HStack(spacing:12){Image(systemName:output.bluetooth ? "airpodspro":"speaker.wave.2").font(.system(size:19)).frame(width:27);Text(output.name).font(.system(size:15,weight:.medium));Spacer();if output.id==audio.selected{Image(systemName:"checkmark.circle.fill").foregroundColor(TVStyle.mint)}}.padding(.vertical,13).padding(.horizontal,15).contentShape(Rectangle())}.buttonStyle(.plain)
                if output.id != audio.outputs.last?.id{Divider().padding(.leading,54).opacity(0.4)}
            }}.background(TVStyle.panel.opacity(0.5)).cornerRadius(13)
            HStack(spacing:15){Button{audio.perform{try audio.setMuted(!audio.muted)}}label:{Image(systemName:audio.muted ? "speaker.slash.fill":"speaker.wave.2.fill").font(.system(size:20)).frame(width:26)}.buttonStyle(TVSoftButton()).disabled(!audio.canMute).accessibilityLabel(audio.muted ? "Unmute":"Mute");Slider(value:Binding(get:{audio.volume},set:{value in audio.perform{try audio.setVolume(value)}}),in:0...1).disabled(!audio.canVolume).accessibilityLabel("Output volume");Text(audio.canVolume ? "\(Int(audio.volume*100))%":"—").font(.system(size:15,weight:.semibold)).monospacedDigit().frame(width:46)}
            if !audio.canVolume{Text("This output uses its own volume controls. Use the TV or speaker remote.").font(.system(size:13)).foregroundColor(TVStyle.gold)}
            HStack{Text("Your AirPods & headphones").font(.system(size:17,weight:.semibold,design:.rounded));Spacer();Button("Bluetooth settings"){audio.settings()}.buttonStyle(.plain).foregroundColor(TVStyle.mint)}.padding(.top,2)
            if audio.headphones.isEmpty{Text("Pair AirPods with this Mac in Bluetooth settings, then refresh. Open the case or wear them to connect.").font(.system(size:13)).foregroundColor(TVStyle.muted)}
            ForEach(audio.headphones){headphones in HStack(spacing:12){Image(systemName:"airpodspro").font(.system(size:23)).foregroundColor(TVStyle.mint);VStack(alignment:.leading,spacing:3){Text(headphones.name).font(.system(size:15,weight:.semibold));Text(headphones.connected ? "Bluetooth connected":"Paired with this Mac").font(.system(size:12)).foregroundColor(TVStyle.muted)};Spacer();Button(audio.connecting ? "Connecting…":"Use for sound"){Task{@MainActor in do{try await audio.connect(headphones.id)}catch{audio.error=true;audio.message=error.localizedDescription}}}.buttonStyle(TVSoftButton()).disabled(audio.connecting)}.padding(.vertical,5)}
            Text(audio.message).font(.system(size:13)).foregroundColor(audio.error ? TVStyle.gold:TVStyle.muted).fixedSize(horizontal:false,vertical:true)
        }
    }
}

struct TVAVButtons:View {
    let tv:TVMode
    @ObservedObject var captions=TVLiveCaptions.shared
    var body:some View {HStack(spacing:10){
        Button{captions.toggle()}label:{Image(systemName:captions.enabled ? "captions.bubble.fill":"captions.bubble").font(.system(size:22)).foregroundColor(captions.enabled ? TVStyle.mint:TVStyle.text)}.help(captions.enabled ? "Turn off live captions":"Turn on live captions").accessibilityLabel(captions.enabled ? "Turn off live captions":"Turn on live captions")
        Button{tv.showAVControls()}label:{Image(systemName:"speaker.wave.2").font(.system(size:22))}.help("Audio & Captions").accessibilityLabel("Audio and captions")
    }.buttonStyle(.plain)}
}
