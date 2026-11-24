import SwiftUI
import ArbiterCore

struct OverviewWorkload: Identifiable {
    let category: Int
    let title: String
    let roots: [Workload]
    var id: Int { category }
    var cpu: Double? { roots.contains {$0.cpu != nil} ? roots.compactMap(\.cpu).reduce(0,+) : nil }
    var memory: UInt64 { roots.map(\.memory).reduce(0,+) }
    var read: Double? { roots.contains {$0.read != nil} ? roots.compactMap(\.read).reduce(0,+) : nil }
    var write: Double? { roots.contains {$0.write != nil} ? roots.compactMap(\.write).reduce(0,+) : nil }
    var count: Int { roots.map { $0.members.count }.reduce(0,+) }
    /// Agents and model runtimes first, then generic tools.
    var order: Int { category<=3 ? category : category==10 ? 4 : category+10 }
    var symbol: String { [1:"chevron.left.forwardslash.chevron.right",2:"sparkles",3:"cpu",5:"cube.transparent",6:"terminal",7:"curlybraces",8:"film",9:"curlybraces.square",10:"memorychip"][category] ?? "terminal" }
    var color: Color { category==1 ? Color(hex:0x389bff) : category==2 ? HUD.purple : category==3 ? HUD.cyan : category==5 ? Color(hex:0xef45f8) : category==10 ? HUD.magenta : HUD.cyan }
    static func groups(_ workloads:[Workload])->[Self] {
        Dictionary(grouping:workloads,by:{$0.root.category}).map { category,roots in
            Self(category:category,title:[1:"Codex",2:"Claude",3:"Local inference",5:"Blender",6:"Python",7:"Node.js",8:"FFmpeg",9:"VS Code",10:"MLX"][category] ?? roots[0].title,roots:roots)
        }.sorted { $0.order < $1.order }
    }
}

