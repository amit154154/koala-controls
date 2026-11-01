import AppKit
import SwiftUI
import Speech
import AVFoundation

/// The visible rolling caption is bounded and never written to disk or the shortcut journal.
struct TVCaptionText {
    private var segments:[(Double,String)]=[]
    mutating func insert(start:Double,text:String)->String {
        guard start.isFinite else{return ""}
        let clean=text.replacingOccurrences(of:"\n",with:" ").trimmingCharacters(in:.whitespacesAndNewlines)
        segments.removeAll{$0.0 >= start-0.005 || $0.0 < start-14}
        if !clean.isEmpty {segments.append((start,String(clean.suffix(600))))}
        segments=Array(segments.suffix(12))
        return Self.visible(segments.map{$0.1}.joined(separator:" "))
    }
    static func visible(_ text:String)->String {let words=text.split(whereSeparator:{$0.isWhitespace});var result="";for word in words.reversed(){let next=String(word)+(result.isEmpty ? "":" "+result);if next.count>150 && !result.isEmpty{break};result=next};return String(result.suffix(180))}
    mutating func clear(){segments=[]}
}

@MainActor final class TVLiveCaptions:ObservableObject {
    static let shared=TVLiveCaptions()
    @Published private(set) var enabled=false
    @Published private(set) var preparing=false
    @Published private(set) var text=""
    @Published private(set) var status="Turn on captions for live, on-device speech to text."
    @Published private(set) var error=false
    @Published private(set) var level:Double=0
    @Published var source=TVCaptionSource(rawValue:UserDefaults.standard.string(forKey:"tvCaptionSource") ?? "chrome") ?? .chrome
    @Published var language=UserDefaults.standard.string(forKey:"tvCaptionLanguage") ?? "en-US"
    @Published var size=UserDefaults.standard.string(forKey:"tvCaptionSize") ?? "medium"
    @Published var position=UserDefaults.standard.string(forKey:"tvCaptionPosition") ?? "bottom"
    @Published var style=UserDefaults.standard.string(forKey:"tvCaptionStyle") ?? "forest"
    @Published private(set) var locales:[String]=["en-US"]
    @Published private(set) var progress:Double=0
    private var engine:(any TVCaptionEngine)?
    private var task:Task<Void,Never>?
    private var panel:NSPanel?
    private var timer:Timer?
    private var token=UUID()
    private var composer=TVCaptionCues()
    private var cues:[TVCaptionCue]=[]
    private var cueUntil=Date.distantPast
    private var lastText=Date.distantPast,lastSound=Date.distantPast,started=Date.distantPast
    private var previewUntil=Date.distantPast
    private var shownCues=0,skippedCues=0
    private var captureBegan=0.0,captionDelay=0.0,firstWordDelay=0.0
    private var resultCount=0,lastDiagnostic=Date.distantPast
    private var observer:NSObjectProtocol?
    var supported:Bool {if #available(macOS 26.0,*){return SpeechTranscriber.isAvailable};return false}
    init(){observer=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main){[weak self]_ in Task{@MainActor in self?.stop(reason:"Captions stopped while the Mac sleeps.")}}}
    func loadLocales(){if #available(macOS 26.0,*){Task{@MainActor in let all=await SpeechTranscriber.supportedLocales;locales=all.map(\.identifier).sorted();if !locales.contains(language),let en=await SpeechTranscriber.supportedLocale(equivalentTo:Locale(identifier:language)){language=en.identifier}}}}
    func configure(_ o:[String:Any]) throws {
        let wasEnabled=enabled
        if let raw=o["source"] as? String {guard let value=TVCaptionSource(rawValue:raw) else{throw RemoteFailure.message("Unknown caption source.")};source=value}
        if let v=o["language"] as? String {guard locales.contains(v) || v=="en-US" else{throw RemoteFailure.message("Choose a supported caption language.")};language=v}
        if let v=o["size"] as? String {guard ["small","medium","large"].contains(v) else{throw RemoteFailure.message("Unknown caption size.")};size=v}
        if let v=o["position"] as? String {guard ["top","bottom"].contains(v) else{throw RemoteFailure.message("Unknown caption position.")};position=v}
        if let v=o["style"] as? String {guard ["forest","contrast"].contains(v) else{throw RemoteFailure.message("Unknown caption style.")};style=v}
        let d=UserDefaults.standard;d.set(source.rawValue,forKey:"tvCaptionSource");d.set(language,forKey:"tvCaptionLanguage");d.set(size,forKey:"tvCaptionSize");d.set(position,forKey:"tvCaptionPosition");d.set(style,forKey:"tvCaptionStyle")
        if wasEnabled,(o["source"] != nil || o["language"] != nil){start()};updateOverlay()
    }
    func toggle(){enabled ? stop():start()}
    func start(){
        stop(reason:"")
        guard supported else{status="Live captions need macOS 26 or later on a supported Mac.";error=true;return}
        guard TVMode.shared.active else{status="Start a TV session first, then turn on captions.";error=true;return}
        resultCount=0;shownCues=0;skippedCues=0;captionDelay=0;firstWordDelay=0;captureBegan=0;enabled=true;preparing=true;error=false;status="Preparing on-device captions…";started=Date();lastText = .distantPast;lastSound = .distantPast;let generation=token
        startTimer()
        if #available(macOS 26.0,*) {
            let e=TVSpeechCaptionEngine();engine=e
            task=Task{@MainActor [weak self] in
                guard let self=self else{return}
                do {
                    try await e.start(locale:language,source:source,onProgress:{[weak self] message,p in guard let self=self,self.token==generation else{return};self.status=message;self.progress=p},onText:{[weak self] words in
                        guard let self=self,self.token==generation,self.enabled else{return}
                        self.resultCount += 1;self.lastText=Date();self.lastSound=Date();self.status="Live captions · finished phrases"
                        self.enqueue(self.composer.submit(words,now:Date().timeIntervalSinceReferenceDate))
                    },onLevel:{[weak self] value in guard let self=self,self.token==generation else{return};self.level=value;if value>0.0015{self.lastSound=Date()}
                    },onError:{[weak self] message in guard let self=self,self.token==generation else{return};self.fail(message)})
                    guard token==generation,enabled else{await e.stop();return}
                    preparing=false;status="Listening to "+source.title+"…";started=Date();captureBegan=ProcessInfo.processInfo.systemUptime
                }catch{if token==generation,enabled{fail(error.localizedDescription)}}
            }
        }
    }
    func stop(reason:String="Captions off."){
        token=UUID();task?.cancel();task=nil
        let old=engine;engine=nil;old?.stopCapture();if let old=old{Task{await old.stop()}}
        enabled=false;preparing=false;level=0;progress=0;text="";composer.clear();cues=[];cueUntil = .distantPast;previewUntil = .distantPast
        timer?.invalidate();timer=nil;panel?.orderOut(nil)
        if !reason.isEmpty{status=reason};error=false;diagnostic()
    }
    private func fail(_ message:String){stop(reason:message);error=true;diagnostic()}
    func preview(){text="A little koala. Every word in reach.";previewUntil=Date().addingTimeInterval(4);lastText=Date();startTimer();updateOverlay()}
    private func startTimer(){if timer==nil{timer=Timer.scheduledTimer(withTimeInterval:0.2,repeats:true){_ in Task{@MainActor in TVLiveCaptions.shared.tick()}}}}
    private func diagnostic(){
        lastDiagnostic=Date()
        let object:[String:Any]=["engine":"Apple SpeechAnalyzer","enabled":enabled,"preparing":preparing,"status":status,"error":error,"source":source.rawValue,"level":level,"results":resultCount,"shownCues":shownCues,"skippedCues":skippedCues,"captionDelaySeconds":captionDelay,"firstWordDelaySeconds":firstWordDelay,"queuedCues":cues.count,"progress":progress,"updated":Date().timeIntervalSince1970]
        let url=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Mini Keyboard/tv-caption-status.json")
        if let data=try? JSONSerialization.data(withJSONObject:object,options:.sortedKeys){try? data.write(to:url,options:.atomic)}
    }
    private func tick(){
        if Date().timeIntervalSince(lastDiagnostic)>5{diagnostic()}
        if !enabled,previewUntil<Date(){text="";panel?.orderOut(nil);timer?.invalidate();timer=nil;return}
        if enabled,!preparing {
            enqueue(composer.flush(now:Date().timeIntervalSinceReferenceDate))
            if Date().timeIntervalSince(started)>9,Date().timeIntervalSince(lastSound)>8 {status="No playback audio yet. Press play; allow system audio recording if macOS asks."}
            else if Date().timeIntervalSince(lastText)>8 {status="Listening to "+source.title+"…"}
            engine?.refreshSource()
        }
        updateOverlay()
    }
    private func enqueue(_ incoming:[TVCaptionCue]){
        for cue in incoming {
            if let previous=cues.last,previous.text.count<22,previous.text.count+cue.text.count<72 {
                cues.removeLast();cues.append(TVCaptionCue(text:previous.text+" "+cue.text,duration:min(1.8,(previous.duration+cue.duration)*0.75),start:previous.start,end:cue.end))
            }else{cues.append(cue)}
        }
        if cues.count>2{skippedCues += cues.count-2;cues=Array(cues.suffix(2))}
        advanceCue()
    }
    private func advanceCue(){
        guard previewUntil<Date() else{return}
        let audioNow=captureBegan>0 ? ProcessInfo.processInfo.systemUptime-captureBegan:0
        // Superseded captions must not build a delay behind live speech.
        while let first=cues.first,audioNow-first.end>1.6{cues.removeFirst();skippedCues += 1}
        let nearDeadline = !cues.isEmpty && audioNow-cues[0].end>0.75
        guard cueUntil<=Date() || nearDeadline else{return}
        if !cues.isEmpty {
            let cue=cues.removeFirst();shownCues += 1;text=cue.text
            captionDelay=max(0,audioNow-cue.end);firstWordDelay=max(0,audioNow-cue.start)
            cueUntil=Date().addingTimeInterval(max(0.7,cue.duration*(cues.isEmpty ? 1:0.75)));updateOverlay()
        }else if cueUntil.addingTimeInterval(0.2)<Date(){text="";updateOverlay()}
    }
    func updateOverlay(){
        guard TVMode.shared.active,let screen=TVMode.shared.captionScreen,!text.isEmpty,(enabled || previewUntil>Date()) else{panel?.orderOut(nil);return}
        if panel==nil {
            let p=NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.title="Koala TV live captions";p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false;p.ignoresMouseEvents=true;p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false;p.level=NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+2);p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary];p.contentView=NSHostingView(rootView:TVSubtitleView(captions:self));panel=p
        }
        let f=screen.frame,w=min(f.width*0.82,1500),h=min(220,max(125,f.height*0.19))
        let y=position=="top" ? f.maxY-h-100:f.minY+max(32,f.height*0.045)
        panel?.setFrame(CGRect(x:f.midX-w/2,y:y,width:w,height:h),display:true);panel?.orderFrontRegardless()
    }
    var snapshot:[String:Any]{["supported":supported,"enabled":enabled,"preparing":preparing,"source":source.rawValue,"sourceName":source.title,"explanation":source.explanation,"language":language,"languages":locales.map{["id":$0,"name":Locale.current.localizedString(forIdentifier:$0) ?? $0]},"size":size,"position":position,"style":style,"status":status,"error":error,"level":level,"progress":progress]}
}

