import SwiftUI
import ArbiterCore

/// Decorative geometry is separate from the two labelled, measured utilization arcs.
struct HolographicInstrument: View {
    let sample: SystemSample?
    let moving: Bool
    let navigate: (Destination) -> Void

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let diameter = min(w * 0.92, h * 1.04)
            let center = CGPoint(x: w * 0.5, y: h * 0.46)
            ZStack {
                RadialGradient(colors: [HUD.cyan.opacity(0.2), HUD.purple.opacity(0.15), .clear], center: UnitPoint(x: 0.5, y: 0.5), startRadius: 15, endRadius: diameter * 0.6)
                ProjectionFloor().shadow(color:HUD.cyan.opacity(0.35),radius:4).overlay{NeonFlow(effect:.projection);NeonFlow(effect:.wave).opacity(0.3)}.frame(height: h * 0.34).position(x: w / 2, y: h * 0.85)
                Group {
                    if moving { ZStack { Circle().fill(RadialGradient(colors:[HUD.cyan.opacity(0.12),HUD.purple.opacity(0.08),.clear],center:.center,startRadius:0,endRadius:diameter*0.3)); Circle().stroke(HUD.cyan.opacity(0.55),lineWidth:0.8).padding(5); NativeGlobe().overlay {SamplePulse(token:sample?.id.timeIntervalSince1970 ?? 0, circular:true)} } }
                    else { WireGlobe().shadow(color:HUD.cyan.opacity(0.3),radius:6) }
                }.frame(width: diameter * 0.59, height: diameter * 0.59).position(center)
                Group {
                    if moving { NativeOrbit(moving:true) }
                    else { StaticOrbit() }
                }.frame(width:diameter,height:diameter).position(center).allowsHitTesting(false).accessibilityHidden(true)
                Circle().trim(from: 0.37, to: 0.98)
                    .stroke(AngularGradient(colors: [HUD.cyan.opacity(0.08), HUD.cyan.opacity(0.35), HUD.cyan.opacity(0.08)], center: .center), lineWidth: 9)
                    .frame(width: diameter * 0.94, height: diameter * 0.94).rotationEffect(.degrees(90)).position(center)
                AnimatedMeter(value:sample?.cpu,color:HUD.cyan,geometry:.arc(start:0.62,sweep:0.61,width:9))
                    .frame(width:diameter*0.94,height:diameter*0.94).position(center)
                AnimatedMeter(value:sample?.memoryPercent,color:HUD.purple,geometry:.arc(start:-0.22,sweep:0.43,width:3))
                    .frame(width:diameter*0.87,height:diameter*0.87).position(center)
                LaptopGlyph().frame(width: diameter * 0.34, height: diameter * 0.24).position(x: center.x, y: center.y + diameter * 0.08)
                ParticleField(kind: .hologram)
                HStack {
                    Button { navigate(.cpu) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("System\nLoad").font(.system(size: 12, weight: .medium))
                            Text(percent(sample?.cpu)).font(.system(size: 28, weight: .medium, design: .rounded)).foregroundStyle(HUD.cyan).monospacedDigit()
                        }.padding(6).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer()
                    Button { navigate(.memory) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unified\nMemory").font(.system(size: 12, weight: .medium))
                            Text(percent(sample?.memoryPercent)).font(.system(size: 28, weight: .medium, design: .rounded)).foregroundStyle(Color(hex: 0xee80ff)).monospacedDigit()
                        }.padding(6).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                    }
                }.buttonStyle(.plain).padding(.horizontal, w * 0.065).position(x: w / 2, y: center.y + 4)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct WireGlobe: View {
    struct Vertex { let x: Double; let y: Double; let z: Double }
    private static let vertices: [Vertex] = (0..<64).map { index in
        let y = 1 - Double(index) / 63 * 2
        let radius = sqrt(max(0, 1 - y * y))
        let theta = Double(index) * .pi * (3 - sqrt(5))
        return Vertex(x: cos(theta) * radius, y: y, z: sin(theta) * radius)
    }
    private static let edges: [(Int, Int)] = vertices.enumerated().flatMap { index, v in
        vertices.indices.filter { $0 > index }.sorted { a, b in
            let x = vertices[a], y = vertices[b]
            return pow(x.x-v.x,2)+pow(x.y-v.y,2)+pow(x.z-v.z,2) < pow(y.x-v.x,2)+pow(y.y-v.y,2)+pow(y.z-v.z,2)
        }.prefix(3).map { (index, $0) }
    }
    var body: some View {
        Canvas { context, size in
            let radius = size.width * 0.48
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let disc = Path(ellipseIn: CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2))
            context.fill(disc, with: .radialGradient(Gradient(colors: [Color(hex: 0x00172b).opacity(0.8), Color(hex: 0x002247).opacity(0.35), .clear]), center: center, startRadius: 0, endRadius: radius))
            context.stroke(disc, with: .linearGradient(Gradient(colors: [HUD.cyan, HUD.purple]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: 1.2)
            let projected = Self.vertices.map { CGPoint(x: center.x + $0.x * radius, y: center.y + $0.y * radius) }
            for (a, b) in Self.edges {
                let depth = (Self.vertices[a].z + Self.vertices[b].z + 2) / 4
                var edge = Path(); edge.move(to: projected[a]); edge.addLine(to: projected[b])
                context.stroke(edge, with: .color((Self.vertices[a].x > 0.2 ? HUD.purple : HUD.cyan).opacity(0.10 + depth * 0.65)), lineWidth: 0.6)
            }
            for (index, vertex) in Self.vertices.enumerated() {
                let point = projected[index]
                let radius = vertex.z > 0 ? 1.5 : 0.7
                let color = vertex.x > 0.25 ? HUD.purple : HUD.cyan
                if vertex.z > 0 {
                    context.fill(Path(ellipseIn: CGRect(x: point.x-4, y: point.y-4, width: 8, height: 8)), with: .radialGradient(Gradient(colors: [color.opacity(0.65), .clear]), center: point, startRadius: 0, endRadius: 4))
                }
                context.fill(Path(ellipseIn: CGRect(x: point.x-radius, y: point.y-radius, width: radius*2, height: radius*2)), with: .color(vertex.z > 0.4 ? .white : color.opacity(0.8)))
            }
        }.drawingGroup().accessibilityHidden(true)
    }
}

private struct LaptopGlyph: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x00101d)).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(HUD.cyan.opacity(0.85), lineWidth: 1.4))
                    .frame(width: w * 0.74, height: h * 0.72).offset(y: -h * 0.1)
                Canvas { context, size in
                    for stripe in 0..<15 {
                        var path = Path()
                        for step in 0...40 {
                            let x = Double(step) / 40 * size.width
                            let y = size.height * 0.55 + sin(Double(step)/10 + Double(stripe)*0.1) * size.height * 0.18 + Double(stripe)*1.1
                            if step == 0 { path.move(to: CGPoint(x:x,y:y)) } else { path.addLine(to: CGPoint(x:x,y:y)) }
                        }
                        context.stroke(path, with: .linearGradient(Gradient(colors: [HUD.cyan.opacity(0.4), HUD.cyan, HUD.purple]), startPoint: .zero, endPoint: CGPoint(x:size.width,y:size.height)), lineWidth: 0.65)
                    }
                }.frame(width: w * 0.65, height: h * 0.55).offset(y: -h * 0.13)
                Path { path in
                    path.move(to: CGPoint(x: w*0.13,y:h*0.74)); path.addLine(to: CGPoint(x:w*0.87,y:h*0.74))
                    path.addLine(to: CGPoint(x:w,y:h*0.94)); path.addLine(to: CGPoint(x:0,y:h*0.94)); path.closeSubpath()
                }.fill(LinearGradient(colors: [Color(hex:0xafd7ee),Color(hex:0x234e70),Color(hex:0x8cc9e4)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    path.move(to: CGPoint(x:w*0.18,y:h*0.77)); path.addLine(to: CGPoint(x:w*0.82,y:h*0.77)); path.addLine(to: CGPoint(x:w*0.9,y:h*0.88)); path.addLine(to: CGPoint(x:w*0.1,y:h*0.88)); path.closeSubpath()
                }.fill(Color(hex:0x072038)).overlay {
                    Path { path in for n in 0..<3 { let y=h*(0.79+Double(n)*0.03); path.move(to: CGPoint(x:w*0.2,y:y)); path.addLine(to: CGPoint(x:w*0.8,y:y)) } }.stroke(HUD.cyan.opacity(0.45),lineWidth:0.5)
                }
            }.shadow(color: HUD.cyan.opacity(0.55), radius: 7).overlay{NeonFlow(effect:.wave).opacity(0.3)}
        }.accessibilityHidden(true)
    }
}

