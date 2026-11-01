import Foundation
import AVFoundation
import Speech
@main struct CaptionsSpeechRegression {
    @MainActor static func main() async throws {
        guard #available(macOS 26,*) else{return}
        guard let locale=await SpeechTranscriber.supportedLocale(equivalentTo:Locale(identifier:"en-US")) else{fatalError("English unavailable")}
        let transcriber=SpeechTranscriber(locale:locale,transcriptionOptions:[],reportingOptions:[.volatileResults,.fastResults],attributeOptions:[.audioTimeRange])
        guard let format=await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:[transcriber]) else{fatalError("Install the speech model in Koala TV first")}
        let analyzer=SpeechAnalyzer(modules:[transcriber]);try await analyzer.prepareToAnalyze(in:format)
        let stream=AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy:.bufferingNewest(64))
        var recognized="",timedWords=0,nonzeroLevels=0,conversionError=""
        let results=Task{@MainActor in
            for try await result in transcriber.results {
                recognized += " "+String(result.text.characters)
                timedWords += result.text.runs.filter{$0.audioTimeRange != nil}.count
            }
        }
        try await analyzer.start(inputSequence:stream.stream)
        let pcm=TVCaptionPCM(format:format,continuation:stream.continuation,onLevel:{if $0>0.001{nonzeroLevels+=1}},onError:{conversionError=$0})
        let file=try AVAudioFile(forReading:URL(fileURLWithPath:CommandLine.arguments[1]))
        while file.framePosition<file.length {
            let b=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:3200)!
            try file.read(into:b);pcm.receive(b);try await Task.sleep(nanoseconds:10_000_000)
        }
        pcm.stop();try await Task.sleep(nanoseconds:300_000_000)
        try await analyzer.finalizeAndFinishThroughEndOfInput();try await results.value
        precondition(conversionError.isEmpty,"Fixture conversion failed")
        precondition(nonzeroLevels>0,"Int16 speech levels must be measured")
        precondition(timedWords>0,"Word timestamps must exist for fixed subtitle cues")
        precondition(recognized.lowercased().contains("basketball") && recognized.lowercased().contains("captions"),"Known local fixture should transcribe")
        print("Local speech fixture passed: real SpeechAnalyzer recognized known speech, time-indexed words, 44.1 kHz conversion and Int16 audio levels. No playback capture or microphone used.")
    }
}
