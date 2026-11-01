import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Pad {
    static let amber = Color(hex: 0x8ECEAD)
    static let amberDim = Color(hex: 0x8A9D90)
    static let clash = Color(hex: 0xFF6B5B)
    static let bodyTop = Color(hex: 0x344A3D)
    static let bodyBottom = Color(hex: 0x203027)
    static let well = Color(hex: 0x111C16)
    static let capHi = Color(hex: 0x405549)
    static let capMid = Color(hex: 0x32453A)
    static let capLo = Color(hex: 0x293B31)
    static let aspect: CGFloat = 400.0 / 735.0
}

/// The pad's outline: chamfered top corners, slightly clipped bottom corners.
struct ChamferShape: Shape {
    func path(in r: CGRect) -> Path {
        let tx = r.width * 0.07, ty = r.height * 0.038
        let bx = r.width * 0.035, by = r.height * 0.03
        var p = Path()
        p.move(to: CGPoint(x: r.minX + tx, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tx, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + ty))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - by))
        p.addLine(to: CGPoint(x: r.maxX - bx, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + bx, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - by))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + ty))
        p.closeSubpath()
        return p
    }
}

struct PadView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let u = geo.size.width / 100
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                // the two buttons on the left side
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(hex: 0x1E2023))
                    .frame(width: 1.8 * u, height: h * 0.08)
                    .offset(x: -1.2 * u, y: h * 0.21)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(hex: 0x1E2023))
                    .frame(width: 1.8 * u, height: h * 0.05)
                    .offset(x: -1.2 * u, y: h * 0.33)

                ChamferShape()
                    .fill(LinearGradient(colors: [Pad.bodyTop, Pad.bodyBottom], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 12)

                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        KnobColumn(knob: "L", u: u).frame(maxWidth: .infinity)
                        LEDsView(u: u).frame(width: 15 * u)
                        KnobColumn(knob: "R", u: u).frame(maxWidth: .infinity)
                    }
                    VStack(spacing: 3.2 * u) {
                        ForEach(0..<4, id: \.self) { row in
                            HStack(spacing: 3 * u) {
                                ForEach(0..<3, id: \.self) { col in
                                    KeyCapView(id: "k\(row * 3 + col + 1)", u: u)
                                }
                            }
                        }
                    }
                    .padding(.top, 3 * u)
                }
                .padding(EdgeInsets(top: 6.5 * u, leading: 6.5 * u, bottom: 6 * u, trailing: 6.5 * u))
                .frame(width: geo.size.width, height: h)
            }
        }
        .aspectRatio(Pad.aspect, contentMode: .fit)
    }
}

struct LEDsView: View {
    let u: CGFloat
    var body: some View {
        VStack(spacing: 6 * u) {
            HStack(spacing: 2.6 * u) {
                RoundedRectangle(cornerRadius: 0.8 * u).fill(Color(hex: 0x9DA3AA).opacity(0.7)).frame(width: 1.9 * u, height: 4 * u)
                RoundedRectangle(cornerRadius: 0.8 * u).fill(Color(hex: 0xFF4134)).frame(width: 1.9 * u, height: 4 * u)
                    .shadow(color: Color(hex: 0xFF4134).opacity(0.8), radius: 1.6 * u)
            }
            HStack(spacing: 1.6 * u) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 0.6 * u)
                        .fill(Color(hex: 0xC9CDD2).opacity(i == 0 ? 1 : 0.5))
                        .frame(width: 1.2 * u, height: 3.4 * u)
                }
            }
        }
        .padding(.top, 9 * u)
    }
}

struct KnobView: View {
    let angle: Double
    let u: CGFloat
    let highlighted: Bool

    private static let knurl: [Color] = (0..<120).map { $0 % 2 == 0 ? Color(hex: 0x141518) : Color(hex: 0x2B2D32) }
    private static let metalHex: [UInt32] = [0x1D1F23, 0x5A5F66, 0x23262A, 0x686D74, 0x1D1F23, 0x555A61, 0x202327, 0x61666D, 0x1D1F23]
    private static let metal: [Color] = metalHex.map { Color(hex: $0) }

    var body: some View {
        let size = 31 * u
        let inset = 2.2 * u
        ZStack {
            Circle().fill(AngularGradient(gradient: Gradient(colors: KnobView.knurl), center: .center))
            Circle()
                .fill(AngularGradient(gradient: Gradient(colors: KnobView.metal), center: .center, angle: .degrees(20)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.45 * u))
                .padding(inset)
            Capsule()
                .fill(Color(white: 0.95))
                .frame(width: 1.1 * u, height: 6.5 * u)
                .offset(y: -(size / 2 - inset - 4.4 * u))
                .rotationEffect(.degrees(angle))
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: angle)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.55), radius: 0, x: 0, y: 1.2 * u)
        .overlay(
            Circle()
                .stroke(Pad.amber, lineWidth: 0.8 * u)
                .padding(-1.9 * u)
                .opacity(highlighted ? 1 : 0)
        )
        .contentShape(Circle())
    }
}