struct ReferenceWorkloads: View {
    let groups: [OverviewWorkload]
    let history: [SystemSample]
    let inspect: (ProcessSample)->Void
    var body: some View {
        ReferencePanel(title:"Local Workloads",subtitle:"AI apps & tools · Performance & utilization",badge:"\(groups.count) observed") {
            if groups.isEmpty { ContentUnavailableView("No local workloads",systemImage:"cpu",description:Text("Recognized tools appear when detected.")) }
            else {
                HStack {
                    Text("APPLICATION").frame(maxWidth:.infinity,alignment:.leading)
                    Text("CPU").frame(width:43)
                    Text("Memory").frame(width:58)
                    Text("Read").frame(width:61)
                    Text("Write").frame(width:61)
                }.font(.system(size:9)).foregroundStyle(Color(hex:0xa7baca)).padding(.leading,43).padding(.top,7)
                VStack(spacing:1) {
                    ForEach(Array(groups.prefix(5))) { group in
                        Button {if let root=group.roots.first?.root {inspect(root)}} label:{
                            HStack(spacing:8) {
                                Image(systemName:group.symbol).font(.system(size:19,weight:.light)).foregroundStyle(group.color).frame(width:36,height:38)
                                    .background(LinearGradient(colors:[group.color.opacity(0.3),group.color.opacity(0.07)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:7))
                                    .overlay(RoundedRectangle(cornerRadius:7).strokeBorder(group.color.opacity(0.25),lineWidth:0.6))
                                VStack(alignment:.leading,spacing:6) {
                                    Text(group.title).font(.system(size:11,weight:.semibold)).lineLimit(1)
                                    HStack(spacing:4) {Circle().fill((group.cpu ?? 0)>0.5 ? HUD.green : HUD.muted).frame(width:5,height:5);Text("\(group.count) processes").font(.system(size:9)).foregroundStyle(HUD.green)}
                                }.frame(maxWidth:.infinity,alignment:.leading)
                                LuminousSparkline(values:values(group),color:group.color).frame(width:44,height:21)
                                Text(percent(group.cpu)).frame(width:43)
                                Text(bytes(group.memory)).frame(width:58)
                                Text(rate(group.read)).frame(width:61)
                                Text(rate(group.write)).frame(width:61)
                            }.font(.system(size:10,weight:.medium)).monospacedDigit().padding(.vertical,6)
                        }.buttonStyle(.plain)
                        Divider().overlay(HUD.cyan.opacity(0.07))
                    }
                }
                Spacer(minLength:0)
                Text("CPU: one-core scale · RSS may include shared pages").font(.system(size:9)).foregroundStyle(HUD.muted)
            }
        }
    }
    private func values(_ group:OverviewWorkload)->[Double] {
        guard let app=AgentApp(category:group.category) else{return []}
        return history.suffix(20).compactMap {$0.apps.first(where:{$0.app==app})?.cpuPercent}
    }
}

struct ReferenceHeatmap: View {
    let history:[SystemSample]
    @State private var hover:CGPoint?
    private let labels=["CPU","GPU","Memory","Disk","Network","AI apps"]
    private var samples:[SystemSample] {Array(history.suffix(30))}
    private func reading(_ row:Int,_ sample:SystemSample)->Double? {
        switch row {
        case 0:sample.cpu
        case 1:sample.gpu
        case 2:sample.memoryPercent
        case 3:sample.diskRead.flatMap {r in sample.diskWrite.map {r+$0}}
        case 4:sample.download.flatMap {r in sample.upload.map {r+$0}}
        default:sample.apps.contains {$0.cpuPercent != nil} ? sample.apps.compactMap(\.cpuPercent).reduce(0,+)/Double(ProcessInfo.processInfo.processorCount) : nil
        }
    }
    var body: some View {
        ReferencePanel(title:"Resource Heatmap",subtitle:"Last 30 observations · per-row scales") {
            HStack(spacing:8) {
                VStack(alignment:.leading,spacing:0) {ForEach(labels,id:\.self){Text($0).font(.system(size:10)).frame(maxHeight:.infinity,alignment:.leading)}}.frame(width:48)
                GeometryReader { geometry in
                    Canvas {context,size in
                        let count=max(1,samples.count),cellW=size.width/Double(count),cellH=size.height/6
                        for row in 0..<6 {
                            let maximum=(row==3 || row==4) ? max(1,samples.compactMap{reading(row,$0)}.max() ?? 1) : 100
                            for col in 0..<count {
                                let value=samples.indices.contains(col) ? reading(row,samples[col]) : nil
                                let intensity=value.map {min(1,max(0,$0/maximum))}
                                let color=intensity.map {Color(red:0.08+$0*0.65,green:0.8-$0*0.5,blue:1).opacity(0.25+$0*0.75)} ?? HUD.muted.opacity(0.09)
                                context.fill(Path(CGRect(x:Double(col)*cellW,y:Double(row)*cellH,width:max(1,cellW-1),height:max(1,cellH-3))),with:.color(color))
                            }
                        }
                    }.overlay(alignment:.trailing) {SamplePulse(token:samples.last?.id.timeIntervalSince1970 ?? 0).frame(width:geometry.size.width/Double(max(1,samples.count)))}.onContinuousHover {phase in switch phase {case .active(let location):hover=location;case .ended:hover=nil}}
                    .overlay(alignment:.bottomLeading) {
                        if let hover,!samples.isEmpty {
                            let row=min(5,max(0,Int(hover.y/max(1,geometry.size.height)*6)))
                            let col=min(samples.count-1,max(0,Int(hover.x/max(1,geometry.size.width)*Double(samples.count))))
                            let value=reading(row,samples[col])
                            Text("\(labels[row]) \(row==3 || row==4 ? rate(value) : percent(value)) · \(samples[col].id.formatted(date:.omitted,time:.standard))")
                                .font(.system(size:9)).padding(4).background(HUD.background,in:RoundedRectangle(cornerRadius:4)).allowsHitTesting(false)
                        }
                    }
                }
            }.frame(maxHeight:.infinity)
        }.accessibilityElement(children:.ignore).accessibilityLabel("Resource heatmap. CPU, memory and AI apps use 0 to 100 percent. Disk and network use the observed row maximum in bytes per second. GPU uses driver-reported utilization where available.")
    }
}

struct ReferenceThroughput: View {
    let sample:SystemSample?
    let history:[SystemSample]
    private var values:[Double] {history.suffix(24).compactMap {s in s.diskRead.flatMap{r in s.diskWrite.map{r+$0}}}}
    var body:some View {
        ReferencePanel(title:"Disk Throughput",subtitle:"Measured reads + writes / second") {
            Text(rate(sample?.diskRead.flatMap{r in sample?.diskWrite.map{r+$0}})).font(.system(size:25,weight:.semibold)).monospacedDigit()
            LuminousSparkline(values:values,color:HUD.purple,bars:true).frame(maxHeight:.infinity)
        }
    }
}

struct ReferenceProcesses: View {
    let sample:SystemSample?
    let inspect:(ProcessSample)->Void
    @State private var scope="All"
    private var rows:[ProcessSample] {
        (sample?.processes ?? []).filter {scope=="All" || scope=="System" && !$0.user || scope=="Agents" && $0.agent != nil || scope=="User" && $0.user}
            .sorted{($0.cpu ?? -1)==($1.cpu ?? -1) ? $0.pid<$1.pid : ($0.cpu ?? -1)>($1.cpu ?? -1)}
    }
    var body:some View {
        ReferencePanel(title:"Processes & Tasks",subtitle:"System processes, apps, and local workloads") {
            HStack(spacing:0) {
                ForEach(["All","System","Agents","User"],id:\.self){ item in
                    Button {scope=item} label:{Text(item).font(.system(size:9,weight:.medium)).frame(maxWidth:.infinity).padding(.vertical,6).background(scope==item ? LinearGradient(colors:[Color(hex:0x2575ff),Color(hex:0x2068af)],startPoint:.top,endPoint:.bottom) : LinearGradient(colors:[.clear,.clear],startPoint:.top,endPoint:.bottom),in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).strokeBorder(scope==item ? HUD.cyan.opacity(0.7):.clear,lineWidth:0.7))}.buttonStyle(.plain)
                }
            }.padding(3).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(HUD.cyan.opacity(0.2),lineWidth:0.7))
            HStack{Text("Name").frame(maxWidth:.infinity,alignment:.leading);Text("Type").frame(width:43);Text("CPU").frame(width:42);Text("Memory").frame(width:64);Text("State").frame(width:52)}.font(.system(size:9)).foregroundStyle(Color(hex:0xb6ccda))
            VStack(spacing:0) {
                ForEach(Array(rows.prefix(7))){ p in
                    Button {inspect(p)} label:{
                        HStack(spacing:5){
                            Image(systemName:p.agent != nil ? "terminal":"square.stack.3d.up").foregroundStyle(p.agent != nil ? HUD.purple:HUD.muted).frame(width:18)
                            Text(p.name).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                            Text(p.agent != nil ? "Agent":p.user ? "User":"System").font(.system(size:8)).padding(2).background(HUD.purple.opacity(0.12),in:RoundedRectangle(cornerRadius:3)).frame(width:43)
                            Text(percent(p.cpu)).frame(width:42)
                            Text(p.memory.map(bytes) ?? "—").frame(width:64)
                            Text(p.state).font(.system(size:8)).foregroundStyle(HUD.green).frame(width:52)
                        }.font(.system(size:10)).monospacedDigit().padding(.vertical,6)
                    }.buttonStyle(HUDRowStyle()).modifier(HoverLight())
                    Divider().opacity(0.22)
                }
            }
        }
    }
}

