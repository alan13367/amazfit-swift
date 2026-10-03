import AppKit
import Foundation

// Generates the app icon: the app's heart, sleep, and activity rings around a pulse line.
// Drawn in code, no downloaded artwork. Usage: swift scripts/make-icon.swift [output.icns] [preview.png]
let arguments = Array(CommandLine.arguments.dropFirst())
let output = arguments.first ?? "Support/Helio.icns"
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Helio-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func draw(in context: CGContext) {
    // macOS icon grid: an 824-point squircle centered on a 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
    let center = CGPoint(x: 512, y: 512)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    context.addPath(shape)
    context.setFillColor(color(0x101217).cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let background = CGGradient(colorsSpace: space, colors: [color(0x22252E).cgColor, color(0x0B0C10).cgColor] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [color(0x5EE0C1, 0.22).cgColor, color(0x5EE0C1, 0).cgColor] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 380, options: [])

    // Rings: outer heart, middle sleep, inner activity. Each starts at 12 o'clock and runs clockwise.
    let rings: [(radius: CGFloat, hex: UInt32, light: UInt32, progress: CGFloat)] = [
        (282, 0xFF5A6E, 0xFF8E9C, 0.80), (214, 0x8C7CF6, 0xB3A8FF, 0.66), (146, 0x3DD68C, 0x7DF0B8, 0.90)
    ]
    for ring in rings {
        context.setLineWidth(50)
        context.setLineCap(.round)
        context.setStrokeColor(color(ring.hex, 0.17).cgColor)
        context.addArc(center: center, radius: ring.radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()

        let start = CGFloat.pi / 2
        let end = start - ring.progress * .pi * 2
        let arc = CGMutablePath()
        arc.addArc(center: center, radius: ring.radius, startAngle: start, endAngle: end, clockwise: true)
        context.saveGState()
        context.setShadow(offset: .zero, blur: 24, color: color(ring.hex, 0.55).cgColor)
        context.addPath(arc.copy(strokingWithWidth: 50, lineCap: .round, lineJoin: .round, miterLimit: 10))
        context.clip()
        // A conic sweep would need private API; a diagonal gradient gives each ring a lit edge.
        let gradient = CGGradient(colorsSpace: space, colors: [color(ring.light).cgColor, color(ring.hex).cgColor] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: center.x - ring.radius, y: center.y + ring.radius),
                                   end: CGPoint(x: center.x + ring.radius, y: center.y - ring.radius), options: [])
        context.restoreGState()
    }

    // Pulse line through the center ring.
    let pulse = CGMutablePath()
    let points: [CGPoint] = [(-100, 0), (-44, 0), (-20, 42), (6, -62), (32, 28), (48, 0), (100, 0)].map { CGPoint(x: 512 + $0.0, y: 512 + $0.1) }
    pulse.addLines(between: points)
    context.saveGState()
    context.setShadow(offset: .zero, blur: 18, color: NSColor.white.withAlphaComponent(0.6).cgColor)
    context.addPath(pulse)
    context.setLineWidth(24)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(NSColor.white.cgColor)
    context.strokePath()
    context.restoreGState()

    // Soft top sheen and a hairline edge.
    let sheen = CGGradient(colorsSpace: space, colors: [NSColor.white.withAlphaComponent(0.07).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    context.restoreGState()
    context.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 185, cornerHeight: 185, transform: nil))
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
    context.setLineWidth(3)
    context.strokePath()
}

func render(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    draw(in: context)
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try render(pixels: size * scale).write(to: directory.appendingPathComponent(name))
    }
}
if arguments.count > 1 { try render(pixels: 1024).write(to: URL(fileURLWithPath: arguments[1])) }
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", directory.path, "-o", output]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