private struct ProjectionFloor: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x:size.width/2,y:size.height*0.61)
            for row in 0..<14 {
                let f = Double(row)/13
                var path = Path()
                for step in 0...60 {
                    let x = Double(step)/60*size.width
                    let y = size.height*(0.3+f*0.65) + sin(Double(step)/8+f*3)*10*f
                    if step==0 {path.move(to:CGPoint(x:x,y:y))} else {path.addLine(to:CGPoint(x:x,y:y))}
                }
                context.stroke(path,with:.linearGradient(Gradient(colors:[HUD.cyan.opacity(0.25),HUD.purple.opacity(0.28)]),startPoint:.zero,endPoint:CGPoint(x:size.width,y:0)),lineWidth:0.5)
            }
            for column in 0..<22 {
                var line=Path();line.move(to:CGPoint(x:size.width/2+Double(column-11)*3,y:0));line.addLine(to:CGPoint(x:Double(column)/21*size.width,y:size.height))
                context.stroke(line,with:.color(HUD.cyan.opacity(0.08)),lineWidth:0.5)
            }
            for index in (0..<5).reversed() {
                let width=Double(index)*16+90, height=Double(index)*5+10
                let ellipse=Path(ellipseIn:CGRect(x:center.x-width/2,y:center.y-height/2,width:width,height:height))
                context.fill(ellipse,with:.color(Color(hex:0x001223).opacity(0.8)))
                context.stroke(ellipse,with:.linearGradient(Gradient(colors:[HUD.cyan,HUD.cyan.opacity(0.4),HUD.purple]),startPoint:CGPoint(x:center.x-width/2,y:0),endPoint:CGPoint(x:center.x+width/2,y:0)),lineWidth:index==1 ? 2 : 0.8)
            }
            let beam=Path { p in p.move(to:CGPoint(x:center.x-42,y:0));p.addLine(to:CGPoint(x:center.x+42,y:0));p.addLine(to:CGPoint(x:center.x+9,y:center.y));p.addLine(to:CGPoint(x:center.x-9,y:center.y));p.closeSubpath() }
            context.fill(beam,with:.linearGradient(Gradient(colors:[HUD.cyan.opacity(0.01),HUD.cyan.opacity(0.23)]),startPoint:CGPoint(x:center.x,y:0),endPoint:center))
        }.drawingGroup().accessibilityHidden(true)
    }
}