private struct TVSubtitleView:View {
    @ObservedObject var captions:TVLiveCaptions
    var body:some View {
        GeometryReader{g in
            let fontSize=max(22,min(50,g.size.width/(captions.size=="large" ? 23:captions.size=="small" ? 36:29)))
            VStack{Spacer(minLength:0)
                HStack(alignment:.center,spacing:14){
                    Image(systemName:"captions.bubble.fill").font(.system(size:20,weight:.semibold)).foregroundColor(TVStyle.mint).accessibilityHidden(true)
                    Text(captions.text).font(.system(size:fontSize,weight:.semibold)).foregroundColor(.white).multilineTextAlignment(.center).lineSpacing(4).lineLimit(2).fixedSize(horizontal:false,vertical:true).shadow(color:.black,radius:2)
                }.padding(.horizontal,24).padding(.vertical,16).background(captions.style=="contrast" ? Color.black:TVStyle.background.opacity(0.93)).clipShape(RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(TVStyle.mint.opacity(captions.style=="forest" ? 0.28:0),lineWidth:1))
                Spacer(minLength:0)
            }.frame(maxWidth:.infinity)
        }.accessibilityLabel("Live captions: "+captions.text)
    }
}

@MainActor protocol TVCaptionEngine:AnyObject {
    func stopCapture()
    func stop() async
    func refreshSource()
}

