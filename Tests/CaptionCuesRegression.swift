import Foundation
@main struct CaptionCuesRegression {
 static func main(){
  var checks=0;func check(_ value:@autoclosure()->Bool,_ name:String){checks+=1;if !value(){fatalError(name)}}
  func words(_ text:String,final:Bool=false,start:Double=0)->[TVCaptionWord]{text.split(separator:" ").enumerated().map{TVCaptionWord(text:String($0.element),start:start+Double($0.offset)*0.3,end:start+Double($0.offset+1)*0.3,final:final)}}
  var cues=TVCaptionCues()
  check(cues.submit(words("A little koala can"),now:0).isEmpty,"Do not show new draft words")
  let early=cues.submit(words("A little koala can hear every word."),now:0.3);check(early.allSatisfy{$0.text=="A little koala can"},"Stable prefix appears as one fixed phrase")
  let ready=cues.submit(words("A little koala can hear every word."),now:0.9);check(!(early+ready).isEmpty,"Stable prefix becomes a short cue without waiting for a long sentence")
  let first=early+ready+cues.flush(now:1.8);check(first.count>=1,"Short cues flush after a short silence")
  check(first.map(\.text).joined(separator:" ")=="A little koala can hear every word.","All words appear in immutable short cues")
  check(first[0].duration>=0.75 && first[0].duration<=1.8,"Readable bounded cue duration")
  let original=first[0]
  check(cues.submit(words("A tiny koala can hear every word.",final:true),now:2).isEmpty,"Late corrections never repeat emitted speech")
  check(first[0]==original,"Already visible text remains immutable")
  var next=cues.submit(words("Basketball is more fun with friends.",final:true,start:3),now:3.5);next += cues.flush(now:4.1);check(next.map(\.text).joined(separator:" ")=="Basketball is more fun with friends.","Next finished sentence becomes a separate cue")
  var long=TVCaptionCues();var all=long.submit(words(String(repeating:"eucalyptus ",count:35),final:true),now:0);all += long.flush(now:1);check(all.count>2 && all.allSatisfy{$0.text.count<=90},"Long speech becomes short caption cues")
  check(all.map(\.text).joined(separator:" ")==String(repeating:"eucalyptus ",count:35).trimmingCharacters(in:.whitespaces),"Chunking preserves every word")
  var unstable=TVCaptionCues();_=unstable.submit(words("The coat is red"),now:0);_=unstable.submit(words("The koala is ready."),now:0.25);let corrected=unstable.flush(now:1.2);check(corrected.map(\.text).joined(separator:" ")=="The koala is ready.","Recognition corrections occur before display")
  unstable.clear();check(unstable.submit(words("Fresh start.",final:true),now:4).first?.text=="Fresh start.","Stop clears cue cursor")
  var conversation=TVCaptionCues();check(conversation.submit(words("The koala",final:true),now:0).isEmpty,"Final fragments still wait for a complete cue")
  check(conversation.submit(words("goes home.",final:true,start:0.6),now:0.4).map(\.text)==["The koala goes home."],"Short final fragments join the next phrase")
  print("\(checks) finished-caption cue checks passed.")
 }
}
