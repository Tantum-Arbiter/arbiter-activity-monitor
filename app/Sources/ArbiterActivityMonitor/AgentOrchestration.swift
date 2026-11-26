import SwiftUI
import ArbiterCore

struct AgentOrchestration: View {
    @Bindable var store: MonitorStore
    /// Slim windows: draw the observed harness as a vertical list instead of the four-lane graph.
    var list = false
    @Environment(\.hudSnapshot) private var snapshot
    private var selected: AgentSession? { store.sessions.first { $0.id == store.selectedSessionID } ?? store.sessions.first { $0.isRunning || $0.status == "Waiting" } ?? store.sessions.first { $0.parent == nil } ?? store.sessions.first }
    var body: some View {
        ReferencePanel(title:"Agent Orchestration",subtitle:"Claude / Codex / MLX · Observed harness · hover for detail") {
            HStack {
                Text(selected.map {statusLabel($0.status)} ?? "No sessions detected").foregroundStyle(selected?.isRunning == true ? HUD.green:HUD.muted)
                Spacer()
                if let selected,!snapshot {Button("Inspect session",systemImage:"scope") {store.inspectedSessionID=selected.id}.buttonStyle(.plain).foregroundStyle(HUD.cyan).help("Open the session inspector")}
                if snapshot {Text(selected.map {"\($0.app.rawValue) · \($0.id.prefix(8)) ▾"} ?? "Select session").font(.system(size:9)).padding(5).background(HUD.panel,in:Capsule())}
                else { Menu {
                    Button("Follow active session") {store.selectedSessionID=nil}
                    Divider()
                    ForEach(store.sessions) { session in
                        Button("\(session.app.rawValue) · \(session.model ?? "Unknown model") · \(session.id.prefix(8))") {store.selectedSessionID=session.id}
                    }
                } label: {
                    Text(selected.map {"\($0.app.rawValue) · \($0.id.prefix(8))"} ?? "Select session").lineLimit(1)
                }.menuStyle(.borderlessButton).fixedSize() }
            }.font(.system(size:10))
            if let selected, list {
                HarnessList(harness:HarnessBuilder.build(session:selected,sessions:store.sessions,processes:store.latest?.processes ?? [])) {store.inspectedSessionID=selected.id}
            } else if let selected {
                HarnessGraph(harness:HarnessBuilder.build(session:selected,sessions:store.sessions,processes:store.latest?.processes ?? []),previewHover:store.previewHover.flatMap(HarnessNode.Kind.init(rawValue:))) {store.inspectedSessionID=selected.id}
                    .frame(height:156).zIndex(1)
            } else {
                ContentUnavailableView("No harness detected",systemImage:"point.3.connected.trianglepath.dotted",description:Text("Open Claude Code or Codex, or load an MLX model.")).frame(height:156)
            }
            Divider().overlay(HUD.cyan.opacity(0.3))
            VStack(alignment:.leading,spacing:6) {
                HStack {Text("Execution Timeline").font(.system(size:14,weight:.semibold));Spacer();Button("Connect events") {store.destination = .settings}.buttonStyle(.plain).font(.system(size:9)).foregroundStyle(HUD.cyan)}
                if let session=selected,!session.events.isEmpty {
                    ExecutionTimeline(events:session.events).frame(height:16)
                    HStack(spacing:12) {Label("Model",systemImage:"circle.fill").foregroundStyle(HUD.cyan);Label("Tool",systemImage:"circle.fill").foregroundStyle(HUD.blue);Label("Subagent",systemImage:"circle.fill").foregroundStyle(HUD.magenta);Label("Turn end",systemImage:"circle.fill").foregroundStyle(HUD.green)}.font(.system(size:8))
                } else {
                    Capsule().fill(LinearGradient(colors:[HUD.cyan.opacity(0.15),HUD.blue.opacity(0.15),HUD.magenta.opacity(0.15)],startPoint:.leading,endPoint:.trailing)).frame(height:15)
                    Text("Session metadata connected · lifecycle hooks needed for execution timing").font(.system(size:9)).foregroundStyle(HUD.muted).lineLimit(2)
                }
            }
        }
    }
}

