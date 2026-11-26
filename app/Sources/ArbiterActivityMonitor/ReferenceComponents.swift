import SwiftUI
import ArbiterCore

struct ReferencePanel<Content: View>: View {
    let title: String
    var subtitle = ""
    var badge: String?
    @ViewBuilder let content: Content
    @State private var hovered = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.hudReducedMotion) private var reducedMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex:0xf0f8ff))
                    if !subtitle.isEmpty { Text(subtitle).font(.system(size: 10)).foregroundStyle(Color(hex:0xa7baca)) }
                }
                Spacer(minLength: 2)
                if let badge { StatusPill(text: badge) }
            }
            content
        }.padding(13).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 15).fill(LinearGradient(stops: [.init(color:Color(hex:0x14283a).opacity(0.9),location:0),.init(color:Color(hex:0x07121b),location:0.28),.init(color:Color(hex:0x0e1423),location:1)],startPoint:.topLeading,endPoint:.bottomTrailing))
                .shadow(color:HUD.cyan.opacity(0.07),radius:8)
                .shadow(color:.black.opacity(0.3),radius:7,y:4)
        }
        .overlay(NeonPanelEdge(emphasized:hovered || contrast == .increased))
        .onHover { hovered=$0 }.animation(reducedMotion ? nil : .easeOut(duration:0.15),value:hovered)
    }
}

struct LuminousSparkline: View {
    let values: [Double]
    var color = HUD.cyan
    var maximum: Double?
    var bars = false
    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let maximum=max(1,maximum ?? values.max() ?? 1)
            if bars {
                let width=size.width/Double(values.count)
                for (i,value) in values.enumerated() {
                    let height=min(1,max(0,value/maximum))*size.height
                    let rect=CGRect(x:Double(i)*width,y:size.height-height,width:max(1,width-2),height:max(0.8,height))
                    context.fill(Path(roundedRect:rect,cornerRadius:0.8),with:.linearGradient(Gradient(colors:[color,color.opacity(0.2)]),startPoint:CGPoint(x:0,y:0),endPoint:CGPoint(x:0,y:size.height)))
                }
                return
            }
            let points=values.enumerated().map { i,value in CGPoint(x:Double(i)/Double(values.count-1)*size.width,y:(1-min(1,max(0,value/maximum)))*max(1,size.height-3)+1) }
            var line=Path();line.move(to:points[0])
            for point in points.dropFirst() {line.addLine(to:point)}
            var fill=line;fill.addLine(to:CGPoint(x:size.width,y:size.height));fill.addLine(to:CGPoint(x:0,y:size.height));fill.closeSubpath()
            context.fill(fill,with:.linearGradient(Gradient(colors:[color.opacity(0.32),color.opacity(0.01)]),startPoint:.zero,endPoint:CGPoint(x:0,y:size.height)))
            context.stroke(line,with:.color(color.opacity(0.12)),lineWidth:5)
            context.stroke(line,with:.color(color),lineWidth:1.1)
        }.overlay(alignment:.trailing) {SamplePulse(token:values.last ?? 0,color:color).frame(width:5)}.overlay { if !bars {NeonFlow(effect:.trace(values),color:color)} else {NeonFlow(effect:.shimmer,color:color)} }.accessibilityHidden(true)
    }
}

struct ReferenceMetric: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let color: Color
    var gauge: Double?
    var gaugeStyle = false
    var progress: Double?
    var values: [Double] = []
    var bars = false
    var body: some View {
        HStack(alignment:.top,spacing:10) {
            Image(systemName:symbol).font(.system(size:20,weight:.light)).foregroundStyle(color).shadow(color:color.opacity(0.3),radius:5).frame(width:24).padding(.top,1)
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(.system(size:11,weight:.semibold))
                Text(value).font(.system(size:gaugeStyle ? 22 : 16,weight:.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                if let progress {
                    Capsule().fill(color.opacity(0.08))
                        .overlay { AnimatedMeter(value:progress,color:color,geometry:.bar) }
                        .frame(height:6).overlay{NeonFlow(effect:.shimmer,color:color)}
                }
                Text(detail).font(.system(size:9)).foregroundStyle(Color(hex:0xa7bdca)).lineLimit(2)
            }.frame(maxWidth:.infinity,alignment:.leading)
            if gaugeStyle {
                VStack(spacing:0) {
                    ZStack {
                        Circle().trim(from:0.5,to:1).stroke(color.opacity(0.17),style:StrokeStyle(lineWidth:7,lineCap:.round))
                        AnimatedMeter(value:gauge,color:color,geometry:.arc(start:0.5,sweep:0.5,width:7))
                    }.frame(width:61,height:61).frame(height:34,alignment:.top)
                    LuminousSparkline(values:values,color:color).frame(width:65,height:20)
                }.padding(.top,7)
            } else if !values.isEmpty && progress == nil {
                LuminousSparkline(values:Array(values.suffix(24)),color:color,bars:bars).frame(width:62,height:29).padding(.top,24)
            }
        }.padding(8).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .background(LinearGradient(colors:[Color(hex:0x07121b),Color(hex:0x071c24).opacity(0.65)],startPoint:.top,endPoint:.bottom),in:RoundedRectangle(cornerRadius:12))
        .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(color.opacity(0.28),lineWidth:0.7))
        .accessibilityElement(children:.combine)
    }
}

