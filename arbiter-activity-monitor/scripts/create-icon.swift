import AppKit
import Foundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        let inset = Double(pixels) * 0.055
        let shape = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: Double(pixels) * 0.21, yRadius: Double(pixels) * 0.21)
        NSGradient(starting: NSColor(srgbRed: 0.06, green: 0.15, blue: 0.24, alpha: 1), ending: NSColor(srgbRed: 0.025, green: 0.04, blue: 0.09, alpha: 1))!.draw(in: shape, angle: -60)
        let cyan = NSColor(srgbRed: 0.125, green: 0.957, blue: 1, alpha: 1)
        let purple = NSColor(srgbRed: 0.70, green: 0.53, blue: 1, alpha: 1)
        for (fraction, color) in [(0.19, cyan), (0.26, purple)] {
            let ring = NSBezierPath()
            ring.appendArc(withCenter: NSPoint(x: pixels / 2, y: pixels / 2), radius: Double(pixels) * (0.5 - fraction), startAngle: 225, endAngle: -45, clockwise: true)
            ring.lineWidth = Double(pixels) * 0.024
            ring.lineCapStyle = .round
            color.setStroke(); ring.stroke()
        }
        let wave = NSBezierPath()
        let points: [(Double, Double)] = [(0.32,0.5),(0.4,0.5),(0.44,0.64),(0.50,0.36),(0.55,0.57),(0.59,0.5),(0.68,0.5)]
        for (index, point) in points.enumerated() {
            let p = NSPoint(x: point.0 * Double(pixels), y: point.1 * Double(pixels))
            if index == 0 { wave.move(to: p) } else { wave.line(to: p) }
        }
        wave.lineWidth = Double(pixels) * 0.023; wave.lineJoinStyle = .round; wave.lineCapStyle = .round
        cyan.setStroke(); wave.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
