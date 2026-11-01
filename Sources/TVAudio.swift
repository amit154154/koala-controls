import AppKit
import CoreAudio
import IOBluetooth

/// Native output controls. No virtual driver and no changes to input devices.
enum TVAudioHardware {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress { .init(mSelector: selector, mScope: scope, mElement: element) }
    static func uint(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: UInt32 = 0) -> UInt32? {
        var a=address(selector,scope,element), v:UInt32=0, n=UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id,&a,0,nil,&n,&v)==noErr ? v:nil
    }
    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var a=address(selector), value:Unmanaged<CFString>?, n=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id,&a,0,nil,&n,&value)==noErr else{return nil};return value?.takeRetainedValue() as String?
    }
    static func ids(_ id:AudioObjectID,_ selector:AudioObjectPropertySelector)->[AudioObjectID] {
        var a=address(selector),n:UInt32=0
        guard AudioObjectGetPropertyDataSize(id,&a,0,nil,&n)==noErr,n>0,n<1_000_000 else{return []}
        var result=[AudioObjectID](repeating:0,count:Int(n)/MemoryLayout<AudioObjectID>.size)
        guard result.withUnsafeMutableBytes({AudioObjectGetPropertyData(id,&a,0,nil,&n,$0.baseAddress!)})==noErr else{return []};return result
    }
    static var output:AudioObjectID? {uint(system,kAudioHardwarePropertyDefaultOutputDevice).flatMap{$0==0 ? nil:$0}}
    static func channels(_ id:AudioObjectID)->Int {
        var a=address(kAudioDevicePropertyStreamConfiguration,kAudioDevicePropertyScopeOutput),n:UInt32=0
        guard AudioObjectGetPropertyDataSize(id,&a,0,nil,&n)==noErr,n>=MemoryLayout<AudioBufferList>.size else{return 0}
        let p=UnsafeMutableRawPointer.allocate(byteCount:Int(n),alignment:MemoryLayout<AudioBufferList>.alignment);defer{p.deallocate()}
        guard AudioObjectGetPropertyData(id,&a,0,nil,&n,p)==noErr else{return 0}
        return UnsafeMutableAudioBufferListPointer(p.assumingMemoryBound(to:AudioBufferList.self)).reduce(0){$0+Int($1.mNumberChannels)}
    }
    static func settable(_ id:AudioObjectID,_ selector:AudioObjectPropertySelector,_ element:UInt32=0)->Bool {
        var a=address(selector,kAudioDevicePropertyScopeOutput,element),v:DarwinBoolean=false
        return AudioObjectHasProperty(id,&a) && AudioObjectIsPropertySettable(id,&a,&v)==noErr && v.boolValue
    }
    static func volume(_ id:AudioObjectID)->Double? {
        func read(_ element:UInt32)->Float32? {var a=address(kAudioDevicePropertyVolumeScalar,kAudioDevicePropertyScopeOutput,element),v:Float32=0,n=UInt32(MemoryLayout<Float32>.size);return AudioObjectGetPropertyData(id,&a,0,nil,&n,&v)==noErr ? v:nil}
        if let v=read(0),v.isFinite{return Double(v)}
        let values=(1...max(1,min(channels(id),32))).compactMap{read(UInt32($0))}.filter{$0.isFinite}
        return values.isEmpty ? nil:Double(values.reduce(0,+)/Float(values.count))
    }
    static func volumeElements(_ id:AudioObjectID)->[UInt32] {
        if settable(id,kAudioDevicePropertyVolumeScalar){return [0]}
        return (1...max(1,min(channels(id),32))).map(UInt32.init).filter{settable(id,kAudioDevicePropertyVolumeScalar,$0)}
    }
    static func setVolume(_ value:Double) throws {
        guard value.isFinite,(0...1).contains(value),let id=output else{throw RemoteFailure.message("Choose a connected sound output.")}
        let elements=volumeElements(id)
        guard !elements.isEmpty else{throw RemoteFailure.message("This output uses its own volume controls. Use the TV or speaker remote.")}
        for e in elements {var a=address(kAudioDevicePropertyVolumeScalar,kAudioDevicePropertyScopeOutput,e),v=Float32(value);guard AudioObjectSetPropertyData(id,&a,0,nil,UInt32(MemoryLayout<Float32>.size),&v)==noErr else{throw RemoteFailure.message("The sound output could not change volume.")}}
    }
    static func muted(_ id:AudioObjectID)->Bool? {uint(id,kAudioDevicePropertyMute,scope:kAudioDevicePropertyScopeOutput).map{$0 != 0}}
    static func setMute(_ value:Bool) throws {
        guard let id=output,settable(id,kAudioDevicePropertyMute) else{throw RemoteFailure.message("This output uses its own mute control.")}
        var a=address(kAudioDevicePropertyMute,kAudioDevicePropertyScopeOutput),v:UInt32=value ? 1:0
        guard AudioObjectSetPropertyData(id,&a,0,nil,UInt32(MemoryLayout<UInt32>.size),&v)==noErr else{throw RemoteFailure.message("The sound output could not change mute.")}
    }
    static func select(_ id:AudioObjectID) throws {
        guard ids(system,kAudioHardwarePropertyDevices).contains(id),channels(id)>0 else{throw RemoteFailure.message("That output disconnected. Refresh the list.")}
        var a=address(kAudioHardwarePropertyDefaultOutputDevice),v=id
        guard AudioObjectSetPropertyData(system,&a,0,nil,UInt32(MemoryLayout<AudioObjectID>.size),&v)==noErr,output==id else{throw RemoteFailure.message("macOS could not switch to that sound output.")}
    }
}

