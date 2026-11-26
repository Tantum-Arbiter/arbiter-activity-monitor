import SwiftUI
import AppKit
import QuartzCore

/// One decorative particle. Position, opacity and scale are pure functions of its own 0…1 cycle phase, so the
/// animated Core Animation sprites and still snapshot frames come from the same geometry. Particles are atmosphere
/// only: they never encode a measurement and never run outside Cinematic.
struct Particle {
    enum Shape: Equatable { case glow, glint, streak(length: CGFloat, vertical: Bool, reverse: Bool) }
    var radius: CGFloat
    var tint: Color
    var shape: Shape = .glow
    /// Seconds per cycle. A cycle may jump at its ends only where opacity is zero.
    var duration: Double
    /// Fraction of a cycle this particle starts ahead, so a field does not move in step.
    var offset: Double = 0
    var point: (Double) -> CGPoint
    var opacity: (Double) -> Double
    var scale: ((Double) -> Double)? = nil
}

enum ParticleKind: Equatable {
    /// Depth-sorted motes rising across the dashboard, plus light packets running along the grid.
    case motes
    /// Sparks spiralling up the projector beam and comets orbiting the globe.
    case hologram
    /// A comet circling a panel's border.
    case edge(seed: Int, corner: CGFloat)
    /// Sparks flowing along the filled part of a meter bar.
    case stream(seed: Int, fraction: Double)
}

