import SwiftUI
import AppKit
import QuartzCore

private struct ValueMotionKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var hudValueMotion: Bool { get { self[ValueMotionKey.self] } set { self[ValueMotionKey.self] = newValue } }
}

enum MeterGeometry: Equatable {
    case arc(start: Double, sweep: Double, width: Double)
    case bar
    func path(in size: CGSize) -> CGPath {
        let path = CGMutablePath()
        switch self {
        case let .arc(start, sweep, width):
            path.addArc(center: CGPoint(x: size.width/2, y: size.height/2), radius: max(0, (min(size.width, size.height)-width)/2), startAngle: start * .pi * 2, endAngle: (start+sweep) * .pi * 2, clockwise: false)
        case .bar:
            path.move(to: CGPoint(x: size.height/2, y: size.height/2))
            path.addLine(to: CGPoint(x: max(size.height/2, size.width-size.height/2), y: size.height/2))
        }
        return path
    }
    func lineWidth(in size: CGSize) -> CGFloat {
        switch self { case let .arc(_, _, width): width; case .bar: size.height }
    }
}

/// Only strokeEnd interpolates. Text and the parent dashboard remain at sample cadence.
struct AnimatedMeter: View {
    let value: Double?
    let color: Color
    let geometry: MeterGeometry
    @Environment(\.hudSnapshot) private var snapshot
    @Environment(\.hudValueMotion) private var animate
    var body: some View {
        Group {
            if snapshot {
                Canvas { context, size in
                    guard let value else { return }
                    context.stroke(Path(geometry.path(in: size)).trimmedPath(from: 0, to: min(1,max(0,value/100))), with: .linearGradient(Gradient(colors: [color, color.opacity(0.5)]), startPoint: .zero, endPoint: CGPoint(x:size.width,y:size.height)), style: StrokeStyle(lineWidth: geometry.lineWidth(in:size),lineCap:.round))
                }
            } else { MeterSurface(value:value,color:color,geometry:geometry,animate:animate) }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct MeterSurface: NSViewRepresentable {
    let value: Double?; let color: Color; let geometry: MeterGeometry; let animate: Bool
    func makeNSView(context: Context) -> MeterLayerView { MeterLayerView() }
    func updateNSView(_ view: MeterLayerView, context: Context) { view.configure(value, color:NSColor(color), geometry:geometry, animate:animate) }
}

private final class MeterLayerView: NSView {
    private let stroke = CAShapeLayer()
    private let glint = CAShapeLayer()
    private let gradient = CAGradientLayer()
    private var geometry: MeterGeometry = .bar
    private var previous: Double?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame:frame); wantsLayer=true; layer=CALayer()
        stroke.fillColor=nil; stroke.strokeColor=NSColor.white.cgColor; stroke.lineCap = .round
        gradient.startPoint=CGPoint(x:0,y:0);gradient.endPoint=CGPoint(x:1,y:1);gradient.mask=stroke
        layer?.addSublayer(gradient)
        glint.fillColor=nil;glint.strokeColor=NSColor.white.cgColor;glint.lineCap = .round;glint.opacity=0;layer?.addSublayer(glint)
    }
    required init?(coder:NSCoder) { nil }
    func configure(_ value:Double?,color:NSColor,geometry:MeterGeometry,animate:Bool) {
        CATransaction.begin();CATransaction.setDisableActions(true)
        if self.geometry != geometry {self.geometry=geometry;needsLayout=true}
        gradient.colors=[color.cgColor,color.withAlphaComponent(0.55).cgColor]
        let next=value.map{min(1,max(0,$0/100))}
        stroke.isHidden = next == nil
        if next != previous || !animate {
            let displayed=stroke.presentation()?.strokeEnd ?? stroke.strokeEnd
            stroke.removeAnimation(forKey:"reading")
            stroke.strokeEnd=next ?? 0
            if animate,previous != nil,let next,next != previous {
                let transition=CABasicAnimation(keyPath:"strokeEnd")
                transition.fromValue=displayed;transition.toValue=next;transition.duration=0.5
                transition.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut)
                transition.preferredFrameRateRange=CAFrameRateRange(minimum:15,maximum:30,preferred:30)
                stroke.add(transition,forKey:"reading")
            }
            if animate,let old=previous,let next,abs(next-old)>=0.08 {
                let start=CABasicAnimation(keyPath:"strokeStart");start.fromValue=0;start.toValue=next
                let end=CABasicAnimation(keyPath:"strokeEnd");end.fromValue=min(0.08,next);end.toValue=next
                let fade=CABasicAnimation(keyPath:"opacity");fade.fromValue=0.8;fade.toValue=0
                let group=CAAnimationGroup();group.animations=[start,end,fade];group.duration=0.5
                glint.add(group,forKey:"significantChange")
            }
            if !animate {glint.removeAllAnimations()}
            previous=next
        }
        CATransaction.commit()
    }
    override func layout() {
        super.layout()
        CATransaction.begin();CATransaction.setDisableActions(true)
        gradient.frame=bounds;stroke.frame=bounds;stroke.path=geometry.path(in:bounds.size);stroke.lineWidth=geometry.lineWidth(in:bounds.size)
        glint.frame=bounds;glint.path=stroke.path;glint.lineWidth=max(1,stroke.lineWidth*0.35)
        CATransaction.commit()
    }
}
