import Foundation
import CoreGraphics

@main struct TVConnectionRegression {
 static func main() throws {
    var checks=0
    func check(_ value:@autoclosure()->Bool,_ name:String){checks+=1;if !value(){fatalError(name)}}
    var p=TVConnectionPolicy()
    check(!p.update(present:false,enabled:true,busy:false),"No TV means no launch")
    check(p.update(present:true,enabled:true,busy:false),"Already attached TV starts at app launch")
    for _ in 0..<10 {check(!p.update(present:true,enabled:true,busy:false),"Resolution or repeated screen notifications never reopen TV")}
    p.suppress();check(!p.update(present:true,enabled:true,busy:false),"End TV remains ended on the same connection")
    check(!p.update(present:false,enabled:true,busy:false),"Disconnect clears the connection")
    check(p.update(present:true,enabled:true,busy:false),"Reconnecting starts TV again")
    var disabled=TVConnectionPolicy();check(!disabled.update(present:true,enabled:false,busy:false),"Disabled automation never launches")
    check(disabled.update(present:true,enabled:true,busy:false),"Enabling automation can start an unhandled attached TV")
    var busy=TVConnectionPolicy();check(!busy.update(present:true,enabled:true,busy:true),"Wait while arranging media")
    check(busy.update(present:true,enabled:true,busy:false),"Pending connection launches once media is idle")
    var vanished=TVConnectionPolicy();_=vanished.update(present:true,enabled:true,busy:true);check(!vanished.update(present:false,enabled:true,busy:false),"Disconnect cancels a pending start")
    let laptop:(UInt32,Bool,Bool,Bool)=(1,true,true,false),tv:(UInt32,Bool,Bool,Bool)=(2,false,false,false),other:(UInt32,Bool,Bool,Bool)=(3,false,false,false)
    check(TVDisplayIdentity.blankIDs(tv:2,displays:[laptop,tv])==[1],"Blank the MacBook, never the TV")
    check(TVDisplayIdentity.blankIDs(tv:2,displays:[laptop,tv,other])==[1],"Office screens remain untouched")
    check(TVDisplayIdentity.blankIDs(tv:2,displays:[(2,false,true,false)])==[],"Closed lid with only the TV never blanks the TV")
    check(TVDisplayIdentity.blankIDs(tv:2,displays:[(1,true,false,false),(2,false,true,false)])==[1],"TV may be primary while MacBook is blank")
    check(TVDisplayIdentity.blankIDs(tv:2,displays:[(3,false,true,false),tv])==[3],"Use the non-TV main display when no MacBook display is available")
    check(TVDisplayIdentity.blankIDs(tv:2,displays:[laptop,(2,false,false,true)])==[],"Never black out a mirrored TV")
    check(TVDisplayIdentity.blankIDs(tv:99,displays:[laptop,tv])==[],"Disconnected target cannot blank anything")
    check(TVDisplayIdentity.blankIDs(tv:1,displays:[laptop,tv])==[],"Built-in TV target cannot blank itself")
    let now=Date();func object(_ control:String,_ args:[String:Any]=[:])->[String:Any]{["id":UUID().uuidString,"kind":"tv","timestamp":now.timeIntervalSince1970,"control":control].merging(args){_,b in b}}
    for control in ["automaticTV","macScreen"] {for value in [true,false]{let key=control=="macScreen" ? "blank":"enabled";check((try? RemoteCommandPolicy.validate(object(control,[key:value]),now:now))=="tv","Accept typed phone display toggle")};for bad:Any in [0,1,"true",NSNull()] {let key=control=="macScreen" ? "blank":"enabled";check((try? RemoteCommandPolicy.validate(object(control,[key:bad]),now:now))==nil,"Reject unsafe display toggle")}}
    check((try? RemoteCommandPolicy.validate(object("rememberTV"),now:now))=="tv","Remember command accepts no raw display identity")
    print("\(checks) TV connection, safe blanking, reconnect and phone command checks passed.")
 }
}
