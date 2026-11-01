import Foundation

// swiftc -Onone -swift-version 5 -target arm64-apple-macosx13.0 -parse-as-library \
//   Sources/TVSessionLayout.swift Tests/TVGameLayoutRegression.swift -o build/tv-game-layout-regression
@main struct TVGameLayoutRegression {
    static var failures = 0
    static func check(_ ok: Bool, _ name: String) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
    static func main() {
        let screen = CGRect(x: -1920, y: 249, width: 1920, height: 1080)
        let stage = TVSessionLayout.stage(screen)
        for media in 0...4 {
            let layout = TVSessionLayout.gameFrames(in: stage, media: media)
            let frames = [layout.game] + layout.media
            check(abs(layout.game.width / layout.game.height - 16.0 / 9.0) < 0.01, "game is 16:9 with \(media) media")
            check(frames.allSatisfy { stage.insetBy(dx: -1, dy: -1).contains($0) }, "all frames inside the stage with \(media) media")
            check(layout.media.count == min(media, 3), "at most three services beside a game (\(media) requested)")
            var overlap = false
            for i in frames.indices { for j in frames.indices where i < j { if frames[i].insetBy(dx: 1, dy: 1).intersects(frames[j]) { overlap = true } } }
            check(!overlap, "no overlapping windows with \(media) media")
            if media > 0 {
                check(layout.media.allSatisfy { $0.minX > layout.game.maxX }, "media column sits right of the game")
                check(layout.game.width > layout.media[0].width, "game keeps the larger area")
                check(zip(layout.media, layout.media.dropFirst()).allSatisfy { $0.minY > $1.minY }, "first service is on top (Cocoa coordinates)")
            } else {
                check(abs(layout.game.midX - stage.midX) < 1, "game alone is centred")
            }
        }
        // Existing media-only layout is unchanged.
        check(TVSessionLayout.frames(in: stage, count: 1) == [stage], "single service still fills the stage")
        print(failures == 0 ? "All game layout checks passed." : "\(failures) failure(s).")
        exit(failures == 0 ? 0 : 1)
    }
}
