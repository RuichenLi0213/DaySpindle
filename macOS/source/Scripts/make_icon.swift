// Renders the 1024×1024 DaySpindle icon in a light or dark style: a rounded square
// with a faint day grid, a red "today" spindle, and colored task bars wound around it.
// Usage: swift Scripts/make_icon.swift <output.png> [light|dark]
import AppKit

let size: CGFloat = 1024
let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "icon_1024.png"
let dark = args.count > 2 && args[2] == "dark"

func color(_ hex: String, _ alpha: CGFloat = 1) -> NSColor {
    let v = UInt32(hex.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}

let palette = dark
    ? (top: "#2E2E33", bottom: "#18181B", grid: "#36363C", column: "#40292A", spindle: "#FF5A5F",
       spindleShade: "#C93C42", edge: color("#FFFFFF", 0.10), stub: color("#FFFFFF", 0.80))
    : (top: "#FFFFFF", bottom: "#ECEEF2", grid: "#E1E3E8", column: "#FFE7E3", spindle: "#E5484D",
       spindleShade: "#B8323A", edge: color("#000000", 0.08), stub: color("#FFFFFF", 0.85))

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824×824 body centered in a 1024 canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185
let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.45 : 0.28)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
color(palette.bottom).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(starting: color(palette.top), ending: color(palette.bottom))!.draw(in: body, angle: -90)

// Day grid and the soft Today column behind the spindle.
let cols = 6
let colW = body.width / CGFloat(cols)
let spindleX = body.minX + 3.5 * colW
color(palette.column).setFill()
NSBezierPath(roundedRect: NSRect(x: spindleX - colW / 2, y: body.minY - 40, width: colW, height: body.height + 80),
             xRadius: 30, yRadius: 30).fill()
for i in 1..<cols where i != 3 && i != 4 {
    color(palette.grid).setFill()
    NSRect(x: body.minX + CGFloat(i) * colW - 2, y: body.minY, width: 4, height: body.height).fill()
}

// The spindle: a rod with a round knob on top and a tapered tip.
let rodW: CGFloat = 30
let rodTop = body.maxY - 150, rodBottom = body.minY + 120
func drawRod(from y0: CGFloat, to y1: CGFloat) {
    let r = NSRect(x: spindleX - rodW / 2, y: y0, width: rodW, height: y1 - y0)
    NSGradient(starting: color(palette.spindle), ending: color(palette.spindleShade))!
        .draw(in: NSBezierPath(rect: r), angle: 0)
}
drawRod(from: rodBottom + 40, to: rodTop)
let tip = NSBezierPath()
tip.move(to: NSPoint(x: spindleX - rodW / 2, y: rodBottom + 41))
tip.line(to: NSPoint(x: spindleX + rodW / 2, y: rodBottom + 41))
tip.line(to: NSPoint(x: spindleX, y: rodBottom - 30))
tip.close()
color(palette.spindleShade).setFill()
tip.fill()
let knob: CGFloat = 92
NSGradient(starting: color(palette.spindle), ending: color(palette.spindleShade))!
    .draw(in: NSBezierPath(ovalIn: NSRect(x: spindleX - knob / 2, y: rodTop - 10, width: knob, height: knob)), angle: -60)

// Task bars ("threads"). The middle one passes behind the spindle, as if wound around it.
let barH: CGFloat = 92
let bars: [(hex: String, from: CGFloat, to: CGFloat, y: CGFloat)] = [
    ("#2F6FEB", 0.6, 4.7, 610),
    ("#30A46C", 2.0, 5.55, 455),
    ("#F2811D", 1.1, 4.25, 300),
]
for (n, b) in bars.enumerated() {
    let r = NSRect(x: body.minX + b.from * colW, y: body.minY + b.y - barH / 2, width: (b.to - b.from) * colW, height: barH)
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.35 : 0.18)
    s.shadowBlurRadius = 10
    s.shadowOffset = NSSize(width: 0, height: -4)
    s.set()
    color(b.hex).setFill()
    NSBezierPath(roundedRect: r, xRadius: 26, yRadius: 26).fill()
    NSGraphicsContext.restoreGraphicsState()
    palette.stub.setFill()
    NSBezierPath(roundedRect: NSRect(x: r.minX + 32, y: r.midY - 9, width: min(140, r.width * 0.32), height: 18),
                 xRadius: 9, yRadius: 9).fill()
    if n == 1 {
        // Spindle drawn over this bar.
        NSGraphicsContext.saveGraphicsState()
        let s2 = NSShadow()
        s2.shadowColor = NSColor.black.withAlphaComponent(0.25)
        s2.shadowBlurRadius = 6
        s2.set()
        drawRod(from: r.minY - 6, to: r.maxY + 6)
        NSGraphicsContext.restoreGraphicsState()
    }
}
NSGraphicsContext.restoreGraphicsState()

// Hairline edge.
palette.edge.setStroke()
let edge = NSBezierPath(roundedRect: body.insetBy(dx: 1, dy: 1), xRadius: radius - 1, yRadius: radius - 1)
edge.lineWidth = 2
edge.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
