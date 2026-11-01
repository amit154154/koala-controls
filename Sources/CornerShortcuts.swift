import Foundation

enum WindowCorner: String, CaseIterable, Codable {
    case topLeft, topRight, bottomLeft, bottomRight
    var actionID: String { [Self.topLeft:"win_tl", .topRight:"win_tr", .bottomLeft:"win_bl", .bottomRight:"win_br"][self]! }
    var title: String { [Self.topLeft:"Top left", .topRight:"Top right", .bottomLeft:"Bottom left", .bottomRight:"Bottom right"][self]! }
    var symbol: String { [Self.topLeft:"arrow.up.left", .topRight:"arrow.up.right", .bottomLeft:"arrow.down.left", .bottomRight:"arrow.down.right"][self]! }
    var glyph: String { [Self.topLeft:"↖", .topRight:"↗", .bottomLeft:"↙", .bottomRight:"↘"][self]! }
    var pad: String { [Self.topLeft:"10 + 11", .topRight:"12 + 11", .bottomLeft:"10 + 9", .bottomRight:"12 + 9"][self]! }
    var laptop: String { [Self.topLeft:"[ + ]", .topRight:"\\ + ]", .bottomLeft:"[ + P", .bottomRight:"\\ + P"][self]! }
    var windowAction: WindowAction { [Self.topLeft:.topLeft, .topRight:.topRight, .bottomLeft:.bottomLeft, .bottomRight:.bottomRight][self]! }
    static func from(actionID: String) -> Self? { allCases.first { $0.actionID == actionID } }
}

enum CornerTrigger: Equatable { case single(String), corner(WindowCorner) }
/// Wait for release on the four chord keys. A matched pair consumes both singles.
/// No timer or ordering requirement: hold either key, then press its partner.
struct CornerChordState {
    static let defaults = ["k9":"win_min", "k10":"win_left", "k11":"win_max", "k12":"win_right"]
    private(set) var held: Set<String> = []
    private var consumed: Set<String> = []
    mutating func press(_ control: String) -> CornerTrigger? {
        guard Self.defaults[control] != nil, held.insert(control).inserted else { return nil }
        if !consumed.isEmpty { consumed.insert(control); return nil }
        for (pair, corner) in [(Set(["k10","k11"]),WindowCorner.topLeft), (Set(["k12","k11"]),.topRight), (Set(["k10","k9"]),.bottomLeft), (Set(["k12","k9"]),.bottomRight)] where pair.isSubset(of: held) {
            consumed.formUnion(held); return .corner(corner)
        }
        return nil
    }
    mutating func release(_ control: String) -> CornerTrigger? {
        guard held.remove(control) != nil else { return nil }
        let fire = !consumed.contains(control)
        if held.isEmpty { consumed.removeAll() }
        return fire ? .single(control) : nil
    }
    mutating func drain() -> [CornerTrigger] { held.sorted().compactMap { release($0) } }
    mutating func cancel() { held.removeAll(); consumed.removeAll() }
}

/// Brief release grace also supports pads whose firmware emits short key pulses.
/// Held pairs work in either order; quick taps retain every single invocation.
final class CornerInput {
    private var state = CornerChordState()
    private var pending: [String:DispatchWorkItem] = [:]
    private var tokens: [String:UUID] = [:]
    var onTrigger: ((CornerTrigger) -> Void)?
    var held: Set<String> { state.held }
    func press(_ control: String) {
        if let old = pending.removeValue(forKey:control) { tokens.removeValue(forKey:control); old.cancel(); if let t = state.release(control) { onTrigger?(t) } }
        if let t = state.press(control) { onTrigger?(t) }
    }
    func release(_ control: String) {
        pending[control]?.cancel()
        let token = UUID(); tokens[control] = token
        let task = DispatchWorkItem { [weak self] in
            guard let self = self, self.tokens[control] == token else { return }
            self.tokens.removeValue(forKey:control)
            self.pending.removeValue(forKey:control)
            if let t = self.state.release(control) { self.onTrigger?(t) }
        }
        pending[control] = task
        DispatchQueue.main.asyncAfter(deadline:.now()+0.14,execute:task)
    }
    func drain() { pending.values.forEach { $0.cancel() }; pending.removeAll(); tokens.removeAll(); for t in state.drain() { onTrigger?(t) } }
    func cancel() { pending.values.forEach { $0.cancel() }; pending.removeAll(); tokens.removeAll(); state.cancel() }
}
