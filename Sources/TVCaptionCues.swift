import Foundation

struct TVCaptionWord {
    var text:String
    var start:Double
    var end:Double
    var final:Bool=false
}
struct TVCaptionCue:Equatable {
    let text:String
    let duration:Double
    let start:Double
    let end:Double
    init(text:String,duration:Double,start:Double=0,end:Double=0){self.text=text;self.duration=duration;self.start=start;self.end=end}
}

/// Draft recognition can change freely; once a cue leaves here its text never changes.
/// Time-indexed words prevent later recognition corrections from repeating an emitted phrase.
struct TVCaptionCues {
    private struct Draft {var word:TVCaptionWord;var firstSeen:Double}
    private var draft:[Draft]=[]
    private var committedThrough = -Double.greatestFiniteMagnitude
    private var latestEnd=0.0,lastUpdate = -Double.greatestFiniteMagnitude
    mutating func submit(_ words:[TVCaptionWord],now:Double)->[TVCaptionCue] {
        let incoming=words.filter{$0.start.isFinite && $0.end.isFinite && $0.end >= $0.start && !$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}.sorted{$0.start<$1.start}
        guard let first=incoming.first else{return []}
        let old=draft
        draft.removeAll{$0.word.end>first.start+0.015}
        for var word in incoming where word.end>committedThrough+0.025 && word.start>=committedThrough-0.06 {
            word.text=String(word.text.trimmingCharacters(in:.whitespacesAndNewlines).prefix(80))
            let prior=old.first{abs($0.word.start-word.start)<0.08 && $0.word.text==word.text}
            draft.append(Draft(word:word,firstSeen:prior?.firstSeen ?? now))
        }
        draft=Array(draft.sorted{$0.word.start<$1.word.start}.suffix(160))
        latestEnd=max(latestEnd,incoming.last?.end ?? latestEnd);lastUpdate=now
        return drain(now:now)
    }
    mutating func flush(now:Double)->[TVCaptionCue]{drain(now:now)}
    private mutating func drain(now:Double)->[TVCaptionCue] {
        var cues:[TVCaptionCue]=[]
        let quiet=now-lastUpdate>=0.45
        while !draft.isEmpty {
            let eligible=draft.prefix{d in d.word.final || (now-d.firstSeen>=0.22 && (d.word.end<=latestEnd-0.18 || quiet))}.count
            guard eligible>0 else{break}
            var cut=0,chars=0
            for i in 0..<eligible {
                let word=draft[i].word;chars += word.text.count+(i==0 ? 0:1)
                if i>0,chars>82 {cut=i;break}
                let punctuation=word.text.last.map{[".","!","?","…"].contains(String($0))} ?? false
                if punctuation {cut=i+1;break}
                if i>=6,word.text.hasSuffix(","){cut=i+1;break}
                if i>=4 || word.end-draft[0].word.start>=1.15 || chars>=50 {cut=i+1;break}
            }
            if cut==0 {
                if quiet {cut=eligible}
                else if eligible>=2,latestEnd-draft[0].word.start>=1.35 {cut=min(eligible,4)}
            }
            guard cut>0 else{break}
            let batch=Array(draft.prefix(cut));draft.removeFirst(cut)
            committedThrough=max(committedThrough,batch.last!.word.end)
            let text=batch.map{$0.word.text}.joined(separator:" ")
            let spoken=max(0.6,batch.last!.word.end-batch[0].word.start)
            let reading=Double(batch.count)/5.0
            cues.append(TVCaptionCue(text:text,duration:max(0.75,min(1.8,max(spoken,reading))),start:batch.first!.word.start,end:batch.last!.word.end))
        }
        return cues
    }
    mutating func clear(){self=Self()}
}
