import Foundation
import CoreAudio
import AVFoundation

/// Only known media process families are capturable. Chrome mixes audio across its tabs.
enum TVCaptionSource:String,CaseIterable {
    case chrome,appleTV,spotify
    var title:String {switch self{case .chrome:return "Chrome / GDN audio";case .appleTV:return "Apple TV audio";case .spotify:return "Spotify audio"}}
    var explanation:String {switch self{case .chrome:return "Includes sound from Chrome and its web apps. Pause other Chrome media for clear captions.";case .appleTV:return "Captures Apple TV playback only. Protected videos may block audio capture.";case .spotify:return "Captures Spotify playback only."}}
    func includes(_ bundle:String)->Bool {switch self{case .chrome:return bundle=="com.google.Chrome" || bundle.hasPrefix("com.google.Chrome.");case .appleTV:return bundle=="com.apple.TV" || bundle.hasPrefix("com.apple.TV.");case .spotify:return bundle=="com.spotify.client" || bundle.hasPrefix("com.spotify.client.")}}
    @available(macOS 14.2,*) func processes()->[AudioObjectID] {TVAudioHardware.ids(TVAudioHardware.system,kAudioHardwarePropertyProcessObjectList).filter{includes(TVAudioHardware.string($0,kAudioProcessPropertyBundleID) ?? "")}}
}

/// A private, unmuted process tap; no disk recording or output replay.
@available(macOS 14.2,*) final class CaptionAudioTap {
    private var tap:AudioObjectID=0,aggregate:AudioObjectID=0
    private var proc:AudioDeviceIOProcID?
    private let queue=DispatchQueue(label:"local.koala.captions.capture",qos:.userInitiated)
    private(set) var processIDs:[AudioObjectID]=[]
    private(set) var format:AVAudioFormat?
    func start(source:TVCaptionSource,receive:@escaping(AVAudioPCMBuffer)->Void) throws {
        stop();let processes=source.processes()
        guard !processes.isEmpty else{throw RemoteFailure.message("Open "+source.title+" and start a video, then enable captions.")}
        let description=CATapDescription(stereoMixdownOfProcesses:processes)
        description.name="Koala TV live captions";description.uuid=UUID();description.isPrivate=true;description.muteBehavior = .unmuted
        func check(_ status:OSStatus,_ step:String) throws {guard status==noErr else{throw RemoteFailure.message("Captions could not "+step+" (\(status)). Allow Mini Keyboard in System Settings → Privacy & Security → Screen & System Audio Recording, then try again.")}}
        do {
            try check(AudioHardwareCreateProcessTap(description,&tap),"capture playback audio")
            var asbd=AudioStreamBasicDescription(),a=TVAudioHardware.address(kAudioTapPropertyFormat),n=UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(tap,&a,0,nil,&n,&asbd),"read the audio format")
            guard let fmt=AVAudioFormat(streamDescription:&asbd),fmt.channelCount>0,fmt.sampleRate>0 else{throw RemoteFailure.message("This media audio format is unavailable.")};format=fmt
            let config:[String:Any]=[kAudioAggregateDeviceNameKey:"Koala captions (private)",kAudioAggregateDeviceUIDKey:"local.koala.captions."+UUID().uuidString,kAudioAggregateDeviceIsPrivateKey:true,kAudioAggregateDeviceTapAutoStartKey:true,kAudioAggregateDeviceTapListKey:[[kAudioSubTapUIDKey:description.uuid.uuidString,kAudioSubTapDriftCompensationKey:true]]]
            try check(AudioHardwareCreateAggregateDevice(config as CFDictionary,&aggregate),"prepare playback capture")
            try check(AudioDeviceCreateIOProcIDWithBlock(&proc,aggregate,queue){_,input,_,_,_ in
                let list=UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating:input))
                guard let first=list.first,first.mDataByteSize>0,asbd.mBytesPerFrame>0 else{return}
                let frames=AVAudioFrameCount(first.mDataByteSize/asbd.mBytesPerFrame)
                guard frames>0,frames<=65_536,let copy=AVAudioPCMBuffer(pcmFormat:fmt,frameCapacity:frames) else{return}
                copy.frameLength=frames
                let dest=UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
                guard dest.count==list.count else{return}
                for i in 0..<list.count {guard let src=list[i].mData,let dst=dest[i].mData,list[i].mDataByteSize<=dest[i].mDataByteSize else{return};memcpy(dst,src,Int(list[i].mDataByteSize));dest[i].mDataByteSize=list[i].mDataByteSize}
                receive(copy)
            },"start the audio stream")
            try check(AudioDeviceStart(aggregate,proc),"start listening")
            processIDs=processes
        }catch{stop();throw error}
    }
    func stop(){
        if aggregate != 0,let proc=proc{AudioDeviceStop(aggregate,proc);AudioDeviceDestroyIOProcID(aggregate,proc)};proc=nil
        if aggregate != 0{AudioHardwareDestroyAggregateDevice(aggregate);aggregate=0}
        if tap != 0{AudioHardwareDestroyProcessTap(tap);tap=0};format=nil;processIDs=[]
    }
    deinit{stop()}
}
