import SwiftUI
import AppKit
import QuartzCore

private struct HUDSnapshotKey: EnvironmentKey { static let defaultValue = false }
private struct AmbientMotionKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var hudSnapshot: Bool { get { self[HUDSnapshotKey.self] } set { self[HUDSnapshotKey.self] = newValue } }
    var hudAmbientMotion: Bool {
        get { self[AmbientMotionKey.self] }
        set { self[AmbientMotionKey.self] = newValue }
    }
}

enum NeonEffect: Equatable {
    case wave, ribbon, projection, shimmer
    case trace([Double])
    case track([NeonPoint])
    case routes([NeonRoute])
}

struct NeonRoute: Equatable {
    let x1: Double, y1: Double, x2: Double, y2: Double
}
struct NeonPoint: Equatable { let x:Double; let y:Double }

/// Decorative light moves across actual geometry. It never changes measured values.
struct NeonFlow: View {
    let effect: NeonEffect
    var color = HUD.cyan
    @Environment(\.hudAmbientMotion) private var moving
    @Environment(\.hudValueMotion) private var eventMotion
    private var enabled:Bool {if case .routes = effect {return eventMotion};return moving}
    var body: some View {
        if enabled { FlowSurface(effect:effect,color:color).allowsHitTesting(false).accessibilityHidden(true) }
    }
}

private struct FlowSurface: NSViewRepresentable {
    let effect: NeonEffect
    let color: Color
    func makeNSView(context: Context) -> NeonLayerView { NeonLayerView() }
    func updateNSView(_ view: NeonLayerView, context: Context) { view.configure(effect, color: NSColor(color)) }
}

