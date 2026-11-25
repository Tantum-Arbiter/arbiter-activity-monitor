import SwiftUI
import ArbiterCore

struct DashboardView: View {
    @Bindable var store: MonitorStore
    var snapshotMode = false
    @Namespace private var navigationGlow
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var body: some View {
        GeometryReader { geometry in
            let narrow = geometry.size.width < 980
            VStack(spacing: 0) {
                header(compact: geometry.size.width < 1440)
                Divider().overlay(HUD.cyan.opacity(0.15))
                HStack(spacing: 0) {
                    sidebar(compact: narrow)
                    Divider().overlay(HUD.cyan.opacity(0.1))
                    if store.destination == .overview {
                        if snapshotMode {
                            ReferenceOverview(store:store,width:geometry.size.width-(narrow ? 69:151)-24,height:geometry.size.height-82).padding(.horizontal,12).padding(.vertical,14).frame(maxHeight:.infinity,alignment:.top)
                        } else {
                            ScrollView {
                                ReferenceOverview(store:store,width:geometry.size.width-(narrow ? 69:151)-24,height:geometry.size.height-82).padding(.horizontal,12).padding(.vertical,14)
                            }
                        }
                    } else if snapshotMode {
                        page(width:geometry.size.width-(narrow ? 69:151)-40).frame(maxHeight:.infinity,alignment:.top)
                    } else {
                        ScrollView { page(width:geometry.size.width-(narrow ? 69:151)-40) }
                    }
                }
            }
        }
        .ignoresSafeArea(.container,edges:.top)
        .background { HUDGrid().overlay(healthColor.opacity(contrast == .increased ? 0:0.025)).background(HUD.background) }.foregroundStyle(HUD.text).preferredColorScheme(.dark)
        .environment(\.hudIntensity, store.motionIntensity)
        .environment(\.hudSnapshot, snapshotMode)
        .environment(\.hudValueMotion, !snapshotMode && store.motionIntensity != .minimal && store.active && !store.paused && !systemReduceMotion && !store.reducedMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled && ProcessInfo.processInfo.thermalState.rawValue < 2)
        .environment(\.hudReducedMotion, systemReduceMotion || store.reducedMotion)
        .environment(\.hudAmbientMotion, !snapshotMode && store.motionIntensity == .cinematic && store.ambientMotion && store.active && !store.paused && !systemReduceMotion && !store.reducedMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled && ProcessInfo.processInfo.thermalState.rawValue < 2)
        .tint(HUD.cyan).frame(minWidth: 760, minHeight: 600)
        .task { if !snapshotMode { store.start() } }
        .onChange(of: scenePhase) { _, phase in store.active = phase == .active }
        .sheet(isPresented: Binding(get: { store.selectedProcessID != nil }, set: { if !$0 { store.selectedProcessID = nil } })) { ProcessInspector(store: store) }
        .sheet(isPresented: Binding(get: { store.inspectedSessionID != nil }, set: { if !$0 { store.inspectedSessionID = nil } })) { SessionInspector(store: store) }
        .modifier(QuitConfirmation(store: store))
        .overlay(alignment: .top) {
            if let notice = store.notice {
                Label(notice, systemImage: "info.circle").font(.system(size: 11, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(HUD.panel, in: Capsule()).overlay(Capsule().strokeBorder(HUD.cyan.opacity(0.4))).padding(.top, 62)
                    .transition(.opacity).onTapGesture { store.notice = nil }
            }
        }
    }

    private func page(width: CGFloat) -> some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text(store.destination.rawValue).font(.system(size:22,weight:.medium))
                Spacer()
                Button {store.paused.toggle()} label:{Label(store.paused ? "Resume":"Pause",systemImage:store.paused ? "play":"pause")}
            }
            content(width:width)
            Text(store.latest.map {"Last sample \($0.id.formatted(date:.omitted,time:.standard)) · \(Int(store.actualInterval))s collection"} ?? "Waiting for first sample").font(.caption).foregroundStyle(HUD.muted)
        }.padding(20)
    }

    private var healthColor: Color {
        switch store.health { case .healthy: HUD.green; case .pressure: HUD.amber; case .critical: HUD.red; case .unknown: HUD.muted }
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing:12) {
            Image(systemName:"waveform.path").font(.system(size:27,weight:.medium)).foregroundStyle(HUD.cyan).shadow(color:HUD.cyan.opacity(0.4),radius:5)
            Text("ARBITER Activity Monitor").font(.system(size:21,weight:.semibold)).fixedSize()
            if !compact { Rectangle().fill(HUD.muted.opacity(0.4)).frame(width:1,height:27);Text("System + Local AI Operations").font(.system(size:12)).foregroundStyle(Color(hex:0xb6cadd)) }
            Spacer(minLength:2)
            StatusPill(text:store.paused ? "Paused":(compact ? "":"System State: ")+store.health.rawValue,color:healthColor)
            HStack(spacing:3) {
                headerMetric(.cpu,percent(store.latest?.cpu),color:HUD.cyan)
                if !compact {headerMetric(.gpu,percent(store.latest?.gpu),color:HUD.purple)}
                headerMetric(.memory,store.latest.map{compact ? bytes($0.memoryUsed):"\(String(format:"%.1f",Double($0.memoryUsed)/1_073_741_824)) / \(bytes($0.memoryTotal))"} ?? "—",color:HUD.purple)
                if !compact {headerMetric(.battery,percent(store.latest?.battery),color:HUD.cyan);headerMetric(.thermals,store.latest?.thermal ?? "—",color:HUD.cyan)}
                if !compact {headerMetric(.workloads,"\(OverviewWorkload.groups(store.workloads).count) apps",color:HUD.purple)}
            }
            Button {store.paused.toggle()} label:{Image(systemName:store.paused ? "play.fill":"pause.fill").font(.system(size:10)).foregroundStyle(HUD.muted)}.buttonStyle(.plain).help(store.paused ? "Resume monitoring":"Pause monitoring")
        }.padding(.leading,compact ? 84:112).padding(.trailing,12).frame(height:54)
        .background(LinearGradient(colors:[Color(hex:0x08121d),Color(hex:0x030a11)],startPoint:.top,endPoint:.bottom))
        .overlay(alignment:.leading) {
            if snapshotMode {
                HStack(spacing:8){ForEach([Color(hex:0xff5f57),Color(hex:0xfebc2e),Color(hex:0x28c840)],id:\.self){color in Circle().fill(color).frame(width:12,height:12)}}.padding(.leading,21).accessibilityHidden(true)
            }
        }
    }

    private func headerMetric(_ destination:Destination,_ value:String,color:Color)->some View {
        Button {store.destination=destination} label:{
            HStack(spacing:8) {
                Image(systemName:destination.symbol).font(.system(size:22,weight:.light)).foregroundStyle(color).shadow(color:color.opacity(0.25),radius:4)
                VStack(alignment:.leading,spacing:3){Text(destination.rawValue).font(.system(size:9)).foregroundStyle(Color(hex:0xb6cadd));Text(value).font(.system(size:13,weight:.semibold)).monospacedDigit().lineLimit(1)}
            }.padding(.horizontal,10).frame(height:48).background(Color(hex:0x07131d),in:RoundedRectangle(cornerRadius:11)).overlay(RoundedRectangle(cornerRadius:11).strokeBorder(HUD.cyan.opacity(0.13),lineWidth:0.7))
        }.buttonStyle(.plain).help("Open \(destination.rawValue) diagnostics")
    }

    private func sidebar(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if snapshotMode { sidebarItems(compact:compact) }
            else {ScrollView {sidebarItems(compact:compact)}}
            Spacer(minLength: 8)
            if !compact {
                VStack(alignment: .leading, spacing: 8) {
                    StatusPill(text: store.paused ? "Paused" : "Live monitoring", color: store.paused ? HUD.amber : HUD.green)
                    Text("App uptime \(Int(Date().timeIntervalSince(store.launched) / 60))m").font(.system(size: 10)).foregroundStyle(HUD.muted)
                    Text("System uptime \(Int(ProcessInfo.processInfo.systemUptime / 3600))h").font(.system(size: 10)).foregroundStyle(HUD.muted)
                }.padding(6)
            }
        }.padding(.horizontal,7).padding(.top,20).padding(.bottom,12).frame(width:compact ? 68:150)
        .background {
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(colors:[Color(hex:0x0b1420),Color(hex:0x030c15)],startPoint:.top,endPoint:.bottom)
                    SidebarWave()
                        .environment(\.hudAmbientMotion, !snapshotMode && store.motionIntensity != .minimal && store.ambientMotion && store.active && !store.paused && !systemReduceMotion && !store.reducedMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled && ProcessInfo.processInfo.thermalState.rawValue < 2)
                        .frame(height:210).position(x:geometry.size.width/2,y:geometry.size.height*0.75)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius:15))
        .overlay(NeonPanelEdge(emphasized:false))
    }

    private func sidebarItems(compact:Bool)->some View {
        VStack(spacing:6) {
            ForEach(Destination.allCases) { destination in
                Button { withAnimation(systemReduceMotion || store.reducedMotion ? nil:.spring(response:0.23,dampingFraction:0.9)) {store.destination = destination} } label: {
                    HStack(spacing: 12) {
                        Image(systemName: destination.symbol).font(.system(size: 16)).frame(width: 22)
                        if !compact { Text(destination.rawValue).font(.system(size: 12)) }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 12).frame(height: 37)
                        .foregroundStyle(store.destination == destination ? HUD.text : HUD.muted)
                        .background { if store.destination == destination {RoundedRectangle(cornerRadius:9).fill(LinearGradient(colors:[HUD.cyan.opacity(0.3),HUD.purple.opacity(0.4)],startPoint:.leading,endPoint:.trailing)).matchedGeometryEffect(id:"navigation",in:navigationGlow)} }
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(store.destination == destination ? HUD.cyan.opacity(0.85) : .clear))
                        .shadow(color:store.destination == destination ? HUD.cyan.opacity(0.23) : .clear,radius:6)
                }.buttonStyle(.plain).help(destination.rawValue).accessibilityLabel(destination.rawValue).accessibilityAddTraits(store.destination == destination ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func content(width: CGFloat) -> some View {
        switch store.destination {
        case .overview: ReferenceOverview(store:store,width:width)
        case .processes: ProcessesView(store: store)
        case .workloads: WorkloadsView(store: store)
        case .models: ModelsView(store: store)
        case .history:
            if let date=store.replayDate {
                HStack {Label("Event replay · \(date.formatted()) · ±2 minutes",systemImage:"clock.arrow.circlepath");Spacer();Button("Return to live") {store.replayDate=nil;store.range=900}}
                if store.chartHistory.isEmpty {Text("No retained measurements around this event.").foregroundStyle(HUD.muted)}
            }
            if store.replayDate == nil { Picker("Time range", selection: $store.range) {
                Text("1 min").tag(60.0); Text("15 min").tag(900.0); Text("1 hour").tag(3600.0); Text("24 hours").tag(86400.0); Text("7 days").tag(604800.0)
            }.pickerStyle(.segmented).onChange(of: store.range) { Task { await store.loadHistory() } } }
            Text(store.replayDate != nil || store.range > 900 ? "Stored observations · one measured sample per bucket · up to 450 points. History accumulates while this app runs." : "Live session history · up to 450 displayed points.").font(.caption).foregroundStyle(HUD.muted)
            HistoryPanel(history: store.chartHistory,spotlight:store.spotlight,replayDate:store.replayDate)
            HeatmapPanel(history: store.chartHistory)
            ThroughputPanel(history: store.chartHistory)
            ThroughputPanel(history: store.chartHistory, network: true)
        case .alerts: EventsPanel(store: store)
        case .settings: MonitorSettings(store: store)
        default: ResourceDetailView(destination: store.destination, sample: store.latest, history: store.chartHistory)
        }
    }
}