/// Conversion is serialized away from both the UI and the capture callback.
@available(macOS 26.0,*) final class TVCaptionPCM {
    private let queue=DispatchQueue(label:"local.koala.captions.convert",qos:.userInitiated)
    private var converter:AVAudioConverter?
    private var inputFormat:AVAudioFormat?
    private let output:AVAudioFormat
    private let continuation:AsyncStream<AnalyzerInput>.Continuation
    private var count=0
    private let onLevel:@MainActor(Double)->Void
    private let onError:@MainActor(String)->Void
    private var stopped=false
    init(format:AVAudioFormat,continuation:AsyncStream<AnalyzerInput>.Continuation,onLevel:@escaping @MainActor(Double)->Void,onError:@escaping @MainActor(String)->Void){output=format;self.continuation=continuation;self.onLevel=onLevel;self.onError=onError}
    func receive(_ buffer:AVAudioPCMBuffer){queue.async{[self] in
        guard !stopped else{return}
        if inputFormat != buffer.format{converter=AVAudioConverter(from:buffer.format,to:output);inputFormat=buffer.format}
        guard let converter=converter,let converted=AVAudioPCMBuffer(pcmFormat:output,frameCapacity:AVAudioFrameCount(ceil(Double(buffer.frameLength)*output.sampleRate/buffer.format.sampleRate))+32) else{return}
        var fed=false,error:NSError?
        let result=converter.convert(to:converted,error:&error){_,status in if fed{status.pointee = .noDataNow;return nil};fed=true;status.pointee = .haveData;return buffer}
        if result == .error {stopped=true;let message="Audio conversion stopped: "+(error?.localizedDescription ?? "unsupported format");Task{@MainActor in self.onError(message)};return}
        guard converted.frameLength>0 else{return}
        continuation.yield(AnalyzerInput(buffer:converted));count += 1
        if count%12==0 {let level=Self.rms(converted);Task{@MainActor in self.onLevel(level)}}
    }}
    static func rms(_ buffer:AVAudioPCMBuffer)->Double{
        let n=Int(buffer.frameLength);guard n>0 else{return 0};var sum:Double=0
        let stride=buffer.format.isInterleaved ? Int(buffer.format.channelCount):1
        for i in 0..<n {let x:Double
            if let p=buffer.floatChannelData{x=Double(p[0][i*stride])}else if let p=buffer.int16ChannelData{x=Double(p[0][i*stride])/32768}else if let p=buffer.int32ChannelData{x=Double(p[0][i*stride])/2147483648}else{return 0}
            sum += x*x
        };return min(1,sqrt(sum/Double(n)))
    }
    func stop(){queue.async{[self] in stopped=true;continuation.finish();converter=nil}}
}