struct ReferenceEvents:View {
    @Environment(\.hudValueMotion) private var animate
    let alerts:[String]
    let events:[MonitorEvent]
    var replay:(Date)->Void = {_ in}
    let open:()->Void
    var body:some View {
        VStack(spacing:12) {
            ReferencePanel(title:"Alerts",subtitle:"\(alerts.count) active performance conditions") {
                if alerts.isEmpty {Label("No active warnings",systemImage:"checkmark.circle").font(.system(size:11)).foregroundStyle(HUD.green)}
                ForEach(Array(alerts.prefix(3)),id:\.self){message in
                    HStack(spacing:8){Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(message.contains("critical") ? HUD.red:HUD.amber);Text(message).font(.system(size:10)).lineLimit(1);Spacer(minLength:0)}.padding(6).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:8))
                }
            }.frame(height:132).animation(animate ? .easeOut(duration:0.25):nil,value:alerts)
            ReferencePanel(title:"Recent Events",subtitle:"Live system & monitoring events") {
                VStack(alignment:.leading,spacing:2) {
                if events.isEmpty {Text("No recorded events yet").font(.system(size:10)).foregroundStyle(HUD.muted)}
                ForEach(Array(events.prefix(4))){event in
                    Button {replay(event.date)} label: { HStack(spacing:8){Circle().fill(event.warning ? HUD.amber:HUD.green).frame(width:6,height:6).shadow(color:(event.warning ? HUD.amber:HUD.green).opacity(0.3),radius:4);Text(event.message).font(.system(size:10)).lineLimit(1);Spacer(minLength:2);Text(event.date.formatted(date:.omitted,time:.shortened)).font(.system(size:9)).foregroundStyle(HUD.muted)}.padding(.vertical,3).padding(.horizontal,6).background(.white.opacity(0.025),in:RoundedRectangle(cornerRadius:8)) }.buttonStyle(HUDRowStyle()).help("Replay measurements around this event")
                }
                Button("View all  →",action:open).buttonStyle(.plain).font(.system(size:9)).foregroundStyle(HUD.cyan)
                }
            }
        }
    }
}