struct ReferenceResourceMatrix: View {
    let sample: SystemSample?
    let history: [SystemSample]
    let navigate: (Destination)->Void
    var spotlight: (Destination?)->Void = {_ in}
    var columns = 2
    var body: some View {
        ReferencePanel(title:"System Performance",subtitle:"MacBook System · Real-time") {
            if columns == 1 {
                VStack(spacing:6) { ForEach(0..<8, id:\.self) { card($0) } }.buttonStyle(.plain)
            } else {
                Grid(horizontalSpacing:6,verticalSpacing:6) {
                    ForEach(0..<4, id:\.self) { row in GridRow { card(row*2); card(row*2+1) } }
                }.buttonStyle(.plain)
            }
        }
    }
    @ViewBuilder private func card(_ index:Int)->some View {
        switch index {
        case 0: metric(.cpu) { ReferenceMetric(title:"CPU",value:percent(sample?.cpu),detail:"\(ProcessInfo.processInfo.processorCount) logical cores",symbol:"cpu",color:HUD.cyan,gauge:sample?.cpu,gaugeStyle:true,values:history.suffix(25).compactMap(\.cpu)) }
        case 1: metric(.gpu) { ReferenceMetric(title:"GPU",value:percent(sample?.gpu),detail:sample?.gpu == nil ? "Driver unavailable":"Integrated · Driver",symbol:"display",color:HUD.purple,gauge:sample?.gpu,gaugeStyle:true,values:history.suffix(25).compactMap(\.gpu)) }
        case 2: metric(.memory) { ReferenceMetric(title:"Memory (Unified)",value:sample.map {"\(bytes($0.memoryUsed)) / \(bytes($0.memoryTotal))"} ?? "—",detail:"Pressure: \(sample?.pressure ?? "Unknown")",symbol:"square.3.layers.3d",color:sample?.pressure == "Normal" ? HUD.purple:sample?.pressure == "Critical" ? HUD.red:HUD.amber,progress:sample?.memoryPercent) }
        case 3: metric(.storage) { ReferenceMetric(title:"Storage",value:sample.map {bytes($0.diskFree)+" free"} ?? "—",detail:sample.map {"of \(bytes($0.diskTotal)) · Data volume"} ?? "Collecting…",symbol:"internaldrive",color:sample.map{$0.diskTotal>0 && Double($0.diskFree)/Double($0.diskTotal)<0.1} == true ? HUD.amber:HUD.cyan,progress:sample.flatMap {$0.diskTotal>0 ? 100*(1-Double($0.diskFree)/Double($0.diskTotal)) : nil}) }
        case 4: metric(.network) { ReferenceMetric(title:"Network",value:"↓ \(rate(sample?.download))",detail:"↑ \(rate(sample?.upload))",symbol:"wifi",color:HUD.cyan,values:history.suffix(25).compactMap(\.download)) }
        case 5: metric(.storage) { ReferenceMetric(title:"Disk I/O",value:"R: \(rate(sample?.diskRead))",detail:"W: \(rate(sample?.diskWrite))",symbol:"externaldrive",color:HUD.purple,values:history.suffix(25).compactMap(\.diskWrite),bars:true) }
        case 6: metric(.battery) { ReferenceMetric(title:"Battery",value:percent(sample?.battery),detail:sample?.onPower == true ? "External power" : "On battery",symbol:"battery.75percent",color:HUD.green,progress:sample?.battery) }
        default: metric(.thermals) { ReferenceMetric(title:"Thermals",value:sample?.thermal ?? "—",detail:"OS thermal pressure\nSensors unavailable",symbol:"thermometer.medium",color:sample?.thermal == "Critical" ? HUD.red : HUD.green,values:history.suffix(25).map {$0.thermal == "Nominal" ? 0.15 : $0.thermal == "Fair" ? 0.4 : 0.8}) }
        }
    }
    private func metric<Content:View>(_ destination:Destination,@ViewBuilder content:()->Content)->some View {
        Button {navigate(destination)} label:{content()}.onHover {spotlight($0 ? destination:nil)}.buttonStyle(HUDRowStyle()).help("Open \(destination.rawValue) · \(sample?.id.formatted(date:.omitted,time:.standard) ?? "Waiting for sample")")
    }
}

struct SidebarWave: View {
    @Environment(\.hudAmbientMotion) private var moving
    var body: some View {
        ZStack {
            RadialGradient(colors:[HUD.cyan.opacity(0.13),.clear],center:UnitPoint(x:0.3,y:0.5),startRadius:1,endRadius:95)
            RadialGradient(colors:[HUD.purple.opacity(0.16),.clear],center:UnitPoint(x:0.9,y:0.55),startRadius:1,endRadius:80)
            if moving { NeonFlow(effect:.ribbon) } else { staticWave }
        }
    }
    private var staticWave: some View {
        Canvas { context,size in
            for n in 0..<23 {
                var path=Path()
                for step in 0...60 {
                    let f=Double(step)/60
                    let point=SidebarWaveform.point(x:f,strand:n,phase:0,size:size)
                    if step==0 {path.move(to:point)} else {path.addLine(to:point)}
                }
                context.stroke(path,with:.linearGradient(Gradient(colors:[HUD.purple.opacity(0.85),HUD.cyan.opacity(0.95),HUD.purple.opacity(0.9)]),startPoint:.zero,endPoint:CGPoint(x:size.width,y:size.height)),lineWidth:0.8)
            }
            RibbonParticles.drawStill(in:context,size:size)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
