import AppKit
import Foundation
import CoreAudio


@main struct CaptionsAudioRegression {
    @MainActor static func main() throws {
        var checks=0
        func check(_ ok:@autoclosure()->Bool,_ name:String){checks+=1;if !ok(){fatalError(name)}}
        let now=Date();func object(_ control:String,_ args:[String:Any]=[:])->[String:Any]{["id":UUID().uuidString,"kind":"tv","timestamp":now.timeIntervalSince1970,"control":control].merging(args){_,b in b}}
        for (c,args) in [("captions",["enabled":true]),("captions",["enabled":false]),("audioMute",["muted":true]),("audioVolume",["value":0.42]),("audioOutput",["output":UUID().uuidString]),("audioConnect",["headphones":UUID().uuidString]),("captionSettings",["size":"large","position":"top","source":"chrome","style":"contrast","language":"en-US"])] as [(String,[String:Any])]{check((try? RemoteCommandPolicy.validate(object(c,args),now:now))=="tv","Allow typed AV action")}
        for c in ["av","audioRefresh","audioSettings","captionPreview"]{check((try? RemoteCommandPolicy.validate(object(c),now:now))=="tv","Allow simple AV action")}
        for (c,args) in [("captions",["enabled":1]),("captions",["enabled":"true"]),("audioMute",["muted":0]),("audioVolume",["value":true]),("audioVolume",["value":Double.nan]),("audioVolume",["value":1.01]),("audioVolume",["value":-0.1]),("audioOutput",["output":"MacBook Pro Speakers"]),("audioConnect",["headphones":"AA:BB:CC"]),("captionSettings",[:]),("captionSettings",["source":"microphone"]),("captionSettings",["size":"huge"]),("captionSettings",["position":"random"]),("captionSettings",["style":"script"]),("captionSettings",["language":"en;open anything"])] as [(String,[String:Any])]{check((try? RemoteCommandPolicy.validate(object(c,args),now:now))==nil,"Reject untyped or unsafe AV action")}
        var text=TVCaptionText()
        check(text.insert(start:0,text:"The koala") == "The koala","First partial")
        check(text.insert(start:0,text:"The koala loves basketball.")=="The koala loves basketball.","Partial replaces, never duplicates")
        check(text.insert(start:2,text:"Every word in reach.")=="The koala loves basketball. Every word in reach.","Consecutive fragments join")
        check(text.insert(start:2,text:"Every word is in reach.").contains("Every word is in reach."),"Corrections replace only their range")
        let bounded=TVCaptionText.visible(String(repeating:"eucalyptus ",count:1000));check(bounded.count<=180 && !bounded.hasPrefix("calyptus"),"Long captions bounded at word boundaries")
        check(!text.insert(start:30,text:"A new scene.").contains("basketball"),"Stale speech discarded")
        text.clear();check(text.insert(start:0,text:"Fresh start")=="Fresh start","Stop clears prior speech")
        check(TVCaptionSource.chrome.includes("com.google.Chrome.helper"),"Chrome audio helper included")
        for b in ["us.zoom.xos","com.apple.FaceTime","com.apple.Terminal","org.rpcs3.rpcs3","local.minikeyboard.app"] {check(!TVCaptionSource.allCases.contains{$0.includes(b)},"Unrelated processes excluded")}
        let outputs=TVAudioHardware.ids(TVAudioHardware.system,kAudioHardwarePropertyDevices).filter{TVAudioHardware.channels($0)>0}
        check(!outputs.isEmpty,"Real connected outputs discovered")
        check(TVAudioHardware.output.map{outputs.contains($0)} ?? false,"Default route is a connected output")
        if let current=TVAudioHardware.output,let volume=TVAudioHardware.volume(current){check(volume.isFinite && (0...1).contains(volume),"CoreAudio volume reports valid scalar")}
        print("\(checks) caption/audio regression checks passed. No capture, Bluetooth connection, or audio settings changed.")
    }
}
