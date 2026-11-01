import AppKit
import Foundation

@main struct TVRegression {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        var checks = 0
        func check(_ ok: @autoclosure () -> Bool, _ message: String) { checks += 1; if !ok() { fatalError(message) } }
        let now=Date()
        func object(_ args:[String:Any]) -> [String:Any] { ["id":UUID().uuidString,"timestamp":now.timeIntervalSince1970,"kind":"tv"].merging(args){_,b in b} }
        for c in ["home","exit","display","refresh","setup","resume","trackpad","share","focus","select","controllers","bluetooth","back","up","down","left","right","playPause","previous","next","tab","shiftTab","fullscreen"] {
            check((try? RemoteCommandPolicy.validate(object(["control":c]),now:now)) == "tv","Allow typed TV control " + c)
        }
        for extra:[String:Any] in [["control":"shell"],["control":"media","service":"https://evil.test"],["control":"game","game":"../../etc/passwd"],["control":"game","game":"a;rm -rf"],["control":"display","display":"abc"],["control":"home","display":true],["control":"game","game":123]] {
            check((try? RemoteCommandPolicy.validate(object(extra),now:now)) == nil,"Reject unsafe TV inputs")
        }
        for service in MediaDestination.allCases { check((try? RemoteCommandPolicy.validate(object(["control":"media","service":service.rawValue]),now:now)) == "tv","All seven media destinations") }
        for id in ["BCUS98282","NPUA80645"] { check(TVLibrary.validID(id),"RPCS3 title ID valid"); check((try? RemoteCommandPolicy.validate(object(["control":"game","game":id]),now:now)) == "tv","Discovered game ID allowed") }
        for bad in ["", "../BCUS98282", "NPUA80645;open", "NPUA80645\n",String(repeating:"A",count:100)] { check(!TVLibrary.validID(bad),"Bad IDs fail closed") }
        for bytes in [Data(),Data([0,80,83,70]),Data(repeating:255,count:128),Data([0,80,83,70]+Array(repeating:255,count:200))] { check(TVSFO.strings(bytes).isEmpty,"Malformed SFO cannot overread") }
        let tmp=FileManager.default.temporaryDirectory.appendingPathComponent("koala-tv-test-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:tmp,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:tmp) }
        try "BCUS98282: /missing/Ratchet & Clank Collection (USA).iso\nINVALID: /etc/passwd\n".write(to:tmp.appendingPathComponent("games.yml"),atomically:true,encoding:.utf8)
        let missing=TVLibrary.load(root:tmp);check(missing.count==1 && !missing[0].available,"Missing game stays visible, cannot launch");check(missing[0].title=="Ratchet & Clank Collection","Clean titles")
        for count in 1...4 {
            let screen=CGRect(x:-1920,y:200,width:1920,height:1080),stage=TVSessionLayout.stage(screen),frames=TVSessionLayout.frames(in:stage,count:count)
            check(frames.count==count,"Correct shared-screen count")
            check(stage.maxY < screen.maxY-TVSessionLayout.railHeight(screen),"Top rail stays clear")
            for i in frames.indices {
                check(stage.contains(frames[i]),"Every view stays inside TV stage")
                check(frames[i].width>0 && frames[i].height>0,"Usable tile dimensions")
                for j in frames.indices where j>i {check(!frames[i].intersects(frames[j]),"Tiles never overlap")}
            }
        }
        check(TVSessionLayout.frames(in:.zero,count:0).isEmpty && TVSessionLayout.frames(in:.zero,count:5).isEmpty,"Only one to four TV panes")
        for c in ["focusMedia","hideMedia"] {
            check((try? RemoteCommandPolicy.validate(object(["control":c,"service":"appleTV"]),now:now))=="tv","Apple TV session controls allowed")
            check((try? RemoteCommandPolicy.validate(object(["control":c,"service":"../../etc/passwd"]),now:now))==nil,"Session controls reject arbitrary targets")
        }
        check(MediaDestination.appleTV.appURL?.path=="/System/Applications/TV.app","Apple TV uses the native app")
        let real=TVLibrary.load();check(real.count==4,"Four real game entries discovered");check(real.filter(\.available).count==2,"Two available entries");check(!real.contains(where:{$0.title.localizedCaseInsensitiveContains("manual")}),"Manuals filtered");check(real.first(where:{$0.id=="BCUS98282"})?.icon != nil,"Real disc artwork extracted without mounting ISO");check(real.first(where:{$0.id=="NPUA80645"})?.icon != nil,"Installed game artwork")
        let tv=TVMode();tv.refresh();tv.selected="media:youtubeMusic";tv.navigate("left");check(tv.selected=="media:youtubeMusic","Left edge clamped");tv.navigate("right");check(tv.selected=="media:spotify","Horizontal focus");tv.navigate("down");check(["share","resume","setup","exit"].contains(tv.selected),"Session action navigation");tv.navigate("down");check(tv.selected.hasPrefix("game:"),"Existing game shelf navigation");tv.navigate("up");tv.navigate("up");check(tv.selected.hasPrefix("media:"),"Return to services")
        let chosen=try tv.display();let chosenID=MediaScreens.id(chosen);check(!MediaScreens.displays().contains(where:{$0.id==chosenID && $0.isIPad}),"TV automatic routing excludes iPad")
        if let builtIn=MediaScreens.displays().first(where: \.builtIn) {
            tv.targetID=builtIn.id;tv.selected="media:youtubeMusic";tv.navigate("down")
            check(tv.selected=="media:netflix","Laptop down follows the four-column grid")
            tv.navigate("up");check(tv.selected=="media:youtubeMusic","Laptop up returns to first service row")
            check(tv.rows[0].count==4 && tv.rows[1].count==4,"Laptop service rows match its visible grid")
        }
        let resumeID=UUID().uuidString
        check((try? RemoteCommandPolicy.validate(object(["control":"resumeOpen","item":resumeID]),now:now))=="tv","Opaque resume ID allowed")
        check((try? RemoteCommandPolicy.validate(object(["control":"refreshOpen"]),now:now))=="tv","Read-only open media refresh allowed")
        for bad:Any in ["https://youtube.com/watch?v=foo","../../etc/passwd","123",true,123,""] {
            check((try? RemoteCommandPolicy.validate(object(["control":"resumeOpen","item":bad]),now:now))==nil,"Resume rejects arbitrary URLs, paths and IDs")
        }
        let listing="youtube\t101\t202\t-1920\t100\t0\t1180\tA real open video\t1"
        let parsed=TVBrowserTab.parse(listing)
        check(parsed?.service == .youtube && parsed?.tab=="202" && parsed?.active==true,"Parse exact running browser tab identity")
        check(parsed?.frame==CGRect(x:-1920,y:100,width:1920,height:1080),"Browser window coordinates support displays left of Mac")
        for bad in [listing.replacingOccurrences(of:"youtube",with:"shell"),listing.replacingOccurrences(of:"101",with:"-1"),listing.replacingOccurrences(of:"202",with:"2;open"),listing.replacingOccurrences(of:"-1920",with:"nan"),listing.replacingOccurrences(of:"1180",with:"0"),listing+"\textra","youtube\t1"] {
            check(TVBrowserTab.parse(bad)==nil,"Malformed browser metadata fails closed")
        }
        let summary=real.map { ["id":$0.id,"title":$0.title,"available":$0.available,"art":$0.icon != nil] as [String:Any] }
        try JSONSerialization.data(withJSONObject:["games":summary,"display":chosen.localizedName,"controllers":tv.controllers.map { $0.name },"checks":checks],options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:"work/tv-library-check.json"))
        print("\(checks) TV library, navigation, routing and command security checks passed")
    }
}