enum ParticleFields {
    /// Compositor frame rate requested for particle motion. Smooth enough to read as drifting light, far below the display rate.
    nonisolated(unsafe) static var frameRate: Float = 24
    /// Deterministic 0…1 value: the same field every launch, no random state to keep.
    static func noise(_ index: Int, _ salt: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: index &* 0x9E3779B1 &+ salt &* 0x85EBCA77 &+ 0x1234567)
        x ^= x >> 33; x = x &* 0xff51afd7ed558ccd; x ^= x >> 33; x = x &* 0xc4ceb9fe1a85ec53; x ^= x >> 33
        return Double(x % 1_000_000) / 1_000_000
    }

    static func particles(_ kind: ParticleKind, size: CGSize, color: Color) -> [Particle] {
        guard size.width > 4, size.height > 2 else { return [] }
        switch kind {
        case .motes: return motes(size) + packets(size)
        case .hologram: return beam(size) + orbits(size)
        case .edge(let seed, let corner): return edge(size, seed: seed, corner: corner)
        case .stream(let seed, let fraction): return stream(size, seed: seed, fraction: fraction, color: color)
        }
    }

    private static func palette(_ value: Double) -> Color {
        value < 0.56 ? HUD.cyan : value < 0.82 ? HUD.purple : value < 0.94 ? HUD.magenta : .white
    }

    /// Three depth tiers rising at different speeds: far motes are small, slow and dim; near ones large, soft and quick.
    private static func motes(_ size: CGSize) -> [Particle] {
        let count = min(96, max(30, Int(size.width * size.height / 15000)))
        return (0..<count).map { i in
            let depth = i % 6 == 0 ? 2 : i % 2 == 0 ? 1 : 0
            let x0 = 0.03 + noise(i, 1) * 0.94
            let sway = (0.008 + noise(i, 3) * 0.022) * (noise(i, 4) < 0.5 ? -1 : 1)
            let swayRate = Double(1 + i % 3), seed = noise(i, 5) * .pi * 2
            let drift = 0.05 * (noise(i, 9) - 0.5)
            let peak = [0.5, 0.62, 0.3][depth], twinkleRate = Double(3 + i % 4)
            return Particle(radius: [1.5, 2.5, 5.5][depth] * (0.8 + noise(i, 7) * 0.5), tint: palette(noise(i, 8)),
                            shape: depth == 2 && i % 12 == 0 ? .glint : .glow,
                            duration: [64.0, 40, 24][depth] * (0.85 + noise(i, 6) * 0.3), offset: noise(i, 2),
                            point: { p in CGPoint(x: (x0 + drift * p + sway * sin(p * .pi * 2 * swayRate + seed)) * size.width, y: (1.04 - p * 1.08) * size.height) },
                            opacity: { p in peak * min(1, min(p, 1 - p) / 0.07) * (0.62 + 0.38 * sin(p * .pi * 2 * twinkleRate + seed)) })
        }
    }

    /// Light packets that run along the 30-point grid lines, then rest until their next cycle.
    private static func packets(_ size: CGSize) -> [Particle] {
        (0..<9).map { i in
            let vertical = i % 3 == 2
            let lanes = max(1, Int((vertical ? size.width : size.height) / 30))
            let lane = Double(Int(noise(i, 21) * Double(lanes)) * 30)
            let reverse = noise(i, 22) < 0.35, active = 0.24 + noise(i, 23) * 0.12
            let tint = i % 4 == 0 ? HUD.magenta : HUD.cyan
            func along(_ p: Double) -> Double {
                let t = min(1, p / active), eased = t * t * (3 - 2 * t)
                return (reverse ? 1.08 - eased * 1.16 : -0.08 + eased * 1.16)
            }
            return Particle(radius: 1.3, tint: tint, shape: .streak(length: 54, vertical: vertical, reverse: reverse),
                            duration: 9 + noise(i, 24) * 9, offset: noise(i, 25),
                            point: { p in vertical ? CGPoint(x: lane, y: along(p) * size.height) : CGPoint(x: along(p) * size.width, y: lane) },
                            opacity: { p in p >= active ? 0 : 0.85 * pow(sin(.pi * p / active), 0.6) })
        }
    }

    /// Matches HolographicInstrument's geometry: globe centre, diameter and the projector on the floor.
    private static func stage(_ size: CGSize) -> (center: CGPoint, diameter: Double, base: CGPoint) {
        let diameter = min(size.width * 0.92, size.height * 1.04)
        return (CGPoint(x: size.width * 0.5, y: size.height * 0.46), diameter, CGPoint(x: size.width * 0.5, y: size.height * 0.887))
    }

    /// Sparks spiralling up an opening cone from the projector into the globe.
    private static func beam(_ size: CGSize) -> [Particle] {
        let s = stage(size)
        let top = s.center.y + s.diameter * 0.12
        return (0..<44).map { i in
            let seed = noise(i, 31) * .pi * 2, turns = 1.2 + noise(i, 32) * 1.1, spread = 0.75 + noise(i, 33) * 0.5
            func angle(_ p: Double) -> Double { p * .pi * 2 * turns + seed }
            func radius(_ p: Double) -> Double { s.diameter * (0.025 + 0.2 * p) * spread }
            return Particle(radius: 1.8 + noise(i, 34) * 1.5, tint: i % 5 == 0 ? .white : i % 3 == 0 ? HUD.purple : HUD.cyan,
                            shape: i % 10 == 0 ? .glint : .glow, duration: 4.6 + noise(i, 35) * 3.2, offset: noise(i, 36),
                            point: { p in CGPoint(x: s.base.x + radius(p) * cos(angle(p)), y: s.base.y + (top - s.base.y) * p + radius(p) * 0.24 * sin(angle(p))) },
                            opacity: { p in 0.9 * pow(sin(.pi * p), 0.75) * (0.5 + 0.25 * (sin(angle(p)) + 1)) },
                            scale: { p in 0.75 + 0.2 * (sin(angle(p)) + 1) })
        }
    }

    /// Three tilted orbits around the globe, each a comet with a fading tail that dims as it passes behind.
    private static func orbits(_ size: CGSize) -> [Particle] {
        let s = stage(size)
        let rings: [(a: Double, b: Double, tilt: Double, period: Double, direction: Double, tint: Color)] = [
            (0.405, 0.125, -0.38, 8.5, 1, HUD.cyan), (0.37, 0.1, 0.5, 11.5, -1, HUD.magenta), (0.39, 0.075, 1.12, 14, 1, HUD.purple),
        ]
        var result: [Particle] = []
        for (index, ring) in rings.enumerated() {
            let start = noise(index, 41)
            for tail in 0..<22 {
                let lag = Double(tail) * 0.0045, fade = 1 - Double(tail) / 22
                func angle(_ p: Double) -> Double { (p - lag) * .pi * 2 * ring.direction + start * .pi * 2 }
                result.append(Particle(radius: tail == 0 ? 4 : 3.2 * fade + 0.8, tint: tail == 0 ? .white : ring.tint, shape: tail == 0 ? .glint : .glow,
                                       duration: ring.period,
                                       point: { p in
                                           let x = s.diameter * ring.a * cos(angle(p)), y = s.diameter * ring.b * sin(angle(p))
                                           return CGPoint(x: s.center.x + x * cos(ring.tilt) - y * sin(ring.tilt), y: s.center.y + x * sin(ring.tilt) + y * cos(ring.tilt))
                                       },
                                       opacity: { p in fade * (0.35 + 0.65 * fade) * (sin(angle(p)) > 0 ? 1 : 0.32) },
                                       scale: { p in 0.8 + 0.2 * (sin(angle(p)) + 1) / 2 }))
            }
        }
        return result
    }

    /// A point `fraction` of the way round a rounded rectangle, clockwise from the top-left corner's end.
    static func perimeter(_ fraction: Double, rect: CGRect, corner: CGFloat) -> CGPoint {
        let r = Double(min(corner, min(rect.width, rect.height) / 2))
        let w = Double(rect.width) - 2 * r, h = Double(rect.height) - 2 * r, arc = .pi * r / 2
        var d = (fraction - floor(fraction)) * (2 * w + 2 * h + 4 * arc)
        let minX = Double(rect.minX), minY = Double(rect.minY), maxX = Double(rect.maxX), maxY = Double(rect.maxY)
        func turn(_ cx: Double, _ cy: Double, from: Double) -> CGPoint {
            let a = from + (arc > 0 ? d / arc : 0) * .pi / 2
            return CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
        }
        if d < w { return CGPoint(x: minX + r + d, y: minY) }; d -= w
        if d < arc { return turn(maxX - r, minY + r, from: -.pi / 2) }; d -= arc
        if d < h { return CGPoint(x: maxX, y: minY + r + d) }; d -= h
        if d < arc { return turn(maxX - r, maxY - r, from: 0) }; d -= arc
        if d < w { return CGPoint(x: maxX - r - d, y: maxY) }; d -= w
        if d < arc { return turn(minX + r, maxY - r, from: .pi / 2) }; d -= arc
        if d < h { return CGPoint(x: minX, y: maxY - r - d) }; d -= h
        return turn(minX + r, minY + r, from: .pi)
    }

    private static func edge(_ size: CGSize, seed: Int, corner: CGFloat) -> [Particle] {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let length = 2 * Double(rect.width + rect.height)
        guard length > 200 else { return [] }
        let direction: Double = seed % 2 == 0 ? 1 : -1, start = noise(seed, 51)
        let tint = [HUD.cyan, HUD.magenta, HUD.purple][abs(seed) % 3]
        // Constant speed whatever the panel size, so large panels do not get a faster comet.
        let duration = max(9, length / 95) * (0.9 + noise(seed, 52) * 0.25)
        return (0..<24).map { tail in
            let lag = Double(tail) * 3.2 / length, fade = 1 - Double(tail) / 24
            return Particle(radius: tail == 0 ? 3.6 : 2.8 * fade + 0.7, tint: tail == 0 ? .white : tint, shape: tail == 0 ? .glint : .glow, duration: duration,
                            point: { p in perimeter(start + direction * (p - lag), rect: rect, corner: corner) },
                            opacity: { _ in fade * (0.35 + 0.65 * fade) })
        }
    }

    private static func stream(_ size: CGSize, seed: Int, fraction: Double, color: Color) -> [Particle] {
        let span = Double(size.width) * min(1, max(0, fraction))
        guard span > 24 else { return [] }
        return (0..<3).map { i in
            // Thin meters carry sparks along their centre; taller bar charts along their baseline.
            Particle(radius: min(3, Double(size.height) * 0.5 + 1.2), tint: i == 1 ? .white : color, duration: 2.6 + noise(seed + i, 61) * 1.6, offset: (Double(i) + noise(seed, 62)) / 3,
                     point: { p in CGPoint(x: span * p, y: size.height <= 10 ? Double(size.height) / 2 : Double(size.height) - 2) },
                     opacity: { p in 0.95 * pow(sin(.pi * p), 0.7) })
        }
    }

    /// Still frame at `time` seconds, for snapshots.
    static func draw(_ kind: ParticleKind, color: Color, size: CGSize, time: Double, in context: GraphicsContext) {
        for particle in particles(kind, size: size, color: color) {
            let cycle = time / particle.duration + particle.offset, phase = cycle - floor(cycle)
            let alpha = particle.opacity(phase)
            guard alpha > 0.01 else { continue }
            let point = particle.point(phase), scale = abs(particle.scale?(phase) ?? 1), radius = Double(particle.radius) * scale
            switch particle.shape {
            case .streak(let length, let vertical, let reverse):
                let rect = vertical ? CGRect(x: point.x - 0.8, y: point.y - length / 2, width: 1.6, height: length) : CGRect(x: point.x - length / 2, y: point.y - 0.8, width: length, height: 1.6)
                let forward = !reverse
                let head = vertical ? CGPoint(x: rect.midX, y: forward ? rect.maxY : rect.minY) : CGPoint(x: forward ? rect.maxX : rect.minX, y: rect.midY)
                let tail = vertical ? CGPoint(x: rect.midX, y: forward ? rect.minY : rect.maxY) : CGPoint(x: forward ? rect.minX : rect.maxX, y: rect.midY)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.8), with: .linearGradient(Gradient(colors: [.clear, particle.tint.opacity(alpha * 0.8), .white.opacity(alpha)]), startPoint: tail, endPoint: head))
            case .glow, .glint:
                let halo = radius * 2.2
                context.fill(Path(ellipseIn: CGRect(x: point.x - halo, y: point.y - halo, width: halo * 2, height: halo * 2)),
                             with: .radialGradient(Gradient(colors: [particle.tint.opacity(alpha * 0.75), particle.tint.opacity(alpha * 0.16), .clear]), center: point, startRadius: 0, endRadius: halo))
                let core = max(0.7, radius * 0.32)
                context.fill(Path(ellipseIn: CGRect(x: point.x - core, y: point.y - core, width: core * 2, height: core * 2)), with: .color(.white.opacity(min(1, alpha * 1.5))))
                if particle.shape == .glint {
                    var cross = Path()
                    cross.move(to: CGPoint(x: point.x - halo, y: point.y)); cross.addLine(to: CGPoint(x: point.x + halo, y: point.y))
                    cross.move(to: CGPoint(x: point.x, y: point.y - halo)); cross.addLine(to: CGPoint(x: point.x, y: point.y + halo))
                    context.stroke(cross, with: .color(particle.tint.opacity(alpha * 0.7)), lineWidth: 0.5)
                }
            }
        }
    }
}

