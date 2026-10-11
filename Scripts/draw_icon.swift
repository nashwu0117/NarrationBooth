// Draws the NarrationBooth app icon (1024×1024 PNG, macOS icon grid: 824 pt squircle with a soft shadow).
// Usage: swift Scripts/draw_icon.swift <out.png> [A|B|C]
//   A = microphone whose grille is lines of script (the default icon)
//   B = teleprompter card with the camera dot above the text
//   C = waveform written as lines of text
import AppKit

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "icon.png"
let variant = args.count > 2 ? args[2] : "A"
let S: CGFloat = 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
let ink = rgb(244, 240, 232)          // warm off-white
let amber = rgb(250, 186, 64)
let red = rgb(242, 70, 61)

// squircle base with shadow
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)
ctx.saveGState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
rgb(20, 20, 24).setFill()
tilePath.fill()
ctx.restoreGState()

func fillTile(_ top: NSColor, _ bottom: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(starting: top, ending: bottom)!.draw(in: tile, angle: -90)
    // soft top highlight
    NSGradient(starting: NSColor.white.withAlphaComponent(0.07), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
}

func capsuleLine(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y - h / 2, width: w, height: h), xRadius: h / 2, yRadius: h / 2).fill()
}

func dot(_ c: CGPoint, _ r: CGFloat, _ color: NSColor, glow: Bool = false) {
    if glow {
        ctx.saveGState()
        let g = NSShadow()
        g.shadowColor = color.withAlphaComponent(0.8)
        g.shadowBlurRadius = r * 1.2
        g.set()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
        ctx.restoreGState()
    }
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
}

switch variant {
case "B":
    fillTile(rgb(232, 72, 60), rgb(176, 36, 40))
    let card = NSRect(x: 230, y: 250, width: 564, height: 470)
    ctx.saveGState()
    let s2 = NSShadow()
    s2.shadowColor = NSColor.black.withAlphaComponent(0.28)
    s2.shadowBlurRadius = 30
    s2.shadowOffset = NSSize(width: 0, height: -10)
    s2.set()
    rgb(22, 22, 26).setFill()
    NSBezierPath(roundedRect: card, xRadius: 54, yRadius: 54).fill()
    ctx.restoreGState()
    dot(CGPoint(x: 512, y: 780), 22, ink)            // the camera, above the text
    dot(CGPoint(x: 512, y: 780), 9, rgb(30, 30, 34))
    let lines: [(CGFloat, NSColor)] = [(380, ink), (300, ink), (420, ink.withAlphaComponent(0.45)), (250, ink.withAlphaComponent(0.45))]
    for (i, l) in lines.enumerated() {
        let y = 640 - CGFloat(i) * 92
        capsuleLine(x: 512 - l.0 / 2, y: y, w: l.0, h: 36, color: l.1)
    }
    capsuleLine(x: 512 + 380 / 2 - 70, y: 640, w: 70, h: 36, color: amber)
case "C":
    fillTile(rgb(36, 36, 42), rgb(14, 14, 17))
    let rows: [[CGFloat]] = [[40, 90, 140, 70, 180, 110, 60, 130, 80],
                             [120, 60, 200, 150, 90, 170, 50, 100],
                             [70, 160, 100, 60, 130, 90]]
    for (r, bars) in rows.enumerated() {
        let y = 640 - CGFloat(r) * 150
        var x: CGFloat = 250
        for (i, h) in bars.enumerated() {
            let color = (r == 1 && i == 2) ? amber : ink.withAlphaComponent(r == 2 ? 0.5 : 1)
            capsuleLine(x: x, y: y, w: 34, h: h * 0.6, color: color)
            x += 60
        }
    }
    dot(CGPoint(x: 760, y: 760), 34, red, glow: true)
default: // A: microphone whose grille is lines of script
    fillTile(rgb(38, 38, 44), rgb(14, 14, 17))
    let cap = NSRect(x: 362, y: 400, width: 300, height: 430)
    let capPath = NSBezierPath(roundedRect: cap, xRadius: 150, yRadius: 150)
    capPath.lineWidth = 30
    ink.setStroke()
    capPath.stroke()
    // script lines inside the capsule (the "grille")
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: cap.insetBy(dx: 26, dy: 26), xRadius: 124, yRadius: 124).addClip()
    let widths: [CGFloat] = [150, 200, 170, 120]
    for (i, w) in widths.enumerated() {
        let y = 735 - CGFloat(i) * 72
        capsuleLine(x: 512 - w / 2, y: y, w: w, h: 26, color: ink.withAlphaComponent(i == 3 ? 0.5 : 0.95))
    }
    NSGraphicsContext.restoreGraphicsState()
    // the breath mark on line 2, in amber
    capsuleLine(x: 512 + 200 / 2 - 52, y: 663, w: 52, h: 26, color: amber)
    // holder arc + stem + base
    let arc = NSBezierPath()
    arc.appendArc(withCenter: CGPoint(x: 512, y: 560), radius: 200, startAngle: 200, endAngle: 340)
    arc.lineWidth = 30
    arc.lineCapStyle = .round
    ink.setStroke()
    arc.stroke()
    ink.setFill()
    NSBezierPath(rect: NSRect(x: 497, y: 262, width: 30, height: 100)).fill()          // stem
    NSBezierPath(roundedRect: NSRect(x: 412, y: 248, width: 200, height: 30), xRadius: 15, yRadius: 15).fill()
    dot(CGPoint(x: 730, y: 790), 36, red, glow: true)                 // recording
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out) [\(variant)]")