struct TVAudioOutput:Identifiable {
    let id:String,device:AudioObjectID,name:String,uid:String,bluetooth:Bool
    var json:[String:Any]{["id":id,"name":name,"bluetooth":bluetooth]}
}
struct TVHeadphones:Identifiable {
    let id:String,name:String,connected:Bool
    var json:[String:Any]{["id":id,"name":name,"connected":connected]}
}

@MainActor final class TVAudio:ObservableObject {
    static let shared=TVAudio()
    @Published var outputs:[TVAudioOutput]=[]
    @Published var headphones:[TVHeadphones]=[]
    @Published var selected=""
    @Published var volume:Double=0
    @Published var canVolume=false
    @Published var canMute=false
    @Published var muted=false
    @Published var connecting=false
    @Published var message="Choose where your evening sounds best."
    @Published var error=false
    private var ids:[String:String]=[:]
    private var paired:[String:IOBluetoothDevice]=[:]
    private var timer:Timer?
    private var connector:TVBluetoothConnector?
    private var restoreVolume:[AudioObjectID:Double]=[:]
    private var connectGeneration=UUID()
    var outputName:String{outputs.first{$0.id==selected}?.name ?? "No sound output"}
    func start(){refresh();if timer==nil{timer=Timer.scheduledTimer(withTimeInterval:1.5,repeats:true){_ in Task{@MainActor in TVAudio.shared.refresh()}}}}
    func stop(){timer?.invalidate();timer=nil;connectGeneration=UUID();connector?.cancel();connector=nil}
    func refresh(pairedDevices:Bool=false){
        let current=TVAudioHardware.output
        outputs=TVAudioHardware.ids(TVAudioHardware.system,kAudioHardwarePropertyDevices).filter{TVAudioHardware.channels($0)>0 && TVAudioHardware.uint($0,kAudioDevicePropertyDeviceIsAlive) != 0}.compactMap {device in
            guard let uid=TVAudioHardware.string(device,kAudioDevicePropertyDeviceUID),let name=TVAudioHardware.string(device,kAudioObjectPropertyName) else{return nil}
            let id=ids[uid] ?? UUID().uuidString;ids[uid]=id
            let transport=TVAudioHardware.uint(device,kAudioDevicePropertyTransportType)
            return TVAudioOutput(id:id,device:device,name:name,uid:uid,bluetooth:transport==kAudioDeviceTransportTypeBluetooth || transport==kAudioDeviceTransportTypeBluetoothLE)
        }.sorted{$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending}
        selected=outputs.first{$0.device==current}?.id ?? ""
        if let id=current {volume=TVAudioHardware.volume(id) ?? 0;canVolume = !TVAudioHardware.volumeElements(id).isEmpty;canMute=TVAudioHardware.settable(id,kAudioDevicePropertyMute) || canVolume;muted=TVAudioHardware.muted(id) ?? (canVolume && volume==0)}else{canVolume=false;canMute=false;muted=false}
        if pairedDevices{refreshHeadphones()}
    }
    func refreshHeadphones(){
        let devices=IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        var next:[String:IOBluetoothDevice]=[:]
        headphones=devices.filter{d in let n=(d.name ?? "").lowercased();return !n.contains("find my") && (n.contains("airpods") || n.contains("beats") || d.deviceClassMajor==kBluetoothDeviceClassMajorAudio)}.compactMap{d in
            guard let address=d.addressString else{return nil};let key="bt:"+address,id=ids[key] ?? UUID().uuidString;ids[key]=id;next[id]=d
            return TVHeadphones(id:id,name:d.name ?? "Bluetooth headphones",connected:d.isConnected())
        }.sorted{$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending}
        paired=next
        if headphones.isEmpty{message="No paired headphones found. Pair AirPods in macOS Bluetooth settings first, then refresh."}
    }
    func choose(_ token:String) throws {guard let o=outputs.first(where:{$0.id==token}) else{throw RemoteFailure.message("That output is no longer available. Refresh the list.")};try TVAudioHardware.select(o.device);refresh();message="Playing through "+o.name+".";error=false}
    func setVolume(_ value:Double) throws {try TVAudioHardware.setVolume(value);if value>0,let d=TVAudioHardware.output,TVAudioHardware.muted(d)==true,TVAudioHardware.settable(d,kAudioDevicePropertyMute){try TVAudioHardware.setMute(false)};refresh();error=false}
    func setMuted(_ value:Bool) throws {
        guard let d=TVAudioHardware.output else{throw RemoteFailure.message("Choose a sound output first.")}
        if TVAudioHardware.settable(d,kAudioDevicePropertyMute){try TVAudioHardware.setMute(value)}else{
            if value {if volume>0{restoreVolume[d]=volume};try TVAudioHardware.setVolume(0)}else{try TVAudioHardware.setVolume(restoreVolume[d] ?? 0.4)}
        };refresh();error=false
    }
    func connect(_ token:String) async throws {
        do {try await connectHeadphones(token);error=false}
        catch{self.error=true;message=error.localizedDescription;throw error}
    }
    private func connectHeadphones(_ token:String) async throws {
        guard !connecting,let device=paired[token],headphones.contains(where:{$0.id==token}) else{throw RemoteFailure.message("Refresh your paired headphones and choose one.")}
        let generation=connectGeneration
        connecting=true;defer{connecting=false;connector=nil;refresh(pairedDevices:true)}
        let name=device.name ?? "AirPods";message="Connecting to "+name+"… Open the case or put them in your ears."
        let c=TVBluetoothConnector();connector=c
        if !device.isConnected(){try await c.open(device)}
        // A Bluetooth link alone is not success: wait for its audio route.
        for _ in 0..<40 {
            guard generation==connectGeneration,!Task.isCancelled else{throw CancellationError()}
            refresh()
            let address=(device.addressString ?? "").lowercased().filter{$0.isHexDigit}
            if let route=outputs.first(where:{o in o.bluetooth && (o.name==name || (!address.isEmpty && o.uid.lowercased().filter{$0.isHexDigit}.contains(address)))}) {try choose(route.id);return}
            try await Task.sleep(nanoseconds:300_000_000)
        }
        throw RemoteFailure.message(name+" has no audio route yet. Open its case, disconnect it from the other device if needed, or use Bluetooth settings, then refresh.")
    }
    func perform(_ operation:() throws->Void){do{try operation()}catch{self.error=true;message=error.localizedDescription}}
    var snapshot:[String:Any]{["outputs":outputs.map(\.json),"headphones":headphones.map(\.json),"selected":selected,"name":outputName,"volume":volume,"canVolume":canVolume,"canMute":canMute,"muted":muted,"connecting":connecting,"message":message,"error":error]}
    func settings(){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.BluetoothSettings")!)}
}

/// The non-nil callback target makes openConnection asynchronous; never blocks TV input.
private final class TVBluetoothConnector:NSObject {
    private var continuation:CheckedContinuation<Void,Error>?
    private var timeout:DispatchWorkItem?
    @MainActor func open(_ device:IOBluetoothDevice) async throws {
        try await withCheckedThrowingContinuation {c in
            continuation=c
            let status=device.openConnection(self)
            guard status==kIOReturnSuccess else{finish(RemoteFailure.message("Bluetooth could not connect. Open the AirPods case and try again."));return}
            let work=DispatchWorkItem{[weak self] in self?.finish(RemoteFailure.message("AirPods did not respond. Put them in your ears or open the case and try again."))};timeout=work;DispatchQueue.main.asyncAfter(deadline:.now()+15,execute:work)
        }
    }
    @objc func connectionComplete(_ device:IOBluetoothDevice!,status:IOReturn){DispatchQueue.main.async{self.finish(status==kIOReturnSuccess ? nil:RemoteFailure.message("Bluetooth could not connect. Make sure the headphones are nearby and available."))}}
    func cancel(){finish(CancellationError())}
    private func finish(_ error:Error?){timeout?.cancel();timeout=nil;let c=continuation;continuation=nil;if let error=error{c?.resume(throwing:error)}else{c?.resume()}}
}
