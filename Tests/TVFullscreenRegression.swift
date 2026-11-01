import AppKit
@main struct TVFullscreenRegression {
 @MainActor static func main() throws {
  var checks=0
  func check(_ b:@autoclosure()->Bool,_ name:String){checks+=1;if !b(){fatalError(name)}}
  for label in ["Fullscreen","Full screen","Full screen (f)","Enter full screen"," FULLSCREEN "]{check(TVPlayerFullscreen.intent(label) == .enter,"Recognize player enter button")}
  for label in ["Exit Fullscreen","Exit full screen (f)","Leave full screen"]{check(TVPlayerFullscreen.intent(label) == .exit,"Recognize player exit button")}
  for label in ["Full screen settings","Close","Picture-in-Picture","Exit","Play","Toggle fullscreen ad"]{check(TVPlayerFullscreen.intent(label)==nil,"Never invoke another player control")}
  check(TVPlayerFullscreen.automaticReflow(busy:false,fullscreen:false),"Idle shared layout may reflow")
  for (busy,full) in [(true,false),(false,true),(true,true)]{check(!TVPlayerFullscreen.automaticReflow(busy:busy,fullscreen:full),"Never resize a transitioning/full-screen player")}
  let tv=CGRect(x:-1920,y:0,width:1920,height:1080)
  check(TVPlayerFullscreen.onDisplay(tv,tv),"Fullscreen on TV left of Mac")
  check(!TVPlayerFullscreen.onDisplay(CGRect(x:0,y:0,width:2056,height:1329),tv),"Reject fullscreen on covered Mac")
  check(!TVPlayerFullscreen.onDisplay(CGRect(x:-1500,y:100,width:900,height:600),tv),"A resized window is not full screen")
  let now=Date(),cmd:[String:Any]=["id":UUID().uuidString,"kind":"tv","timestamp":now.timeIntervalSince1970,"control":"fullscreen"]
  check((try? RemoteCommandPolicy.validate(cmd,now:now))=="tv","Paired phone uses typed fullscreen command")
  print("\(checks) full-screen player intent, transition safety, target display and phone checks passed.")
 }
}