private final class NeonLayerView: NSView {
    private var effect: NeonEffect = .shimmer
    private var color = NSColor.cyan
    private var drawnSize = CGSize.zero
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame:frame); wantsLayer = true; layer = CALayer(); layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { nil }
    func configure(_ next: NeonEffect, color nextColor: NSColor) {
        guard next != effect || nextColor != color else { return }
        effect = next; color = nextColor; drawnSize = .zero; needsLayout = true
    }
    override func layout() {
        super.layout()
        guard bounds.size != drawnSize, !bounds.isEmpty else { return }
        drawnSize = bounds.size
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        switch effect {
        case .wave, .ribbon:
            let ribbon = effect == .ribbon
            let epoch = layer?.convertTime(CACurrentMediaTime(), from:nil) ?? 0
            // Batch contours into two paths; particle positions share the same phase/geometry.
            for group in 0..<2 {
                let frameCount = ribbon ? 48:24
                let frames=(0...frameCount).map {frame in
                    let combined=CGMutablePath()
                    for index in stride(from:group,to:ribbon ? 23:13,by:2) {combined.addPath(wave(index:index,phase:Double(frame)/Double(frameCount) * .pi*2,ribbon:ribbon))}
                    return combined
                }
                let tint=group==0 ? color:NSColor(srgbRed:0.72,green:0.2,blue:1,alpha:1)
                let shape=line(frames[0],color:tint.withAlphaComponent(ribbon ? 0.95:0.65),width:0.8)
                if ribbon {
                    shape.removeFromSuperlayer()
                    let gradient=CAGradientLayer();gradient.frame=bounds
                    gradient.colors=[NSColor(srgbRed:0.75,green:0.15,blue:1,alpha:1).cgColor,color.cgColor,NSColor(srgbRed:0.65,green:0.2,blue:1,alpha:1).cgColor]
                    gradient.startPoint=CGPoint(x:0,y:1);gradient.endPoint=CGPoint(x:1,y:0)
                    gradient.mask=shape;layer?.addSublayer(gradient)
                }
                let morph=CAKeyframeAnimation(keyPath:"path");morph.values=frames
                morph.beginTime=epoch
                morph.duration=9;morph.repeatCount = .infinity;morph.calculationMode = .linear
                morph.preferredFrameRateRange=CAFrameRateRange(minimum:6,maximum:10,preferred:10)
                shape.add(morph,forKey:"wave")
            }
            if ribbon { addRibbonParticles(epoch:epoch) }
        case .projection:
            for index in 0..<3 {
                let ellipse = CALayer()
                let w = bounds.width*0.35, h = bounds.height*0.18
                ellipse.bounds = CGRect(x:0,y:0,width:w,height:h); ellipse.position = CGPoint(x:bounds.midX,y:bounds.height*0.61)
                ellipse.borderColor = color.withAlphaComponent(0.7).cgColor; ellipse.borderWidth = 1; ellipse.cornerRadius = h/2
                ellipse.shadowColor = color.cgColor; ellipse.shadowRadius = 5; ellipse.shadowOpacity = 0.8; ellipse.shadowOffset = .zero
                ellipse.shadowPath = CGPath(ellipseIn: ellipse.bounds, transform: nil)
                ellipse.shouldRasterize = true; ellipse.rasterizationScale = window?.backingScaleFactor ?? 2
                let scale = CABasicAnimation(keyPath:"transform.scale"); scale.fromValue = 0.7; scale.toValue = 1.5
                let fade = CABasicAnimation(keyPath:"opacity"); fade.fromValue = 0.8; fade.toValue = 0
                let group = CAAnimationGroup(); group.animations = [scale,fade]; group.duration = 3.6; group.repeatCount = .infinity; group.timeOffset = Double(index)*1.2
                group.preferredFrameRateRange = CAFrameRateRange(minimum: 6, maximum: 10, preferred: 10)
                layer?.addSublayer(ellipse); ellipse.add(group,forKey:"projection")
            }
        case .trace(let values):
            guard values.count>1 else { break }
            let maximum = max(1,values.max() ?? 1), path = CGMutablePath()
            for (index,value) in values.enumerated() {
                let point = CGPoint(x:Double(index)/Double(values.count-1)*bounds.width,y:(1-min(1,max(0,value/maximum)))*max(1,bounds.height-3)+1)
                if index==0 {path.move(to:point)} else {path.addLine(to:point)}
            }
            particle(path: path,duration:4.5,offset:0)
        case .routes(let routes):
            for (index,route) in routes.enumerated() {
                let path=CGMutablePath(), start=CGPoint(x:bounds.width*route.x1,y:bounds.height*route.y1), end=CGPoint(x:bounds.width*route.x2,y:bounds.height*route.y2)
                path.move(to:start);path.addCurve(to:end,control1:CGPoint(x:(start.x+end.x)/2,y:start.y),control2:CGPoint(x:(start.x+end.x)/2,y:end.y))
                particle(path:path,duration:2.3,offset:Double(index)*0.3)
            }
        case .track(let points):
            guard points.count>1 else {break}
            let path=CGMutablePath()
            for (index,point) in points.enumerated() {
                let p=CGPoint(x:point.x*bounds.width,y:point.y*bounds.height)
                if index==0 {path.move(to:p)} else {path.addLine(to:p)}
            }
            particle(path:path,duration:7,offset:0)
        case .shimmer:
            let light=CAGradientLayer();light.colors=[NSColor.clear.cgColor,color.withAlphaComponent(0.28).cgColor,NSColor.clear.cgColor]
            light.startPoint=CGPoint(x:0,y:0);light.endPoint=CGPoint(x:1,y:1)
            light.frame=CGRect(x:-bounds.width,y:0,width:bounds.width,height:bounds.height)
            let travel=CABasicAnimation(keyPath:"transform.translation.x");travel.fromValue=0;travel.toValue=bounds.width*2
            travel.duration=6;travel.repeatCount = .infinity
            travel.preferredFrameRateRange = CAFrameRateRange(minimum: 6, maximum: 10, preferred: 10)
            layer?.addSublayer(light);light.add(travel,forKey:"light")
        }
        CATransaction.commit()
    }
    private func addRibbonParticles(epoch:CFTimeInterval) {
        for index in 0..<RibbonParticles.count {
            let radius:CGFloat = index < 12 ? 6:4
            let tint=NSColor(RibbonParticles.tint(index))
            let sprite=CAGradientLayer()
            sprite.type = .radial
            sprite.bounds=CGRect(x:0,y:0,width:radius*2,height:radius*2)
            sprite.colors=[tint.withAlphaComponent(0.8).cgColor,tint.withAlphaComponent(0.15).cgColor,NSColor.clear.cgColor]
            sprite.locations=[0,0.3,1]
            sprite.startPoint=CGPoint(x:0.5,y:0.5);sprite.endPoint=CGPoint(x:1,y:1)
            let core=CALayer();core.backgroundColor=NSColor.white.cgColor
            core.frame=CGRect(x:radius-0.8,y:radius-0.8,width:1.6,height:1.6);core.cornerRadius=0.8
            sprite.addSublayer(core)
            if index < 12 && index % 4 == 0 {
                let glint=CAShapeLayer();let path=CGMutablePath()
                path.move(to:CGPoint(x:radius-3,y:radius));path.addLine(to:CGPoint(x:radius+3,y:radius))
                path.move(to:CGPoint(x:radius,y:radius-3));path.addLine(to:CGPoint(x:radius,y:radius+3))
                glint.path=path;glint.strokeColor=tint.withAlphaComponent(0.8).cgColor;glint.lineWidth=0.5
                sprite.addSublayer(glint)
            }
            sprite.shouldRasterize=true;sprite.rasterizationScale=window?.backingScaleFactor ?? 2
            sprite.position=RibbonParticles.point(index,phase:0,size:bounds.size)
            let travel=CAKeyframeAnimation(keyPath:"position")
            travel.values=(0...72).map {NSValue(point:RibbonParticles.point(index,phase:Double($0)/72,size:bounds.size))}
            let fade=CAKeyframeAnimation(keyPath:"opacity")
            fade.values=(0...72).map {RibbonParticles.opacity(index,phase:Double($0)/72)}
            let motion=CAAnimationGroup();motion.animations=[travel,fade]
            motion.duration=RibbonParticles.duration;motion.repeatCount = .infinity;motion.beginTime=epoch
            motion.preferredFrameRateRange=CAFrameRateRange(minimum:6,maximum:10,preferred:10)
            layer?.addSublayer(sprite);sprite.add(motion,forKey:"ribbonParticle")
        }
    }
    private func wave(index:Int,phase:Double,ribbon:Bool=false)->CGPath {
        let path=CGMutablePath()
        for step in 0...60 {
            let f=Double(step)/60
            let y:Double
            if ribbon {y=SidebarWaveform.point(x:f,strand:index,phase:phase / (.pi*2),size:bounds.size).y}
            else {y=bounds.height*0.5 + sin(f*7.5+Double(index)*0.16+phase)*bounds.height*0.27 + sin(f*3.2-phase)*bounds.height*0.09 + (Double(index)-6)*2}
            let p=CGPoint(x:f*bounds.width,y:y)
            if step==0 {path.move(to:p)} else {path.addLine(to:p)}
        }
        return path
    }
    private func line(_ path:CGPath,color:NSColor,width:CGFloat)->CAShapeLayer {
        let shape=CAShapeLayer();shape.path=path;shape.strokeColor=color.cgColor;shape.fillColor=nil;shape.lineWidth=width
        // The static SwiftUI waves supply bloom. Blurring every deforming path
        // forces repeated offscreen compositor passes, even with low app CPU.
        layer?.addSublayer(shape);return shape
    }
    private func particle(path:CGPath,duration:Double,offset:Double) {
        let dot=CALayer();dot.bounds=CGRect(x:0,y:0,width:3,height:3);dot.cornerRadius=1.5;dot.backgroundColor=NSColor.white.cgColor
        dot.shadowColor=color.cgColor;dot.shadowOpacity=1;dot.shadowRadius=5;dot.shadowOffset = .zero
        dot.shadowPath = CGPath(ellipseIn: dot.bounds, transform: nil)
        dot.shouldRasterize = true; dot.rasterizationScale = window?.backingScaleFactor ?? 2
        let travel=CAKeyframeAnimation(keyPath:"position");travel.path=path;travel.calculationMode = .paced;travel.duration=duration;travel.repeatCount = .infinity;travel.timeOffset=offset
        travel.preferredFrameRateRange = CAFrameRateRange(minimum: 6, maximum: 10, preferred: 10)
        layer?.addSublayer(dot);dot.add(travel,forKey:"flow")
    }
}
