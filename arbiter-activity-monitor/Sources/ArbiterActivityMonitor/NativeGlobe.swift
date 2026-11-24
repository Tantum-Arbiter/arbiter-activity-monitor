import SwiftUI
import AppKit
import QuartzCore

/// Precomputed 3-D projections animate in Core Animation; no frame timer or SwiftUI invalidations.
struct NativeGlobe: NSViewRepresentable {
    func makeNSView(context: Context) -> GlobeLayerView { GlobeLayerView() }
    func updateNSView(_ view: GlobeLayerView, context: Context) {}
}

final class GlobeLayerView: NSView {
    private struct Vertex { let x:Double;let y:Double;let z:Double }
    private static let vertices:[Vertex]=(0..<64).map { i in
        let y=1-Double(i)/63*2,r=sqrt(max(0,1-y*y)),a=Double(i)*Double.pi*(3-sqrt(5))
        return Vertex(x:cos(a)*r,y:y,z:sin(a)*r)
    }
    private static let edges:[(Int,Int)]=vertices.enumerated().flatMap { i,v in
        vertices.indices.filter{$0>i}.sorted { a,b in
            func distance(_ p:Vertex)->Double {pow(p.x-v.x,2)+pow(p.y-v.y,2)+pow(p.z-v.z,2)}
            return distance(vertices[a])<distance(vertices[b])
        }.prefix(3).map{(i,$0)}
    }
    private var drawnSize=CGSize.zero
    override var isFlipped:Bool {true}
    override init(frame:NSRect) {super.init(frame:frame);wantsLayer=true;layer=CALayer()}
    required init?(coder:NSCoder) {nil}
    override func layout() {
        super.layout()
        guard bounds.size != drawnSize,!bounds.isEmpty else{return}
        drawnSize=bounds.size
        CATransaction.begin();CATransaction.setDisableActions(true)
        layer?.sublayers?.forEach{$0.removeFromSuperlayer()}
        let cyan=NSColor(srgbRed:0.125,green:0.957,blue:1,alpha:1)
        let purple=NSColor(srgbRed:0.82,green:0.24,blue:1,alpha:1)
        for group in 0..<4 {
            let frames=(0...48).map {paths(angle:Double($0)/48 * .pi*2,group:group)}
            let mesh=CAShapeLayer();mesh.path=frames[0]
            let color=group%2==0 ? cyan:purple
            mesh.fillColor=group<2 ? nil:color.cgColor
            mesh.strokeColor=group<2 ? color.withAlphaComponent(0.45).cgColor:nil
            mesh.lineWidth=0.65
            let spin=CAKeyframeAnimation(keyPath:"path");spin.values=frames;spin.duration=36;spin.repeatCount = .infinity
            spin.calculationMode = .linear;spin.preferredFrameRateRange=CAFrameRateRange(minimum:6,maximum:10,preferred:10)
            layer?.addSublayer(mesh);mesh.add(spin,forKey:"sphereRotation")
            if group>=2 {
                let pulse=CABasicAnimation(keyPath:"opacity");pulse.fromValue=0.6;pulse.toValue=1;pulse.duration=2.4+Double(group)*0.5;pulse.autoreverses=true;pulse.repeatCount = .infinity
                pulse.preferredFrameRateRange=CAFrameRateRange(minimum:6,maximum:10,preferred:10)
                mesh.add(pulse,forKey:"nodes")
            }
        }
        CATransaction.commit()
    }
    private func paths(angle:Double,group:Int)->CGPath {
        let radius=min(bounds.width,bounds.height)*0.47
        let points=Self.vertices.map {v in
            CGPoint(x:bounds.midX+(v.x*cos(angle)+v.z*sin(angle))*radius,y:bounds.midY+v.y*radius)
        }
        let path=CGMutablePath()
        if group<2 {
            for (a,b) in Self.edges where a%2==group {path.move(to:points[a]);path.addLine(to:points[b])}
        } else {
            for i in Self.vertices.indices where i%2==group-2 {
                let r=1.3+0.5*(Self.vertices[i].z*cos(angle)-Self.vertices[i].x*sin(angle))
                path.addEllipse(in:CGRect(x:points[i].x-r,y:points[i].y-r,width:r*2,height:r*2))
            }
        }
        return path
    }
}
