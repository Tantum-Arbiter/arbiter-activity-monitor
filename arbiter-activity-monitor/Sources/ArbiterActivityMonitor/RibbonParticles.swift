import SwiftUI

/// Shared geometry for the rendered audio-style contours and their travelling sparks.
/// This is a decorative signal: no microphone or audio input is sampled.
enum SidebarWaveform {
    static func point(x: Double, strand: Int, phase: Double, size: CGSize) -> CGPoint {
        let time = phase * .pi * 2
        let envelope = pow(max(0, sin(x * .pi)), 1.2)
        let breathing = 0.72 + 0.28 * sin(time + 0.6)
        let carrier = sin(x * .pi * 5 - time * 2)
        let harmonic = 0.22 * sin(x * .pi * 11 + time * 3)
        let contour = (Double(strand) - 11) / 11
        let amplitude = size.height * 0.34 * envelope * breathing
        return CGPoint(x: x * size.width, y: size.height * 0.5 + (carrier + harmonic) * contour * amplitude)
    }
}

/// Deterministic decorative particles, synchronized with the nine-second ribbon cycle.
enum RibbonParticles {
    static let count = 20
    static let duration = 9.0

    static func point(_ index: Int, phase: Double, size: CGSize) -> CGPoint {
        let seed = Double(index) * 0.61803398875
        let start = seed - floor(seed)
        if index >= 12 {
            return CGPoint(x: (0.1 + start * 0.8 + sin(phase * .pi * 2 + seed) * 0.06) * size.width,
                           y: (0.12 + Double((index * 7) % 11) / 11 * 0.76 + cos(phase * .pi * 2 + seed) * 0.04) * size.height)
        }
        let x = (start + phase).truncatingRemainder(dividingBy: 1)
        return SidebarWaveform.point(x:x,strand:(index * 7) % 23,phase:phase,size:size)
    }

    static func opacity(_ index: Int, phase: Double) -> Double {
        if index >= 12 { return 0.22 + 0.30 * pow(sin(phase * .pi + Double(index)), 2) }
        let seed = Double(index) * 0.61803398875
        let x = (seed - floor(seed) + phase).truncatingRemainder(dividingBy: 1)
        // Hide the wrap at the edges rather than drawing a jump across the sidebar.
        return min(1, max(0, min(x, 1-x) / 0.09)) * (0.65 + Double(index % 3) * 0.16)
    }

    static func tint(_ index: Int) -> Color { index % 3 == 0 ? HUD.magenta : HUD.cyan }

    static func drawStill(in context: GraphicsContext, size: CGSize) {
        for index in 0..<count {
            let point = point(index, phase: 0, size: size)
            let color = tint(index)
            let radius = index < 12 ? 6.0 : 4.0
            let alpha = opacity(index, phase: 0)
            context.fill(Path(ellipseIn: CGRect(x:point.x-radius,y:point.y-radius,width:radius*2,height:radius*2)),
                         with:.radialGradient(Gradient(colors:[color.opacity(alpha*0.65),.clear]),center:point,startRadius:0,endRadius:radius))
            context.fill(Path(ellipseIn:CGRect(x:point.x-0.8,y:point.y-0.8,width:1.6,height:1.6)),with:.color(.white.opacity(alpha)))
        }
    }
}