private struct ParticleStillKey: EnvironmentKey { static let defaultValue: Double? = nil }
extension EnvironmentValues {
    /// Snapshot rendering only: draw particle fields frozen at this many seconds into their cycles.
    var hudParticleStill: Double? { get { self[ParticleStillKey.self] } set { self[ParticleStillKey.self] = newValue } }
}

/// A Cinematic particle field. Animated by the window compositor; nothing is drawn in other visual modes.
struct ParticleField: View {
    let kind: ParticleKind
    var color = HUD.cyan
    @Environment(\.hudAmbientMotion) private var moving
    @Environment(\.hudParticleStill) private var still
    var body: some View {
        if moving {
            ParticleSurface(kind: kind, color: color).allowsHitTesting(false).accessibilityHidden(true)
        } else if let still {
            Canvas { context, size in ParticleFields.draw(kind, color: color, size: size, time: still, in: context) }.allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

private struct ParticleSurface: NSViewRepresentable {
    let kind: ParticleKind
    let color: Color
    func makeNSView(context: Context) -> ParticleLayerView { ParticleLayerView() }
    func updateNSView(_ view: ParticleLayerView, context: Context) { view.configure(kind, color: color) }
}

/// Sprites share a few pre-rendered textures and are moved by keyframe animations in the render server:
/// no per-frame work in the app, no SwiftUI invalidation.
private final class ParticleLayerView: NSView {
    private var kind: ParticleKind?
    private var color = HUD.cyan
    private var drawnSize = CGSize.zero
    private var textures: [String: CGImage] = [:]
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer = CALayer() }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(_ next: ParticleKind, color nextColor: Color) {
        guard next != kind || nextColor != color else { return }
        kind = next; color = nextColor; drawnSize = .zero; needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let kind, bounds.size != drawnSize, !bounds.isEmpty else { return }
        drawnSize = bounds.size
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        // Fields that cover content are clipped; comets on a border may glow slightly past it.
        if case .edge = kind { layer?.masksToBounds = false } else { layer?.masksToBounds = true }
        let epoch = layer?.convertTime(CACurrentMediaTime(), from: nil) ?? 0
        let scale = window?.backingScaleFactor ?? 2
        for particle in ParticleFields.particles(kind, size: bounds.size, color: color) {
            let sprite = CALayer()
            let glowRadius = particle.radius * 2.2
            switch particle.shape {
            case .streak(let length, let vertical, let reverse):
                sprite.bounds = CGRect(x: 0, y: 0, width: length, height: 1.6)
                // The texture's bright head points along +x; turn it to face the direction of travel.
                sprite.setAffineTransform(CGAffineTransform(rotationAngle: (vertical ? .pi / 2 : 0) + (reverse ? .pi : 0)))
            case .glow, .glint:
                sprite.bounds = CGRect(x: 0, y: 0, width: glowRadius * 2, height: glowRadius * 2)
            }
            sprite.contents = texture(particle.shape, tint: NSColor(particle.tint), scale: scale)
            sprite.contentsGravity = .resize
            sprite.opacity = 0
            let samples = 72
            let phases = (0...samples).map { Double($0) / Double(samples) }
            let travel = CAKeyframeAnimation(keyPath: "position")
            travel.values = phases.map { NSValue(point: particle.point($0)) }
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = phases.map { particle.opacity($0) }
            var animations: [CAAnimation] = [travel, fade]
            if let size = particle.scale {
                let grow = CAKeyframeAnimation(keyPath: "transform.scale")
                grow.values = phases.map { size($0) }
                animations.append(grow)
            }
            let motion = CAAnimationGroup()
            motion.animations = animations
            motion.duration = particle.duration; motion.repeatCount = .infinity
            motion.beginTime = epoch; motion.timeOffset = particle.offset * particle.duration
            motion.preferredFrameRateRange = CAFrameRateRange(minimum: min(15, ParticleFields.frameRate), maximum: ParticleFields.frameRate, preferred: ParticleFields.frameRate)
            layer?.addSublayer(sprite)
            sprite.add(motion, forKey: "particle")
        }
        CATransaction.commit()
    }

    /// One texture per shape and tint, shared by every sprite that uses it.
    private func texture(_ shape: Particle.Shape, tint: NSColor, scale: CGFloat) -> CGImage? {
        let rgb = tint.usingColorSpace(.sRGB) ?? tint
        let name: String
        switch shape { case .glow: name = "glow"; case .glint: name = "glint"; case .streak: name = "streak" }
        let key = "\(name)-\(Int(rgb.redComponent * 255))-\(Int(rgb.greenComponent * 255))-\(Int(rgb.blueComponent * 255))"
        if let cached = textures[key] { return cached }
        let streak = name == "streak"
        let pixels = streak ? CGSize(width: 108 * scale, height: 4 * scale) : CGSize(width: 48 * scale, height: 48 * scale)
        guard let context = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func gradient(_ stops: [(NSColor, CGFloat)]) -> CGGradient? {
            CGGradient(colorsSpace: space, colors: stops.map { $0.0.cgColor } as CFArray, locations: stops.map { $0.1 })
        }
        if streak {
            if let fade = gradient([(rgb.withAlphaComponent(0), 0), (rgb.withAlphaComponent(0.8), 0.72), (NSColor.white, 1)]) {
                context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: pixels), cornerWidth: pixels.height / 2, cornerHeight: pixels.height / 2, transform: nil))
                context.clip()
                context.drawLinearGradient(fade, start: .zero, end: CGPoint(x: pixels.width, y: 0), options: [])
            }
        } else {
            let center = CGPoint(x: pixels.width / 2, y: pixels.height / 2), radius = pixels.width / 2
            if let halo = gradient([(rgb.withAlphaComponent(0.75), 0), (rgb.withAlphaComponent(0.16), 0.42), (rgb.withAlphaComponent(0), 1)]) {
                context.drawRadialGradient(halo, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
            }
            if name == "glint" {
                context.setStrokeColor(rgb.withAlphaComponent(0.7).cgColor); context.setLineWidth(max(1, scale * 0.6))
                context.move(to: CGPoint(x: 0, y: center.y)); context.addLine(to: CGPoint(x: pixels.width, y: center.y))
                context.move(to: CGPoint(x: center.x, y: 0)); context.addLine(to: CGPoint(x: center.x, y: pixels.height))
                context.strokePath()
            }
            let core = radius * 0.15
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2))
        }
        let image = context.makeImage()
        textures[key] = image
        return image
    }
}
