// Draws the app icon: an OBD-II connector under a live-signal trace on a dark squircle.
// Usage: swift make-icon.swift out.png   (1024×1024; make-icon.sh turns it into AppIcon.icns)
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Background squircle (Apple's grid: 824 pt tile centred in 1024, ~185 corner radius) with a soft shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(squircle); ctx.setFillColor(color(0x10203A)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
let bg = CGGradient(colorsSpace: nil, colors: [color(0x1E3D6B), color(0x0B1626)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// faint grid, like a scope screen
ctx.setStrokeColor(color(0xFFFFFF, 0.05)); ctx.setLineWidth(3)
for i in stride(from: 100.0, through: 924.0, by: 82.4) {
    ctx.move(to: CGPoint(x: i, y: 100)); ctx.addLine(to: CGPoint(x: i, y: 924))
    ctx.move(to: CGPoint(x: 100, y: i)); ctx.addLine(to: CGPoint(x: 924, y: i))
}
ctx.strokePath()
ctx.restoreGState()

// Signal trace across the upper half, with a glow.
let trace = CGMutablePath()
let base: CGFloat = 690
let pts: [(CGFloat, CGFloat)] = [(170, 0), (330, 0), (370, 60), (420, -110), (470, 150), (520, -40), (555, 0), (854, 0)]
trace.move(to: CGPoint(x: pts[0].0, y: base + pts[0].1))
for p in pts.dropFirst() { trace.addLine(to: CGPoint(x: p.0, y: base + p.1)) }
ctx.saveGState()
ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.setShadow(offset: .zero, blur: 30, color: color(0x3DE0C0, 0.9))
ctx.addPath(trace); ctx.setStrokeColor(color(0x3DE0C0)); ctx.setLineWidth(26); ctx.strokePath()
ctx.restoreGState()

// OBD-II (J1962) connector: a D-shaped trapezoid shell with two rows of 8 pins.
let shell = CGMutablePath()
let top: CGFloat = 520, bottom: CGFloat = 300, left: CGFloat = 230, right: CGFloat = 794, inset: CGFloat = 60
shell.move(to: CGPoint(x: left + 30, y: top))
shell.addLine(to: CGPoint(x: right - 30, y: top))
shell.addQuadCurve(to: CGPoint(x: right, y: top - 32), control: CGPoint(x: right, y: top))
shell.addLine(to: CGPoint(x: right - inset, y: bottom + 30))
shell.addQuadCurve(to: CGPoint(x: right - inset - 34, y: bottom), control: CGPoint(x: right - inset, y: bottom))
shell.addLine(to: CGPoint(x: left + inset + 34, y: bottom))
shell.addQuadCurve(to: CGPoint(x: left + inset, y: bottom + 30), control: CGPoint(x: left + inset, y: bottom))
shell.addLine(to: CGPoint(x: left, y: top - 32))
shell.addQuadCurve(to: CGPoint(x: left + 30, y: top), control: CGPoint(x: left, y: top))
shell.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x000000, 0.5))
ctx.addPath(shell)
ctx.setFillColor(color(0xE9EEF5)); ctx.fillPath()
ctx.restoreGState()
// recessed face
ctx.saveGState()
ctx.addPath(shell); ctx.clip()
let face = CGGradient(colorsSpace: nil, colors: [color(0xF4F7FB), color(0xC9D2DE)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(face, start: CGPoint(x: 512, y: top), end: CGPoint(x: 512, y: bottom), options: [])
ctx.restoreGState()

// pins
func pinRow(y: CGFloat, from x0: CGFloat, to x1: CGFloat) {
    for i in 0..<8 {
        let x = x0 + (x1 - x0) * CGFloat(i) / 7
        let r = CGRect(x: x - 17, y: y - 26, width: 34, height: 52)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil))
    }
}
pinRow(y: 455, from: 300, to: 724)
pinRow(y: 365, from: 335, to: 689)
ctx.setFillColor(color(0x1B2B44)); ctx.fillPath()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
