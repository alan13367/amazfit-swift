import AppKit
import Foundation

// Generates the local development app icon. No downloaded artwork or dependencies.
let output = CommandLine.arguments.dropFirst().first ?? "Support/Helio.icns"
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Helio-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let transform = AffineTransform(scale: Double(pixels) / 1024)
        (transform as NSAffineTransform).concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 195, yRadius: 195)
        NSGradient(starting: NSColor(calibratedWhite: 0.16, alpha: 1), ending: NSColor(calibratedWhite: 0.045, alpha: 1))!.draw(in: background, angle: -90)
        let ring = NSBezierPath(ovalIn: NSRect(x: 240, y: 150, width: 544, height: 724))
        ring.lineWidth = 62
        NSColor(calibratedRed: 0.34, green: 0.92, blue: 0.77, alpha: 1).setStroke()
        ring.stroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 205, y: 485))
        for point in [NSPoint(x: 390, y: 485), NSPoint(x: 446, y: 570), NSPoint(x: 507, y: 365), NSPoint(x: 575, y: 645), NSPoint(x: 638, y: 485), NSPoint(x: 815, y: 485)] { line.line(to: point) }
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        line.lineWidth = 36
        NSColor.white.setStroke()
        line.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", directory.path, "-o", output]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
