import SwiftUI
import AppKit
import QuartzCore

enum MotionIntensity: String, CaseIterable, Identifiable {
    case minimal = "Minimal", balanced = "Balanced", cinematic = "Cinematic"
    var id: String {rawValue}
}
private struct MotionIntensityKey: EnvironmentKey {static let defaultValue = MotionIntensity.balanced}
extension EnvironmentValues {
    var hudIntensity: MotionIntensity {get {self[MotionIntensityKey.self]} set {self[MotionIntensityKey.self]=newValue}}
}

/// One bounded acknowledgement per new observation, never a repeating activity simulation.
struct SamplePulse: View {
    let token: Double
    var color = HUD.cyan
    var circular = false
    @Environment(\.hudValueMotion) private var enabled
    @Environment(\.hudSnapshot) private var snapshot
    var body: some View {
        if !snapshot { PulseSurface(token:token,color:color,circular:circular,enabled:enabled).allowsHitTesting(false).accessibilityHidden(true) }
    }
}

private struct PulseSurface: NSViewRepresentable {
    let token:Double
    let color:Color
    let circular:Bool
    let enabled:Bool
    func makeNSView(context: Context) -> SamplePulseLayer { SamplePulseLayer() }
    func updateNSView(_ view: SamplePulseLayer, context: Context) {
        view.configure(token:token,color:NSColor(color),circular:circular,enabled:enabled)
    }
}

final class SamplePulseLayer: NSView {
    private let stroke=CAShapeLayer()
    private var token:Double?
    private var circular=false
    override var isFlipped:Bool {true}
    override init(frame:NSRect) {
        super.init(frame:frame);wantsLayer=true;layer=CALayer()
        stroke.fillColor=nil;stroke.lineWidth=1.5;stroke.opacity=0;layer?.addSublayer(stroke)
    }
    required init?(coder:NSCoder) {nil}
    override func hitTest(_ point:NSPoint)->NSView? {nil}
    func configure(token:Double,color:NSColor,circular:Bool,enabled:Bool) {
        CATransaction.begin();CATransaction.setDisableActions(true)
        stroke.strokeColor=color.cgColor
        if self.circular != circular {self.circular=circular;needsLayout=true}
        if !enabled {stroke.removeAllAnimations()}
        else if let previous=self.token,previous != token {
            let pulse=CABasicAnimation(keyPath:"opacity")
            pulse.fromValue=0.7;pulse.toValue=0;pulse.duration=0.5
            pulse.timingFunction=CAMediaTimingFunction(name:.easeOut)
            pulse.preferredFrameRateRange=CAFrameRateRange(minimum:15,maximum:30,preferred:30)
            stroke.add(pulse,forKey:"sample")
        }
        self.token=token
        CATransaction.commit()
    }
    override func layout() {
        super.layout()
        CATransaction.begin();CATransaction.setDisableActions(true)
        stroke.frame=bounds
        let rect=bounds.insetBy(dx:1,dy:1)
        stroke.path=circular ? CGPath(ellipseIn:rect,transform:nil):CGPath(roundedRect:rect,cornerWidth:4,cornerHeight:4,transform:nil)
        CATransaction.commit()
    }
}

struct HUDRowStyle: ButtonStyle {
    @Environment(\.hudReducedMotion) private var reduced
    func makeBody(configuration:Configuration)->some View {
        configuration.label.background(HUD.cyan.opacity(configuration.isPressed ? 0.13:0),in:RoundedRectangle(cornerRadius:5))
            .animation(reduced ? nil:.easeOut(duration:0.14),value:configuration.isPressed)
    }
}

struct HoverLight: ViewModifier {
    @State private var hovered=false
    @Environment(\.hudReducedMotion) private var reduced
    func body(content:Content)->some View {
        content.background(HUD.cyan.opacity(hovered ? 0.07:0),in:RoundedRectangle(cornerRadius:5))
            .onHover {hovered=$0}.animation(reduced ? nil:.easeOut(duration:0.15),value:hovered)
    }
}
