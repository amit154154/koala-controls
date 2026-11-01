import AppKit

/// The nine opponents follow the reference image, row by row.
enum CompanionMob: String, CaseIterable, Codable {
  case greenSnail, blueSnail, redSnail, slime, orangeMushroom, pointyMushroom, stump, pig, purpleMob
  var index: Int { Self.allCases.firstIndex(of: self)! }
  var title: String {
    [
      "Green snail", "Blue snail", "Red snail", "Green slime", "Orange mushroom", "Pointy mushroom",
      "Stump", "Pig", "Purple horned mob",
    ][index]
  }
}
enum BasketballShot: String { case swish, miss, dunk }
struct CompanionReaction: Equatable {
  let style: CompanionStyle
  var tier = 0
  var rare = false
  var mob = CompanionMob.slime
  var shot = BasketballShot.swish
  var duration: TimeInterval {
    style.duration + (rare && ![.left, .fill, .right, .topLeft, .topRight, .bottomLeft, .bottomRight, .basketball].contains(style) ? 0.10 : 0)
  }
  var description: String {
    if style == .battle { return (rare ? "Critical hit · " : "Battle · ") + mob.title }
    if style == .basketball { return shot.rawValue.capitalized }
    return (rare ? "Rare · " : "") + style.title
  }
}
struct CompanionSelector {
  private var sinceRare = 3
  private var opponents: [CompanionMob] = []
  /// Each random opponent appears once per bag. Other actions never consume it.
  mutating func next(
    style: CompanionStyle, preferences: CompanionPreferences,
    rareRoll: Double = Double.random(in: 0..<1), shotRoll: Double = Double.random(in: 0..<1)
  ) -> CompanionReaction {
    let rare = preferences.rareAnimations && sinceRare >= 3 && rareRoll < 0.08
    sinceRare = rare ? 0 : sinceRare + 1
    var result = CompanionReaction(style: style, rare: rare)
    if style == .basketball { result.shot = rare ? .dunk : (shotRoll < 0.25 ? .miss : .swish) }
    if style == .battle {
      if let selected = CompanionMob(rawValue: preferences.opponent) {
        result.mob = selected
      } else {
        if opponents.isEmpty { opponents = CompanionMob.allCases.shuffled() }
        result.mob = opponents.removeLast()
      }
    }
    return result
  }
}