struct SessionAgentsPanel: View {
    @Bindable var store: MonitorStore
    /// Stacked layouts: take the list's natural height instead of filling a fixed slot.
    var fit = false
    @State private var showInactive=false
    @State private var showUnconfirmed=false
    @Environment(\.hudSnapshot) private var snapshot
    @Environment(\.hudReducedMotion) private var reducedMotion
    private var active:[AgentSession] {store.sessions.filter{$0.isRunning || $0.status == "Waiting" || $0.status == "Error"}}
    /// Live MLX runtime processes: present and measured, but MLX reports no task state, so they are not counted as active.
    private var runtimes:[AgentSession] {store.sessions.filter{$0.status == MLXRuntimes.status}}
    private var inactive:[AgentSession] {store.sessions.filter{["Idle","Ended","Stale"].contains($0.status)}}
    private var unconfirmed:[AgentSession] {store.sessions.filter{!["Idle","Ended","Stale","Waiting","Error",MLXRuntimes.status].contains($0.status) && !$0.isRunning}}
    var body:some View {
        ReferencePanel(title:"AI Agents",subtitle:"Claude / Codex / MLX · Live session activity",badge:"\(active.count) active · \(store.sessions.count) seen") {
            HStack {
                Text("APPLICATION / MODEL").frame(maxWidth:.infinity,alignment:.leading)
                Text("App CPU").frame(width:48);Text("App RAM").frame(width:57);Text("Tokens").frame(width:52)
            }.font(.system(size:9)).foregroundStyle(HUD.muted).padding(.top,3)
            if fit {sessionList}
            else if snapshot {sessionList;Spacer(minLength:0)}
            else {ScrollView {sessionList}.scrollIndicators(.automatic)}
            Text("CPU/RAM are shared app totals. Tokens are cumulative per session.").font(.system(size:9)).foregroundStyle(HUD.muted).lineLimit(2)
        }
    }
    private var sessionList:some View {
        VStack(spacing:7) {
            if active.isEmpty && runtimes.isEmpty {
                VStack(spacing:8) {
                    Image(systemName:"moon.zzz").font(.system(size:23,weight:.ultraLight)).foregroundStyle(HUD.cyan)
                    Text("No active sessions reported").font(.system(size:12,weight:.medium))
                    Text(unconfirmed.isEmpty ? "Agents will expand when work starts.":"Some sessions have no live activity signal yet.")
                        .font(.system(size:10)).foregroundStyle(HUD.muted).multilineTextAlignment(.center)
                }.frame(maxWidth:.infinity).padding(.vertical,20)
            }
            ForEach(active) {session in sessionRow(session)}
            ForEach(runtimes) {session in sessionRow(session)}
            if !inactive.isEmpty {collapsedGroup("Inactive",sessions:inactive,expanded:$showInactive)}
            if !unconfirmed.isEmpty {collapsedGroup("Activity unconfirmed",sessions:unconfirmed,expanded:$showUnconfirmed)}
            if store.sessions.isEmpty {
                Text("Open Claude Code or Codex, or load an MLX model. Connect lifecycle events in Settings.").font(.system(size:10)).foregroundStyle(HUD.muted)
            }
        }.padding(.top,3)
    }
    private func collapsedGroup(_ title:String,sessions:[AgentSession],expanded:Binding<Bool>)->some View {
        VStack(spacing:4) {
            Button {
                withAnimation(reducedMotion ? nil:.easeInOut(duration:0.2)) {expanded.wrappedValue.toggle()}
            } label: {
                HStack(spacing:7) {
                    Image(systemName:expanded.wrappedValue ? "chevron.down":"chevron.right").font(.system(size:9,weight:.semibold))
                    Text(title);Text("\(sessions.count)").foregroundStyle(HUD.cyan)
                    Spacer()
                    Text("\(sessions.filter{$0.app == .claude}.count) Claude · \(sessions.filter{$0.app == .codex}.count) Codex").font(.system(size:9))
                }.font(.system(size:10)).foregroundStyle(HUD.muted).padding(9)
                    .background(HUD.cyan.opacity(0.035),in:RoundedRectangle(cornerRadius:7))
            }.buttonStyle(.plain).accessibilityLabel("\(expanded.wrappedValue ? "Collapse":"Expand") \(title), \(sessions.count) sessions")
            if expanded.wrappedValue {ForEach(sessions) {session in sessionRow(session)}}
        }
    }
    private func sessionRow(_ session:AgentSession)->some View {
        let app=store.latest?.apps.first{$0.app==session.app}
        let color=session.app == .codex ? HUD.blue:session.app == .mlx ? HUD.magenta:HUD.purple
        return Button {store.selectedSessionID=session.id} label:{
            HStack(spacing:7) {
                Image(systemName:session.app == .codex ? "chevron.left.forwardslash.chevron.right":session.app == .mlx ? "memorychip":"sparkles")
                    .font(.system(size:19)).foregroundStyle(color).frame(width:32,height:36)
                    .background(color.opacity(0.17),in:RoundedRectangle(cornerRadius:7))
                VStack(alignment:.leading,spacing:3) {
                    Text(session.model ?? "Model not reported").font(.system(size:11,weight:.semibold)).lineLimit(1)
                    Text("\(session.app.rawValue) · \(session.id.prefix(8))").font(.system(size:9)).foregroundStyle(HUD.muted)
                    Text(session.status == "Observed" ? "Activity unconfirmed":session.status == MLXRuntimes.status ? "Runtime loaded · activity not reported":session.status)
                        .font(.system(size:9)).foregroundStyle(session.isRunning ? HUD.green:session.status == "Waiting" ? HUD.amber:HUD.muted)
                }.frame(maxWidth:.infinity,alignment:.leading)
                Text(percent(app?.cpuPercent)).frame(width:48)
                Text(app.map{bytes($0.memoryBytes)} ?? "—").frame(width:57)
                Text(session.tokens.map(compact) ?? "—").frame(width:52)
            }.font(.system(size:10,weight:.medium)).monospacedDigit().padding(.vertical,5)
                .overlay(alignment:.bottom){Rectangle().fill(color.opacity(0.16)).frame(height:0.5)}
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .help("\(session.app.rawValue) · \(statusLabel(session.status)) · \(session.source). Click to show its harness; double-click to inspect.")
            .simultaneousGesture(TapGesture(count:2).onEnded {store.inspectedSessionID=session.id})
    }
    private func compact(_ value:Int)->String {value>=1_000_000 ? String(format:"%.1f M",Double(value)/1_000_000):value>=1000 ? String(format:"%.1f K",Double(value)/1000):String(value)}
}

struct SessionThroughput:View {
    let sessions:[AgentSession]
    private var events:[SessionEvent] {sessions.flatMap(\.events)}
    private var now:Date {Date()}
    private var completions:[SessionEvent] {events.filter{$0.event=="Stop"}}
    var body:some View {
        ReferencePanel(title:"Agent Throughput",subtitle:"Recorded turn completions per minute") {
            VStack(alignment:.leading,spacing:0) {
                Text(events.isEmpty ? "—":String(completions.filter{now.timeIntervalSince($0.date)<60}.count)).font(.system(size:27,weight:.semibold)).monospacedDigit()
                Text("turns/min").font(.system(size:12))
            }
            if events.isEmpty {Text("Waiting for lifecycle events").font(.system(size:10)).foregroundStyle(HUD.muted);Spacer(minLength:0)}
            else {LuminousSparkline(values:(0..<20).map {bucket in Double(completions.filter {let age=now.timeIntervalSince($0.date);return age>=Double(19-bucket)*60 && age<Double(20-bucket)*60}.count)},color:HUD.purple,bars:true).frame(maxHeight:.infinity)}
        }
    }
}
