import AppKit

/// The user's unmodified sound effects travel with the app, independent of Downloads.
struct CompanionSoundPicker {
    private var remaining: [Int] = []
    private var previous: Int?
    private var previousCount = 0

    static let movementNames = ["004","005","006","007","008","009","010","014"].map { "Maplestory-" + $0 + ".wav" }
    static let reservedNames: Set<String> = ["Maplestory-001.wav","Maplestory-011.wav"]
    static func urls(in bundle: Bundle, movement: Bool = false) -> [URL] {
        let urls = (bundle.urls(forResourcesWithExtension: "wav", subdirectory: "MapleStorySounds") ?? []).filter { movement ? movementNames.contains($0.lastPathComponent) : !reservedNames.contains($0.lastPathComponent) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if !urls.isEmpty { return urls }
        if movement { return [] }
        return bundle.url(forResource: "koala-pop", withExtension: "wav").map { [$0] } ?? []
    }

    mutating func next(count: Int) -> Int? {
        guard count > 0 else { remaining = []; previous = nil; previousCount = 0; return nil }
        if count != previousCount { remaining = []; previous = nil; previousCount = count }
        if remaining.isEmpty {
            remaining = Array(0..<count).shuffled()
            if count > 1, remaining.last == previous { remaining.swapAt(0, count - 1) }
        }
        let result = remaining.removeLast()
        previous = result
        return result
    }
}
