import SwiftUI

/// Static edge lighting: no full-panel blur or animation-driven invalidation.
struct NeonPanelEdge: View {
    var emphasized = false
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let outline = Path(roundedRect: rect, cornerRadius: 15)
            let colors = [HUD.cyan, HUD.purple, HUD.magenta, HUD.cyan]
            let gradient = GraphicsContext.Shading.linearGradient(
                Gradient(colors: colors.map { $0.opacity(emphasized ? 1 : 0.8) }),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height))
            context.stroke(outline, with: gradient, lineWidth: 1)
            for (x, y, color) in [(0.67, 0.0, HUD.cyan), (0.94, 0.04, HUD.purple), (0.18, 1.0, HUD.cyan), (0.84, 1.0, HUD.magenta)] {
                let center = CGPoint(x: size.width*x, y: size.height*y)
                for (width, strength) in [(9.0, 0.08), (5.0, 0.16), (2.5, 0.4)] {
                    context.fill(outline.strokedPath(StrokeStyle(lineWidth:width)),
                        with:.radialGradient(Gradient(colors:[color.opacity(strength*(emphasized ? 1.4:1)), .clear]),center:center,startRadius:0,endRadius:85))
                }
            }
            for x in [0.18, 0.67] {
                let y = x < 0.5 ? size.height-1 : 1
                let glow = CGRect(x:size.width*x-38, y:y-1, width:76, height:2)
                context.fill(Path(ellipseIn:glow), with:.linearGradient(Gradient(colors:[.clear, HUD.cyan, .white.opacity(0.8), HUD.cyan, .clear]), startPoint:CGPoint(x:glow.minX,y:y),endPoint:CGPoint(x:glow.maxX,y:y)))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