/// Tiny, self-contained scenes. They draw immediately and never hold up the shortcut.
enum CompanionScenes {
  static let mint = CompanionDrawing.mint
  static let gold = CompanionDrawing.gold
  static let ink = NSColor(calibratedRed: 0.07, green: 0.12, blue: 0.10, alpha: 1)
  static let cream = NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.88, alpha: 1)
  static func curve(_ p: Double, _ points: [(Double, Double)]) -> Double {
    CompanionPlan.interpolate(p, points)
  }
  static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
  static func ease(_ x: Double) -> Double {
    let t = clamp(x)
    return t * t * (3 - 2 * t)
  }

  static func draw(
    _ reaction: CompanionReaction, progress: Double, reducedMotion: Bool,
    mascot: NSImage, mobs: NSImage?, poses: NSImage?, in rect: CGRect
  ) {
    guard let c = NSGraphicsContext.current?.cgContext else { return }
    c.saveGState()
    defer { c.restoreGState() }
    c.scaleBy(x: rect.width / 240, y: rect.height / 190)
    let p = clamp(progress)
    c.setAlpha(curve(p, [(0, 0), (0.10, 1), (0.88, 1), (1, 0)]))
    if reducedMotion {
      koala(c, mascot: mascot, poses: nil, pose: nil, x: 120, y: 32, size: 100)
      badge(c, text: reaction.style == .basketball ? "●" : "✦", x: 158, y: 112, color: mint)
      return
    }
    func bear(
      _ x: Double, _ y: Double, _ size: Double = 100, _ pose: Int? = nil, _ tilt: Double = 0
    ) {
      koala(c, mascot: mascot, poses: poses, pose: pose, x: x, y: y, size: size, tilt: tilt)
    }
    switch reaction.style {
    case .basketball:
      basketball(c, reaction: reaction, p: p, mascot: mascot, poses: poses)
    case .battle:
      battle(c, reaction: reaction, p: p, mascot: mascot, poses: poses, mobs: mobs)
    case .connect:
      let portal = ease(p / 0.25)
      ellipse(
        c, CGRect(x: 142 - 23 * portal, y: 32, width: 46 * portal, height: 108),
        stroke: reaction.rare ? gold : mint, width: 3)
      ellipse(
        c, CGRect(x: 147 - 17 * portal, y: 40, width: 34 * portal, height: 92),
        stroke: mint.withAlphaComponent(0.35), width: 2)
      let travel = ease((p - 0.10) / 0.56)
      bear(49 + 100 * travel, 33 + 13 * sin(.pi * travel), 95 * (1 - 0.64 * travel))
      if p > 0.65 { bear(166, 30, 90 * ease((p - 0.65) / 0.18), 2) }
      if reaction.rare { burst(c, x: 148, y: 90, p: p, color: gold, count: 10) }
    case .viz:
      bear(59, 30 + 7 * sin(.pi * p), 92, p > 0.6 ? 2 : nil)
      window(c, CGRect(x: 108, y: 47, width: 103, height: 87))
      for i in 0..<3 {
        let growth = ease((p - Double(i) * 0.10) / 0.46)
        let h = Double(22 + i * 17) * growth
        rounded(
          c, CGRect(x: 123 + Double(i) * 25, y: 57, width: 15, height: h), radius: 3,
          fill: i == 2 ? gold : mint)
        if reaction.rare && p > 0.50 {
          flower(c, x: 130 + Double(i) * 25, y: 57 + h, scale: ease((p - 0.50) / 0.20))
        }
      }
    case .notes:
      bear(69, 31, 98, nil, -0.04 * sin(p * .pi))
      rounded(c, CGRect(x: 47, y: 43, width: 49, height: 35), radius: 4, fill: cream, stroke: mint)
      line(c, [CGPoint(x: 72, y: 45), CGPoint(x: 72, y: 75)], color: ink.withAlphaComponent(0.4))
      let t = ease((p - 0.16) / 0.66)
      let x = 95 + t * 110
      let y = 79 + sin(t * .pi / 2) * 74
      c.saveGState()
      c.translateBy(x: x, y: y)
      c.rotate(by: 0.2 + t * 0.3)
      polygon(
        c,
        [
          CGPoint(x: -17, y: -8), CGPoint(x: 18, y: 5), CGPoint(x: -9, y: 10), CGPoint(x: -5, y: 0),
        ], fill: cream, stroke: mint)
      line(c, [CGPoint(x: -5, y: 0), CGPoint(x: 18, y: 5)], color: mint)
      c.restoreGState()
      if reaction.rare {
        for i in 0..<4 {
          heart(
            c, x: x - Double(i) * 17 - 20, y: y - Double(i) * 9, size: 6 * sin(.pi * p), color: gold
          )
        }
      }
    case .focus:
      bear(120, 38, 111, nil, sin(p * 12) * 0.025)
      window(c, CGRect(x: 72, y: 29, width: 96, height: 58))
      text("‹ / ›", at: CGPoint(x: 91, y: 44), size: 24, color: mint)
      line(c, [CGPoint(x: 66, y: 28), CGPoint(x: 174, y: 28)], color: gold, width: 3)
      if reaction.rare {
        let t = ease((p - 0.3) / 0.6)
        let x = 148 + t * 57
        let y = 79 + t * 79
        c.saveGState()
        c.translateBy(x: x, y: y)
        c.rotate(by: -0.4)
        polygon(
          c, [CGPoint(x: -7, y: 0), CGPoint(x: 0, y: 24), CGPoint(x: 7, y: 0)], fill: cream,
          stroke: mint)
        polygon(
          c,
          [
            CGPoint(x: -4, y: 0), CGPoint(x: 0, y: -14 * (0.7 + 0.3 * sin(p * 40))),
            CGPoint(x: 4, y: 0),
          ], fill: gold)
        c.restoreGState()
      } else {
        for i in 0..<3 where p > Double(i) * 0.15 {
          sparkle(
            c, x: 178 + Double(i % 2) * 9, y: 80 + Double(i) * 17, r: 3 * sin(.pi * p), color: mint)
        }
      }
    case .setup:
      bear(120, 19, 92, 2, sin(p * 8) * 0.04)
      for i in 0..<3 {
        let x = Double(45 + i * 75)
        let t = ease((p - Double(i) * 0.1) / 0.45)
        let y = 122 + (1 - t) * (i % 2 == 0 ? 30 : -18)
        c.saveGState()
        c.translateBy(x: x, y: y)
        c.rotate(by: (1 - t) * Double(i - 1) * 0.35)
        window(c, CGRect(x: -27, y: -15, width: 54, height: 38))
        line(c, [CGPoint(x: -12, y: -20), CGPoint(x: 12, y: -20)], color: mint, width: 2)
        if t > 0.9 { checkmark(c, x: -5, y: 0, color: gold) }
        c.restoreGState()
      }
      if reaction.rare { burst(c, x: 120, y: 104, p: p, color: gold, count: 12) }
    case .duo:
      let bump = sin(.pi * clamp((p - 0.12) / 0.7))
      bear(72 + 16 * bump, 30 + 12 * bump, 96, 2, -0.08 * bump)
      bear(168 - 16 * bump, 30 + 12 * bump, 96, 2, 0.08 * bump)
      bubble(c, CGRect(x: 36, y: 126, width: 46, height: 27), label: "{ }")
      bubble(c, CGRect(x: 159, y: 126, width: 46, height: 27), label: "✦")
      if reaction.rare && p > 0.38 {
        bear(120, 24, 67 * ease((p - 0.38) / 0.20), 2)
        heart(c, x: 120, y: 142, size: 10 * sin(.pi * p), color: gold)
      } else {
        sparkle(c, x: 120, y: 88, r: 10 * sin(.pi * p), color: gold)
      }
    case .minimize:
      let tuck = ease((p - 0.12) / 0.56)
      rounded(
        c, CGRect(x: 68, y: 23, width: 104, height: 22), radius: 8,
        fill: ink.withAlphaComponent(0.8), stroke: mint)
      bear(
        120, 39 - 11 * tuck, 105 * (1 - tuck) + 17 * tuck, p > 0.22 ? 5 : nil, -0.15 * sin(p * .pi))
      if reaction.rare && p > 0.68 {
        c.saveGState()
        c.clip(to: CGRect(x: 60, y: 39, width: 120, height: 130))
        bear(120, 2 + 20 * sin(.pi * clamp((p - 0.68) / 0.32)), 70)
        c.restoreGState()
      }
      line(c, [CGPoint(x: 82, y: 44), CGPoint(x: 158, y: 44)], color: gold, width: 2)
    case .guide:
      bear(65, 32, 90)
      let unfold = ease(p / 0.35)
      let w = 98 * unfold
      rounded(
        c, CGRect(x: 158 - w / 2, y: 54, width: w, height: 73), radius: 3, fill: cream, stroke: gold
      )
      if unfold > 0.8 {
        line(
          c,
          [
            CGPoint(x: 126, y: 69), CGPoint(x: 145, y: 90), CGPoint(x: 166, y: 77),
            CGPoint(x: 187, y: 107),
          ], color: ink.withAlphaComponent(0.5), width: 2, dashed: true)
        text("×", at: CGPoint(x: 179, y: 97), size: 21, color: reaction.rare ? gold : mint)
      }
      if reaction.rare && p > 0.40 {
        burst(c, x: 186, y: 109, p: (p - 0.4) / 0.6, color: gold, count: 9)
      }
    default: break
    }
  }

  static func basketball(
    _ c: CGContext, reaction: CompanionReaction, p: Double, mascot: NSImage, poses: NSImage?
  ) {
    let dunk = reaction.shot == .dunk
    // Backboard, rim and a net that stretches after a made shot.
    rounded(c, CGRect(x: 199, y: 110, width: 7, height: 48), radius: 2, fill: cream)
    let netPull = reaction.shot == .miss ? 0 : 8 * sin(.pi * clamp((p - 0.6) / 0.26))
    for i in 0...4 {
      let x = 165 + Double(i) * 7
      line(
        c, [CGPoint(x: x, y: 122), CGPoint(x: 174 + Double(i) * 3, y: 99 - netPull)],
        color: cream.withAlphaComponent(0.85), width: 1)
    }
    line(
      c, [CGPoint(x: 169, y: 112), CGPoint(x: 191, y: 112)], color: cream.withAlphaComponent(0.65),
      width: 1)
    ellipse(c, CGRect(x: 163, y: 120, width: 33, height: 7), stroke: gold, width: 3)
    var bx = 82.0
    var by = 90.0
    if dunk {
      let leap = ease((p - 0.1) / 0.46)
      let x = 46 + 98 * leap
      let y = 30 + sin(leap * .pi) * 55 + 26 * leap
      koala(
        c, mascot: mascot, poses: poses, pose: p < 0.18 ? 0 : 1, x: x, y: y, size: 99, tilt: -0.1)
      bx = x + 39
      by = y + 73
      if p > 0.57 {
        bx = 180
        by = 125 - 74 * ease((p - 0.57) / 0.29)
      }
    } else {
      let pose = p < 0.23 ? 0 : (p > 0.72 && reaction.shot == .swish ? 2 : 1)
      koala(
        c, mascot: mascot, poses: poses, pose: pose, x: 53, y: 29 + 8 * sin(.pi * clamp(p / 0.6)),
        size: 103, tilt: reaction.shot == .miss && p > 0.72 ? -0.12 : 0)
      let t = clamp((p - 0.21) / 0.41)
      bx = 82 + 98 * t
      by = 90 + 35 * t + 66 * 4 * t * (1 - t)
      if p > 0.62 {
        let fall = clamp((p - 0.62) / 0.27)
        if reaction.shot == .miss {
          bx = 180 + 45 * fall
          by = 125 + 22 * sin(.pi * fall) - 66 * fall
        } else {
          bx = 180
          by = 125 - 76 * fall
        }
      }
    }
    ball(c, x: bx, y: by, r: 9, rotation: p * 5)
    if p > 0.72 {
      let label = dunk ? "DUNK!" : (reaction.shot == .miss ? "oops!" : "SWISH!")
      text(label, at: CGPoint(x: 144, y: 39), size: 13, color: dunk ? gold : mint)
      if dunk { burst(c, x: 181, y: 126, p: clamp((p - 0.57) / 0.43), color: gold, count: 9) }
    }
  }
  static func battle(
    _ c: CGContext, reaction: CompanionReaction, p: Double, mascot: NSImage, poses: NSImage?,
    mobs: NSImage?
  ) {
    let hit = clamp((p - 0.43) / 0.48)
    let dash = curve(p, [(0, 0), (0.22, -6), (0.44, 30), (0.64, 27), (0.88, 0), (1, 0)])
    let pose = p < 0.39 ? 3 : (p < 0.72 ? 4 : 2)
    koala(
      c, mascot: mascot, poses: poses, pose: pose, x: 54 + dash, y: 27 + 8 * sin(.pi * p),
      size: 106, tilt: -0.06 * sin(.pi * p))
    let enemyX = 172 + 27 * sin(hit * .pi / 2)
    c.saveGState()
    c.translateBy(x: enemyX, y: 36 + 23 * sin(.pi * hit))
    c.rotate(by: -0.27 * sin(.pi * hit))
    let shrink = 1 - 0.65 * ease((p - 0.76) / 0.22)
    c.scaleBy(x: shrink, y: shrink)
    if let mobs = mobs {
      atlas(
        mobs, index: reaction.mob.index, columns: 3, rows: 3,
        in: CGRect(x: -40, y: 0, width: 80, height: 80))
    } else {
      ellipse(c, CGRect(x: -29, y: 0, width: 58, height: 52), fill: mint, stroke: ink, width: 2)
    }
    c.restoreGState()
    if p > 0.38 && p < 0.74 {
      let impact = sin(.pi * clamp((p - 0.38) / 0.36))
      sparkle(c, x: 142, y: 78, r: 23 * impact, color: reaction.rare ? gold : cream)
      for i in 0..<3 {
        let angle = Double(i) * 0.65 - 0.65
        line(
          c,
          [
            CGPoint(x: 145 + cos(angle) * 23, y: 78 + sin(angle) * 23),
            CGPoint(x: 145 + cos(angle) * 37, y: 78 + sin(angle) * 37),
          ], color: gold.withAlphaComponent(impact), width: 2)
      }
    }
    if p > 0.62 {
      if reaction.rare {
        text("CRIT!", at: CGPoint(x: 150, y: 137), size: 14, color: gold)
        burst(c, x: enemyX, y: 77, p: clamp((p - 0.62) / 0.38), color: gold, count: 11)
      } else {
        sparkle(c, x: enemyX - 10, y: 122, r: 5 * sin(.pi * hit), color: mint)
        sparkle(c, x: enemyX + 9, y: 132, r: 4 * sin(.pi * hit), color: gold)
      }
    }
  }

  static func koala(
    _ c: CGContext, mascot: NSImage, poses: NSImage?, pose: Int?, x: Double, y: Double,
    size: Double, tilt: Double = 0
  ) {
    c.saveGState()
    defer { c.restoreGState() }
    c.translateBy(x: x, y: y)
    c.rotate(by: tilt)
    if let poses = poses, let pose = pose {
      atlas(
        poses, index: pose, columns: 3, rows: 2,
        in: CGRect(x: -size / 2, y: 0, width: size, height: size))
    } else {
      mascot.draw(
        in: CGRect(x: -size / 2, y: 0, width: size, height: size), from: .zero,
        operation: .sourceOver, fraction: 1)
    }
  }
  static func atlas(_ image: NSImage, index: Int, columns: Int, rows: Int, in rect: CGRect) {
    let w = image.size.width / Double(columns)
    let h = image.size.height / Double(rows)
    // The mallet extends slightly across the last cell boundary; keep it with
    // its owner, and exclude that transparent-margin overlap from the tuck pose.
    let extra = columns == 3 && rows == 2 && index == 4 ? w * 0.060 : 0
    let inset = columns == 3 && rows == 2 && index == 5 ? w * 0.075 : 0
    let source = CGRect(
      x: Double(index % columns) * w + inset, y: image.size.height - Double(index / columns + 1) * h,
      width: w + extra - inset, height: h)
    image.draw(
      in: rect, from: source, operation: .sourceOver, fraction: 1, respectFlipped: false,
      hints: [.interpolation: NSImageInterpolation.high.rawValue])
  }
  static func rounded(
    _ c: CGContext, _ rect: CGRect, radius: Double, fill: NSColor? = nil, stroke: NSColor? = nil,
    width: Double = 1.5
  ) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if let fill = fill {
      c.setFillColor(fill.cgColor)
      c.addPath(path)
      c.fillPath()
    }
    if let stroke = stroke {
      c.setStrokeColor(stroke.cgColor)
      c.setLineWidth(width)
      c.addPath(path)
      c.strokePath()
    }
  }
  static func ellipse(
    _ c: CGContext, _ rect: CGRect, fill: NSColor? = nil, stroke: NSColor? = nil,
    width: Double = 1.5
  ) {
    if let fill = fill {
      c.setFillColor(fill.cgColor)
      c.fillEllipse(in: rect)
    }
    if let stroke = stroke {
      c.setStrokeColor(stroke.cgColor)
      c.setLineWidth(width)
      c.strokeEllipse(in: rect)
    }
  }
  static func line(
    _ c: CGContext, _ points: [CGPoint], color: NSColor, width: Double = 1.5, dashed: Bool = false
  ) {
    guard let first = points.first else { return }
    c.saveGState()
    defer { c.restoreGState() }
    c.setStrokeColor(color.cgColor)
    c.setLineWidth(width)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    if dashed { c.setLineDash(phase: 0, lengths: [3, 4]) }
    c.move(to: first)
    for point in points.dropFirst() { c.addLine(to: point) }
    c.strokePath()
  }
  static func polygon(_ c: CGContext, _ points: [CGPoint], fill: NSColor, stroke: NSColor? = nil) {
    guard let first = points.first else { return }
    c.beginPath()
    c.move(to: first)
    for point in points.dropFirst() { c.addLine(to: point) }
    c.closePath()
    c.setFillColor(fill.cgColor)
    if let stroke = stroke {
      c.setStrokeColor(stroke.cgColor)
      c.setLineWidth(1.5)
      c.drawPath(using: .fillStroke)
    } else {
      c.fillPath()
    }
  }
  static func window(_ c: CGContext, _ frame: CGRect) {
    rounded(c, frame, radius: 5, fill: ink.withAlphaComponent(0.8), stroke: mint)
    for i in 0..<3 {
      ellipse(
        c, CGRect(x: frame.minX + 5 + Double(i) * 5, y: frame.maxY - 7, width: 2.5, height: 2.5),
        fill: i == 0 ? gold : mint)
    }
  }
  static func text(_ string: String, at point: CGPoint, size: Double, color: NSColor) {
    (string as NSString).draw(
      at: point,
      withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: color,
      ])
  }
  static func badge(_ c: CGContext, text string: String, x: Double, y: Double, color: NSColor) {
    ellipse(c, CGRect(x: x - 14, y: y - 14, width: 28, height: 28), fill: ink, stroke: color)
    text(string, at: CGPoint(x: x - 7, y: y - 9), size: 17, color: color)
  }
  static func bubble(_ c: CGContext, _ rect: CGRect, label: String) {
    rounded(c, rect, radius: 9, fill: ink.withAlphaComponent(0.85), stroke: mint)
    text(label, at: CGPoint(x: rect.minX + 10, y: rect.minY + 6), size: 13, color: gold)
  }
  static func checkmark(_ c: CGContext, x: Double, y: Double, color: NSColor) {
    line(
      c, [CGPoint(x: x - 4, y: y), CGPoint(x: x, y: y - 4), CGPoint(x: x + 9, y: y + 6)],
      color: color, width: 2)
  }
  static func sparkle(_ c: CGContext, x: Double, y: Double, r: Double, color: NSColor) {
    guard r > 0 else { return }
    polygon(
      c,
      [
        CGPoint(x: x, y: y + r), CGPoint(x: x + r * 0.32, y: y + r * 0.32), CGPoint(x: x + r, y: y),
        CGPoint(x: x + r * 0.32, y: y - r * 0.32), CGPoint(x: x, y: y - r),
        CGPoint(x: x - r * 0.32, y: y - r * 0.32), CGPoint(x: x - r, y: y),
        CGPoint(x: x - r * 0.32, y: y + r * 0.32),
      ], fill: color)
  }
  static func burst(_ c: CGContext, x: Double, y: Double, p: Double, color: NSColor, count: Int) {
    let t = clamp(p)
    for i in 0..<count {
      let a = Double(i) * Double.pi * 2 / Double(count)
      sparkle(
        c, x: x + cos(a) * (15 + 40 * t), y: y + sin(a) * (15 + 33 * t), r: 4 * sin(.pi * t),
        color: i % 2 == 0 ? color : mint)
    }
  }
  static func heart(_ c: CGContext, x: Double, y: Double, size: Double, color: NSColor) {
    guard size > 0 else { return }
    c.setFillColor(color.cgColor)
    c.move(to: CGPoint(x: x, y: y - size))
    c.addCurve(
      to: CGPoint(x: x, y: y + size * 0.45), control1: CGPoint(x: x - size * 2, y: y + size * 0.4),
      control2: CGPoint(x: x - size * 0.5, y: y + size * 1.6))
    c.addCurve(
      to: CGPoint(x: x, y: y - size), control1: CGPoint(x: x + size * 0.5, y: y + size * 1.6),
      control2: CGPoint(x: x + size * 2, y: y + size * 0.4))
    c.fillPath()
  }
  static func flower(_ c: CGContext, x: Double, y: Double, scale: Double) {
    for i in 0..<5 {
      let a = Double(i) * Double.pi * 2 / 5
      ellipse(
        c,
        CGRect(
          x: x + cos(a) * 6 * scale - 4, y: y + sin(a) * 6 * scale - 4, width: 8 * scale,
          height: 8 * scale), fill: mint)
    }
    ellipse(c, CGRect(x: x - 3, y: y - 3, width: 6, height: 6), fill: gold)
  }
  static func ball(_ c: CGContext, x: Double, y: Double, r: Double, rotation: Double) {
    c.saveGState()
    defer { c.restoreGState() }
    c.translateBy(x: x, y: y)
    c.rotate(by: rotation)
    ellipse(
      c, CGRect(x: -r, y: -r, width: r * 2, height: r * 2),
      fill: NSColor(calibratedRed: 1, green: 0.48, blue: 0.14, alpha: 1), stroke: ink, width: 1.3)
    c.addEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
    c.clip()
    line(c, [CGPoint(x: -r, y: 0), CGPoint(x: r, y: 0)], color: ink, width: 1)
    line(c, [CGPoint(x: 0, y: -r), CGPoint(x: 0, y: r)], color: ink, width: 1)
    ellipse(c, CGRect(x: -r * 1.8, y: -r, width: r * 1.5, height: 2 * r), stroke: ink, width: 1)
    ellipse(c, CGRect(x: r * 0.3, y: -r, width: r * 1.5, height: 2 * r), stroke: ink, width: 1)
  }
}
