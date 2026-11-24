import SwiftUI
import ArbiterCore

struct ReferenceOverview: View {
    @Bindable var store:MonitorStore
    let width:CGFloat
    var height:CGFloat = 920
    @Environment(\.hudReducedMotion) private var reduceMotion
    private var moving:Bool {store.motionIntensity != .minimal && store.ambientMotion && store.active && !store.paused && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled && ProcessInfo.processInfo.thermalState.rawValue<2}
    var body:some View {
        let usable=width-24
        let topHeight=max(387,min(430,height*0.425))
        let chartHeight=max(150,min(200,height*0.165))
        let lowerHeight=max(344,min(410,height-topHeight-chartHeight-28))
        VStack(spacing:14) {
            if width>=1140 {
                HStack(spacing:12) {
                    ReferenceResourceMatrix(sample:store.latest,history:store.chartHistory,navigate:{store.destination=$0},spotlight:{store.spotlight=$0?.rawValue}).frame(width:usable*0.33)
                    instrument.frame(width:usable*0.29)
                    SessionAgentsPanel(store:store)
                }.frame(height:topHeight)
                HStack(spacing:12) {
                    HistoryPanel(history:store.chartHistory,height:chartHeight,spotlight:store.spotlight).frame(width:usable*0.595)
                    ReferenceHeatmap(history:store.chartHistory).frame(width:usable*0.225)
                    SessionThroughput(sessions:store.sessions)
                }.frame(height:chartHeight)
                HStack(spacing:12) {
                    ReferenceProcesses(sample:store.latest,inspect:store.inspect).frame(width:usable*0.30)
                    AgentOrchestration(store:store).frame(width:usable*0.42)
                    ReferenceEvents(alerts:store.alerts,events:store.events,replay:store.replay,open:{store.destination = .alerts})
                }.frame(height:lowerHeight)
            } else if width>=940 {
                HStack(spacing:12) {
                    ReferenceResourceMatrix(sample:store.latest,history:store.chartHistory,navigate:{store.destination=$0},spotlight:{store.spotlight=$0?.rawValue})
                    instrument.frame(width:usable*0.46)
                }.frame(height:387)
                HStack(spacing:12) {
                    SessionAgentsPanel(store:store)
                    AgentOrchestration(store:store)
                }.frame(height:360)
                HistoryPanel(history:store.chartHistory,height:180,spotlight:store.spotlight)
                HStack(spacing:12) {
                    ReferenceProcesses(sample:store.latest,inspect:store.inspect)
                    ReferenceEvents(alerts:store.alerts,events:store.events,replay:store.replay,open:{store.destination = .alerts})
                }.frame(height:320)
                HStack(spacing:12){ReferenceHeatmap(history:store.chartHistory);SessionThroughput(sessions:store.sessions)}.frame(height:180)
            } else {
                HStack(spacing:12) {
                    ReferenceResourceMatrix(sample:store.latest,history:store.chartHistory,navigate:{store.destination=$0},spotlight:{store.spotlight=$0?.rawValue})
                    if width>820 {instrument.frame(width:width*0.42)}
                }.frame(height:386)
                if width<=820 {instrument.frame(height:386)}
                SessionAgentsPanel(store:store).frame(height:387)
                HistoryPanel(history:store.chartHistory,spotlight:store.spotlight)
                HStack(spacing:12){ReferenceHeatmap(history:store.chartHistory);SessionThroughput(sessions:store.sessions)}.frame(height:180)
                ReferenceProcesses(sample:store.latest,inspect:store.inspect).frame(height:320)
                AgentOrchestration(store:store).frame(height:344)
                ReferenceEvents(alerts:store.alerts,events:store.events,replay:store.replay,open:{store.destination = .alerts}).frame(height:312)
            }
        }
    }
    private var treeWorkload:Workload? {store.workloads.first {workload in workload.members.contains {$0.parent==workload.root.pid}} ?? store.workloads.first}
    private var instrument:some View {
        VStack(spacing:7) {
            HolographicInstrument(sample:store.latest,moving:moving,navigate:{store.destination=$0})
            HStack(spacing:6) {
                heroStat("Sessions",value:String(store.sessions.count),symbol:"scope",color:HUD.cyan)
                heroStat("Running",value:store.sessions.contains{!$0.events.isEmpty} ? String(store.sessions.filter{$0.isRunning}.count):"—",symbol:"square.3.layers.3d",color:HUD.purple)
                heroStat("Tool events",value:store.sessions.contains{!$0.events.isEmpty} ? String(store.sessions.flatMap(\.events).filter{$0.event=="PostToolUse"}.count):"—",symbol:"bolt.fill",color:HUD.amber)
                heroStat("Turns seen",value:store.sessions.contains{!$0.events.isEmpty} ? String(store.sessions.flatMap(\.events).filter{$0.event=="Stop"}.count):"—",symbol:"square.grid.2x2",color:HUD.purple)
            }.frame(height:46)
        }
    }
    private func heroStat(_ name:String,value:String,symbol:String,color:Color)->some View {
        HStack(spacing:6) {
            Image(systemName:symbol).font(.system(size:19)).foregroundStyle(color)
            VStack(alignment:.leading,spacing:2){Text(name).font(.system(size:8));Text(value).font(.system(size:14,weight:.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)}
        }.frame(maxWidth:.infinity,maxHeight:.infinity).padding(.horizontal,5)
        .background(LinearGradient(colors:[Color(hex:0x152b3b),HUD.background],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:11))
        .overlay(RoundedRectangle(cornerRadius:11).strokeBorder(HUD.cyan.opacity(0.28),lineWidth:0.7))
    }
}

struct ReferenceDependency:View {
    let workload:Workload?
    let history:[SystemSample]
    let inspect:(ProcessSample)->Void
    private var children:[ProcessSample] {
        guard let workload else{return []}
        return Array(workload.members.filter{$0.parent==workload.root.pid}.sorted{($0.cpu ?? -1)>($1.cpu ?? -1)}.prefix(3))
    }
    var body:some View {
        ReferencePanel(title:"Workload Dependencies",subtitle:"Observed process tree · Live resource attribution") {
            if let workload {
                GeometryReader {geometry in
                    let w=geometry.size.width,h=geometry.size.height
                    ZStack {
                        Canvas {context,size in
                            for index in children.indices {
                                let y=size.height*(Double(index)+0.5)/Double(max(1,children.count))
                                var path=Path();path.move(to:CGPoint(x:size.width*0.21,y:size.height/2));path.addCurve(to:CGPoint(x:size.width*0.43,y:y),control1:CGPoint(x:size.width*0.35,y:size.height/2),control2:CGPoint(x:size.width*0.3,y:y))
                                context.stroke(path,with:.linearGradient(Gradient(colors:[HUD.cyan,HUD.purple]),startPoint:.zero,endPoint:CGPoint(x:size.width,y:0)),lineWidth:1.1)
                                var total=Path();total.move(to:CGPoint(x:size.width*0.64,y:y));total.addCurve(to:CGPoint(x:size.width*0.82,y:size.height/2),control1:CGPoint(x:size.width*0.76,y:y),control2:CGPoint(x:size.width*0.73,y:size.height/2))
                                context.stroke(total,with:.color(HUD.cyan.opacity(0.7)),lineWidth:1)
                            }
                        }
                        Button {inspect(workload.root)} label:{node(workload.title,subtitle:"PID \(workload.root.pid)",symbol:"point.3.connected.trianglepath.dotted",color:HUD.cyan)}.buttonStyle(.plain).frame(width:w*0.23).position(x:w*0.115,y:h/2)
                        ForEach(Array(children.enumerated()),id:\.element.id){index,child in
                            Button {inspect(child)} label:{node(child.name,subtitle:child.memory.map(bytes) ?? "Unavailable",symbol:child.category==6 ? "terminal":"chevron.left.forwardslash.chevron.right",color:index==0 ? Color(hex:0x409cff):index==1 ? HUD.purple:Color(hex:0xef45f8))}.buttonStyle(.plain).frame(width:w*0.25).position(x:w*0.535,y:h*(Double(index)+0.5)/Double(max(1,children.count)))
                        }
                        node("Group total",subtitle:percent(workload.cpu)+" CPU",symbol:"gauge.with.needle",color:HUD.green).frame(width:w*0.21).position(x:w*0.895,y:h/2)
                        if children.isEmpty {Text("No observable child processes").font(.system(size:10)).foregroundStyle(HUD.muted).position(x:w*0.53,y:h/2)}
                    }
                }.frame(height:137)
                Divider().overlay(HUD.cyan.opacity(0.12))
                VStack(alignment:.leading,spacing:7) {
                    Text("Observation Timeline").font(.system(size:14,weight:.semibold))
                    Text("Measured CPU samples · \(history.suffix(40).count) observations").font(.system(size:10)).foregroundStyle(Color(hex:0xa7baca))
                    Canvas { context,size in
                        let observations=Array(history.suffix(40)), width=size.width/Double(max(1,observations.count))
                        for (index,sample) in observations.enumerated() {
                            let x=Double(index)*width
                            context.fill(Path(CGRect(x:x,y:0,width:max(0,width-1),height:size.height)),with:.linearGradient(Gradient(colors:[HUD.cyan.opacity(0.3+(sample.cpu ?? 0)/140),HUD.purple.opacity(0.5+(sample.cpu ?? 0)/200)]),startPoint:CGPoint(x:x,y:0),endPoint:CGPoint(x:x+width,y:0)))
                        }
                    }.frame(height:15).clipShape(RoundedRectangle(cornerRadius:4)).accessibilityLabel("Last 40 measured CPU observations. Inspect exact time and value in the history chart.")
                    HStack{Label("Observed ancestry",systemImage:"circle.fill").foregroundStyle(HUD.cyan);Spacer();Text("No inferred task stages").foregroundStyle(HUD.muted)}.font(.system(size:9))
                }
            } else {ContentUnavailableView("No process tree yet",systemImage:"point.3.connected.trianglepath.dotted",description:Text("Detected and explicitly tracked workloads appear here."))}
        }
    }
    private func node(_ title:String,subtitle:String,symbol:String,color:Color)->some View {
        HStack(spacing:6){Image(systemName:symbol).font(.system(size:19)).foregroundStyle(color);VStack(spacing:3){Text(title).font(.system(size:10,weight:.semibold)).lineLimit(1);Text(subtitle).font(.system(size:9)).foregroundStyle(Color(hex:0xb6cadd)).lineLimit(1)}}.padding(8)
            .frame(maxWidth:.infinity,minHeight:39).background(LinearGradient(colors:[color.opacity(0.18),HUD.background],startPoint:.top,endPoint:.bottom),in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(color.opacity(0.75),lineWidth:0.8)).shadow(color:color.opacity(0.12),radius:4)
    }
}