private struct StaticOrbit: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x:size.width/2,y:size.height/2), radius = min(size.width,size.height)/2
            var ticks=Path()
            for tick in 0..<72 {
                let angle=Double(tick)/72 * .pi * 2, inner=radius-(tick%6==0 ? 10:3)
                ticks.move(to:CGPoint(x:center.x+cos(angle)*inner,y:center.y+sin(angle)*inner))
                ticks.addLine(to:CGPoint(x:center.x+cos(angle)*radius,y:center.y+sin(angle)*radius))
            }
            context.stroke(ticks,with:.color(HUD.cyan.opacity(0.32)),lineWidth:0.7)
            context.stroke(Path(ellipseIn:CGRect(origin:.zero,size:size).insetBy(dx:11,dy:11)),with:.color(HUD.cyan.opacity(0.15)),lineWidth:0.6)
            for (start,end,inset,color) in [(0.01,0.19,20.0,HUD.cyan),(0.31,0.52,4.0,HUD.purple)] {
                var arc=Path();arc.addArc(center:center,radius:max(0,radius-inset),startAngle:.degrees(start*360),endAngle:.degrees(end*360),clockwise:false)
                context.stroke(arc,with:.color(color.opacity(0.8)),lineWidth:1.6)
            }
        }
    }
}
