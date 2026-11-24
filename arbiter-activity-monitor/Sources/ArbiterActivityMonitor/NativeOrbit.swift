import SwiftUI
import AppKit
import QuartzCore

/// A rasterized ornament rotated by the window compositor, without a SwiftUI frame timer.
struct NativeOrbit: NSViewRepresentable {
    let moving: Bool
    func makeNSView(context: Context) -> OrbitLayerView { OrbitLayerView() }
    func updateNSView(_ view: OrbitLayerView, context: Context) { view.setMoving(moving) }
}

final class OrbitLayerView: NSView {
    private let orbit = CALayer()
    private var moving = false
    private var drawnSize = CGSize.zero
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.addSublayer(orbit)
        orbit.shouldRasterize = true
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        guard bounds.size != drawnSize else { return }
        drawnSize = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        orbit.bounds = CGRect(origin: .zero, size: bounds.size)
        orbit.position = CGPoint(x: bounds.midX, y: bounds.midY)
        orbit.rasterizationScale = window?.backingScaleFactor ?? 2
        orbit.sublayers?.forEach { $0.removeFromSuperlayer() }
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let radius = min(bounds.width, bounds.height) / 2
        let cyan = NSColor(srgbRed: 0.125, green: 0.957, blue: 1, alpha: 1)
        let purple = NSColor(srgbRed: 0.702, green: 0.533, blue: 1, alpha: 1)
        let ticks = CGMutablePath()
        for tick in 0..<72 {
            let angle = Double(tick) / 72 * .pi * 2
            let inner = radius - (tick % 6 == 0 ? 10 : 3)
            ticks.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            ticks.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
        }
        add(ticks, color: cyan.withAlphaComponent(0.32), width: 0.7)
        add(CGPath(ellipseIn: orbit.bounds.insetBy(dx: 11, dy: 11), transform: nil), color: cyan.withAlphaComponent(0.15), width: 0.6)
        for (start, end, inset, color) in [(0.01, 0.19, 20.0, cyan), (0.31, 0.52, 4.0, purple)] {
            let path = CGMutablePath()
            path.addArc(center: center, radius: max(0, radius-inset), startAngle: start * 2 * .pi, endAngle: end * 2 * .pi, clockwise: false)
            add(path, color: color.withAlphaComponent(0.8), width: 1.6)
        }
        for (point, color) in [(CGPoint(x: center.x+radius*0.9, y: center.y), cyan), (CGPoint(x:center.x,y:center.y+radius*0.96),purple)] {
            let dot = CAShapeLayer()
            dot.path = CGPath(ellipseIn:CGRect(x:point.x-1.5,y:point.y-1.5,width:3,height:3),transform:nil)
            dot.fillColor = color.cgColor
            dot.shadowColor = color.cgColor; dot.shadowOpacity = 0.9; dot.shadowRadius = 4; dot.shadowOffset = .zero
            orbit.addSublayer(dot)
        }
        CATransaction.commit()
        synchronizeAnimation()
    }

    private func add(_ path: CGPath, color: NSColor, width: CGFloat) {
        let shape = CAShapeLayer()
        shape.path = path; shape.fillColor = nil; shape.strokeColor = color.cgColor; shape.lineWidth = width
        orbit.addSublayer(shape)
    }

    func setMoving(_ value: Bool) {
        guard moving != value else { return }
        moving = value
        synchronizeAnimation()
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); synchronizeAnimation() }

    private func synchronizeAnimation() {
        if moving && window != nil && !bounds.isEmpty {
            guard orbit.animation(forKey: "ambientOrbit") == nil else { return }
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = 0; animation.toValue = Double.pi * 2
            animation.duration = 75; animation.repeatCount = .infinity
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 6, maximum: 10, preferred: 10)
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            orbit.add(animation, forKey: "ambientOrbit")
        } else { orbit.removeAnimation(forKey: "ambientOrbit") }
    }
}