struct LearnDot: View {
    let learned: Bool
    let clash: Bool
    let size: CGFloat
    var body: some View {
        Group {
            if clash {
                Circle().fill(Pad.clash)
            } else if learned {
                Circle().fill(Pad.amber)
            } else {
                Circle().strokeBorder(Pad.amber, lineWidth: max(1, size * 0.2))
            }
        }
        .frame(width: size, height: size)
    }
}

struct KnobColumn: View {
    @EnvironmentObject var model: AppModel
    let knob: String
    let u: CGFloat

    var body: some View {
        let selected = model.selection == knob
        let target = model.learnTargetID.map { Controls.info($0).knob == knob } ?? false
        VStack(spacing: 2.4 * u) {
            Button {
                model.select(knob)
            } label: {
                KnobView(angle: model.knobAngle[knob] ?? -28, u: u, highlighted: selected || target)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(knob == "L" ? "Left knob" : "Right knob")
            KnobLegend(knob: knob, u: u)
        }
    }
}

struct KnobLegend: View {
    @EnvironmentObject var model: AppModel
    let knob: String
    let u: CGFloat

    private func symbol(_ id: String) -> String {
        if id.hasSuffix("ccw") { return "↺" }
        if id.hasSuffix("cw") { return "↻" }
        return "Press:"
    }

    var body: some View {
        let clashes = model.clashes
        let ids = [knob + "ccw", knob + "cw", knob + "press"].filter { model.settings.mapping($0).action != nil }
        VStack(spacing: 0.7 * u) {
            if ids.isEmpty {
                Text("Not set").foregroundColor(Pad.amberDim)
            }
            ForEach(ids, id: \.self) { id in
                let m = model.settings.mapping(id)
                HStack(spacing: 0.9 * u) {
                    LearnDot(learned: m.source != nil, clash: clashes[id] != nil, size: 1.6 * u)
                    Text("\(symbol(id)) \(m.action.map { Actions.cap(for: $0).cap } ?? "")")
                        .lineLimit(1)
                }
                .foregroundColor(Pad.amber)
            }
        }
        .font(.system(size: 3.3 * u, weight: .semibold).width(.condensed))
        .frame(minHeight: 9 * u, alignment: .top)
    }
}

struct KeyCapView: View {
    @EnvironmentObject var model: AppModel
    let id: String
    let u: CGFloat

    var body: some View {
        let m = model.settings.mapping(id)
        let highlighted = model.selection == id || model.learnTargetID == id
        let clash = model.clashes[id] != nil
        let number = Controls.info(id).keyNumber ?? 0
        Button {
            model.select(id)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 2.4 * u).fill(Pad.well)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 1.9 * u)
                        .fill(LinearGradient(colors: [Pad.capHi, Pad.capMid, Pad.capLo], startPoint: .top, endPoint: .bottom))
                        .shadow(color: Color(hex: 0x232528), radius: 0, x: 0, y: 0.9 * u)
                    VStack(spacing: 0.6 * u) {
                        if let action = m.action {
                            let cap = Actions.cap(for: action)
                            if let action = GroveAction.from(m.action) {
                                GroveArtwork(action: action).frame(width: 21 * u, height: 18 * u)
                                    .clipShape(RoundedRectangle(cornerRadius: 2 * u))
                            } else if let name = WindowArtwork.names[action.id] {
                                GroveArtwork(name: name).frame(width: 21 * u, height: 18 * u)
                                    .clipShape(RoundedRectangle(cornerRadius: 2 * u))
                            } else if let glyph = cap.glyph {
                                Text(glyph).font(.system(size: 6 * u))
                            }
                            Text(cap.cap)
                                .font(.system(size: 3.3 * u, weight: .semibold).width(.condensed))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.6)
                        } else {
                            Text("\(number)")
                                .font(.system(size: 3.4 * u))
                                .foregroundColor(Pad.amberDim)
                        }
                    }
                    .foregroundColor(Pad.amber)
                    .padding(1.4 * u)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if m.action != nil {
                        Text("\(number)").font(.system(size: 2.7 * u, weight: .bold, design: .rounded))
                            .foregroundColor(GroveTheme.muted).padding(1.6 * u)
                    }
                    if m.action != nil || m.source != nil {
                        LearnDot(learned: m.source != nil, clash: clash, size: 1.6 * u)
                            .padding(1.6 * u)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(EdgeInsets(top: 1.3 * u, leading: 1.3 * u, bottom: 2.3 * u, trailing: 1.3 * u))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 2.8 * u)
                    .stroke(Pad.amber, lineWidth: 0.8 * u)
                    .padding(-0.9 * u)
                    .opacity(highlighted ? 1 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("\(Controls.capitalized(Controls.info(id).name)): \(m.action.map { Actions.describe($0) } ?? "nothing assigned")")
    }
}