@available(macOS 26.0,*) @MainActor final class TVSpeechCaptionEngine:TVCaptionEngine {
    private var tap:CaptionAudioTap?
    private var analyzer:SpeechAnalyzer?
    private var transcriber:SpeechTranscriber?
    private var pcm:TVCaptionPCM?
    private var results:Task<Void,Never>?
    private var analysisTask:Task<Void,Never>?
    private var progressTimer:Timer?
    private var source:TVCaptionSource = .chrome
    private var lastRefresh=Date()
    private var stopped=false
    private var reserved:Locale?
    private var onError:(@MainActor(String)->Void)?
    func start(locale:String,source:TVCaptionSource,onProgress:@escaping @MainActor(String,Double)->Void,onText:@escaping @MainActor([TVCaptionWord])->Void,onLevel:@escaping @MainActor(Double)->Void,onError:@escaping @MainActor(String)->Void) async throws {
        self.source=source;self.onError=onError
        guard let locale=await SpeechTranscriber.supportedLocale(equivalentTo:Locale(identifier:locale)) else{throw RemoteFailure.message("That speech language is not supported on this Mac.")}
        try Task.checkCancellation()
        let t=SpeechTranscriber(locale:locale,transcriptionOptions:[],reportingOptions:[.volatileResults,.fastResults],attributeOptions:[.audioTimeRange]);transcriber=t
        let alreadyReserved=(await AssetInventory.reservedLocales).contains(locale)
        try Task.checkCancellation()
        if !alreadyReserved {let added=try await AssetInventory.reserve(locale:locale);if stopped || Task.isCancelled{if added{await AssetInventory.release(reservedLocale:locale)};throw CancellationError()};if added{reserved=locale}}
        if let install=try await AssetInventory.assetInstallationRequest(supporting:[t]) {
            onProgress("Downloading Apple’s on-device speech model…",0)
            progressTimer=Timer.scheduledTimer(withTimeInterval:0.4,repeats:true){_ in Task{@MainActor in onProgress("Downloading Apple’s on-device speech model…",install.progress.fractionCompleted)}}
            do{try await install.downloadAndInstall()}catch{progressTimer?.invalidate();progressTimer=nil;throw error}
            progressTimer?.invalidate();progressTimer=nil
        }
        try Task.checkCancellation();guard !stopped else{throw CancellationError()}
        guard let format=await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:[t]) else{throw RemoteFailure.message("No compatible format for live speech captions.")}
        onProgress("Warming up live captions…",1)
        let a=SpeechAnalyzer(modules:[t]);analyzer=a
        try await a.prepareToAnalyze(in:format);try Task.checkCancellation()
        let stream=AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy:.bufferingNewest(64))
        let p=TVCaptionPCM(format:format,continuation:stream.continuation,onLevel:onLevel,onError:onError);pcm=p
        results=Task{@MainActor in do{for try await result in t.results{guard !stopped else{return};onText(Self.words(result))}}catch{if !stopped{onError("Speech recognition stopped: "+error.localizedDescription)}}}
        analysisTask=Task{@MainActor in do{try await a.start(inputSequence:stream.stream)}catch{if !stopped{onError("Speech analysis stopped: "+error.localizedDescription)}}}
        guard !stopped,!Task.isCancelled else{throw CancellationError()}
        let capture=CaptionAudioTap();tap=capture;try capture.start(source:source){buffer in p.receive(buffer)}
        lastRefresh=Date()
    }
    static func words(_ result:SpeechTranscriber.Result)->[TVCaptionWord]{
        var output:[TVCaptionWord]=[]
        for run in result.text.runs {
            let text=String(result.text[run.range].characters),parts=text.split(whereSeparator:{$0.isWhitespace})
            guard !parts.isEmpty else{continue}
            let range=run.audioTimeRange ?? result.range
            let start=CMTimeGetSeconds(range.start),duration=max(0.01,CMTimeGetSeconds(range.duration))
            for (i,part) in parts.enumerated(){output.append(TVCaptionWord(text:String(part),start:start+duration*Double(i)/Double(parts.count),end:start+duration*Double(i+1)/Double(parts.count),final:result.isFinal))}
        }
        return output
    }
    func refreshSource(){
        guard !stopped,let tap=tap,Date().timeIntervalSince(lastRefresh)>3 else{return};lastRefresh=Date()
        let new=source.processes();guard Set(new) != Set(tap.processIDs) else{return}
        guard let pcm=pcm else{return}
        do{try tap.start(source:source){pcm.receive($0)}}catch{onError?(error.localizedDescription)}
    }
    func stopCapture(){stopped=true;progressTimer?.invalidate();progressTimer=nil;tap?.stop();tap=nil;pcm?.stop();pcm=nil;results?.cancel();results=nil;analysisTask?.cancel();analysisTask=nil}
    func stop() async {
        stopCapture()
        let a=analyzer;analyzer=nil;transcriber=nil
        let locale=reserved;reserved=nil
        if let a=a{await a.cancelAndFinishNow()}
        if let locale=locale{await AssetInventory.release(reservedLocale:locale)}
    }
}
