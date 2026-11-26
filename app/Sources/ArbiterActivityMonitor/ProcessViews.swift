import SwiftUI
import Charts
import ArbiterCore

struct WorkloadsPanel: View {
    let workloads: [Workload]
    let inspect: (ProcessSample) -> Void
    var limit = 5
    var sort: Binding<ConsumptionSort>?
    var selection: Binding<Set<String>>?
    var quit: (([ProcessSample], QuitMode) -> Void)?
    private var shown: [Workload] { Array(workloads.prefix(limit)) }
    private var selected: [Workload] { workloads.filter { selection?.wrappedValue.contains($0.id) == true } }
    var body: some View {
        Panel(title: "Local workloads", subtitle: "OBSERVED PROCESS TREES · CPU IS % OF ONE CORE · MEMORY IS SUMMED RESIDENT BYTES") {
            if let sort, !workloads.isEmpty {
                HStack(spacing: 10) {
                    if let selection {
                        SelectBox(selected: !shown.isEmpty && shown.allSatisfy { selection.wrappedValue.contains($0.id) }, partial: !selection.wrappedValue.isEmpty) {
                            selection.wrappedValue = selection.wrappedValue.isEmpty ? Set(shown.map(\.id)) : []
                        }.help("Select all or none")
                    }
                    Text("\(workloads.count) workloads").foregroundStyle(HUD.muted)
                    Spacer()
                    Text("Sort").foregroundStyle(HUD.muted)
                    Picker("Sort", selection: sort) { ForEach(ConsumptionSort.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
                }.font(.system(size: 10))
            }
            if let selection, let quit, !selected.isEmpty {
                QuitBar(count: selected.count, clear: { selection.wrappedValue = [] }) { mode in quit(selected.flatMap(\.members), mode) }
                Text("Quitting a workload ends every process in its tree (\(selected.map(\.members.count).reduce(0, +)) processes).").font(.system(size: 9)).foregroundStyle(HUD.muted)
            }
            if workloads.isEmpty {
                ContentUnavailableView("No workloads detected", systemImage: "cpu", description: Text("Recognized local tools appear here. Track any process from its inspector."))
            } else {
                VStack(spacing: 5) {
                ForEach(shown) { workload in
                    HStack(spacing: 10) {
                    if let selection {
                        SelectBox(selected: selection.wrappedValue.contains(workload.id)) {
                            if selection.wrappedValue.contains(workload.id) { selection.wrappedValue.remove(workload.id) } else { selection.wrappedValue.insert(workload.id) }
                        }
                    }
                    Button { inspect(workload.root) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: workload.root.agent != nil ? "terminal" : "square.stack.3d.up").font(.system(size: 18)).foregroundStyle(HUD.purple)
                                .frame(width: 36, height: 40).background(HUD.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(workload.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text("\(workload.members.count) processes · \(workload.explicit ? "Tracked" : "Detected")").font(.system(size: 10)).foregroundStyle(HUD.muted)
                            }
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 5) {
                                Text(percent(workload.cpu)).foregroundStyle(HUD.cyan).font(.system(size: 15, weight: .medium, design: .monospaced))
                                Text(bytes(workload.memory)).font(.system(size: 10)).foregroundStyle(HUD.muted)
                            }
                        }.padding(.vertical, 5)
                    }.buttonStyle(.plain).help("Inspect \(workload.title). Shared memory may be counted more than once in aggregate RSS.")
                        .modifier(QuitMenu(processes: workload.members, quit: quit))
                    }
                    if workload.id != shown.last?.id { Divider().overlay(HUD.cyan.opacity(0.08)) }
                }
                }
                Text("Local impact, not cloud model performance.").font(.system(size: 10)).foregroundStyle(HUD.muted)
            }
        }
    }
}

enum ProcessSort: String, CaseIterable { case cpu = "CPU", memory = "Memory", read = "Disk read", write = "Disk write", name = "Name" }

struct ProcessesView: View {
    @Bindable var store: MonitorStore
    @State private var query = ""
    @AppStorage("processSort") private var sort = ProcessSort.cpu
    @State private var scope = "All"
    @State private var selection = Set<String>()
    @Environment(\.hudLayout) private var layout
    var compact = false
    private var selected: [ProcessSample] { (store.latest?.processes ?? []).filter { selection.contains($0.id) } }
    private var rows: [ProcessSample] {
        let filtered = (store.latest?.processes ?? []).filter {
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || String($0.pid).contains(query)) &&
            (scope == "All" || scope == "User" && $0.user || scope == "System" && !$0.user || scope == "Pinned" && store.pinned.contains($0.id))
        }
        return filtered.sorted {
            switch sort {
            case .cpu: ($0.cpu ?? -1) == ($1.cpu ?? -1) ? $0.pid < $1.pid : ($0.cpu ?? -1) > ($1.cpu ?? -1)
            case .memory: ($0.memory ?? 0) == ($1.memory ?? 0) ? $0.pid < $1.pid : ($0.memory ?? 0) > ($1.memory ?? 0)
            case .read: ($0.read ?? -1) == ($1.read ?? -1) ? $0.pid < $1.pid : ($0.read ?? -1) > ($1.read ?? -1)
            case .write: ($0.write ?? -1) == ($1.write ?? -1) ? $0.pid < $1.pid : ($0.write ?? -1) > ($1.write ?? -1)
            case .name: $0.name == $1.name ? $0.pid < $1.pid : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }
    var body: some View {
        Panel(title: compact ? "Top resource consumers" : "Process explorer", subtitle: "CPU: 100% = ONE CORE · MEMORY: RESIDENT BYTES · DENIED COUNTERS: —") {
            if !compact {
                let filters = Group {
                    Picker("Scope", selection: $scope) { ForEach(["All", "User", "System", "Pinned"], id: \.self) { Text($0) } }.frame(maxWidth: 160)
                    Picker("Sort", selection: $sort) { ForEach(ProcessSort.allCases, id: \.self) { Text($0.rawValue) } }.frame(maxWidth: 160)
                }
                if layout == .wide {
                    HStack { TextField("Search name or PID", text: $query).textFieldStyle(.roundedBorder); filters }
                } else {
                    VStack(alignment: .leading, spacing: 8) { TextField("Search name or PID", text: $query).textFieldStyle(.roundedBorder); HStack { filters } }
                }
            }
            HStack {
                if !compact {
                    let visible = rows.prefix(4096).map(\.id)
                    SelectBox(selected: !visible.isEmpty && visible.allSatisfy(selection.contains), partial: !selection.isEmpty) {
                        selection = selection.isEmpty ? Set(visible) : []
                    }.help("Select all visible processes, or clear the selection")
                }
                SortHeader(title: "PROCESS", active: sort == .name) { sort = .name }.frame(maxWidth: .infinity, alignment: .leading)
                SortHeader(title: "CPU", active: sort == .cpu) { sort = .cpu }.frame(width: 65, alignment: .trailing)
                SortHeader(title: "MEMORY", active: sort == .memory) { sort = .memory }.frame(width: 85, alignment: .trailing)
                if !compact && layout == .wide { Text("THREADS").frame(width: 60) }
                if !compact && layout >= .stacked { Text("READ / WRITE").frame(width: 145) }
                if !compact && layout == .wide { Text("STATE").frame(width: 75) }
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(HUD.muted)
            if !compact && !selected.isEmpty {
                QuitBar(count: selected.count, clear: { selection = [] }) { mode in store.requestQuit(selected, mode: mode) }
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.prefix(compact ? 7 : 4096))) { p in
                    HStack(spacing: 6) {
                    if !compact {
                        SelectBox(selected: selection.contains(p.id)) { if selection.contains(p.id) { selection.remove(p.id) } else { selection.insert(p.id) } }
                            .padding(.leading, 5)
                    }
                    Button { store.inspect(p) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: store.pinned.contains(p.id) ? "pin.fill" : "terminal").foregroundStyle(p.category > 0 ? HUD.purple : HUD.muted)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.name).lineLimit(1)
                                if !compact { Text("PID \(p.pid) · parent \(p.parent)").font(.system(size: 9)).foregroundStyle(HUD.muted) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text(percent(p.cpu)).monospacedDigit().foregroundStyle(HUD.cyan).frame(width: 65, alignment: .trailing)
                            Text(p.memory.map(bytes) ?? "—").monospacedDigit().frame(width: 85, alignment: .trailing)
                            if !compact && layout == .wide { Text(p.threads.map(String.init) ?? "—").frame(width: 60) }
                            if !compact && layout >= .stacked { Text("\(rate(p.read)) / \(rate(p.write))").font(.system(size: 10)).frame(width: 145) }
                            if !compact && layout == .wide { Text(p.state).foregroundStyle(HUD.muted).frame(width: 75) }
                        }.font(.system(size: 11)).padding(.vertical, 9).padding(.horizontal, 5)
                            .background(store.selectedProcessID == p.id ? HUD.cyan.opacity(0.1) : .clear)
                    }.buttonStyle(.plain).modifier(QuitMenu(processes: [p], quit: store.requestQuit))
                    }.background(selection.contains(p.id) ? HUD.cyan.opacity(0.06) : .clear)
                    Divider().opacity(0.3)
                }
            }
            if rows.isEmpty { ContentUnavailableView("No matching processes", systemImage: "line.3.horizontal.decrease", description: Text("Try a different search or filter.")) }
            if !compact { Text("\(rows.count) visible processes · paths stay on this Mac · tick processes, or right-click one, to Quit or Force Quit · other users' and macOS processes are refused").font(.system(size: 10)).foregroundStyle(HUD.muted) }
        }
    }
}

struct ProcessInspector: View {
    @Bindable var store: MonitorStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Process inspector").font(.title2)
                Spacer()
                Button("Close", systemImage: "xmark") { store.selectedProcessID = nil }.labelStyle(.iconOnly)
            }
            if let p = store.selectedProcess {
                Text(p.name).font(.title3).foregroundStyle(HUD.cyan)
                LabeledContent("Identity", value: "PID \(p.pid) · parent \(p.parent)")
                LabeledContent("State", value: p.state)
                LabeledContent("Started", value: p.startDate.formatted(date: .abbreviated, time: .standard))
                LabeledContent("Lifetime / CPU time", value: "\(Int(Date().timeIntervalSince(p.startDate)))s / \(p.cpuTimeSeconds.map { String(format: "%.2f s", $0) } ?? "—")")
                LabeledContent("CPU / memory", value: "\(percent(p.cpu)) / \(p.memory.map(bytes) ?? "—")")
                LabeledContent("Disk read / write", value: "\(rate(p.read)) / \(rate(p.write))")
                LabeledContent("Network / GPU", value: "Unavailable per process")
                Text(p.path.isEmpty ? "Executable path unavailable" : p.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).foregroundStyle(HUD.muted)
                HStack {
                    Button(store.pinned.contains(p.id) ? "Unpin" : "Pin process", systemImage: "pin") {
                        if store.pinned.contains(p.id) { store.pinned.remove(p.id) } else { store.pinned.insert(p.id) }
                    }
                    Button(store.tracked.contains(p.id) ? "Stop tracking" : "Track workload", systemImage: "point.3.connected.trianglepath.dotted") {
                        if store.tracked.contains(p.id) { store.tracked.remove(p.id) } else { store.tracked.insert(p.id) }
                    }
                    Spacer()
                    let blocker = ProcessControl.blocker(for: p)
                    ForEach(QuitMode.allCases, id: \.self) { mode in
                        Button(mode.rawValue, systemImage: mode == .quit ? "xmark.circle" : "xmark.octagon") {
                            store.selectedProcessID = nil
                            store.requestQuit([p], mode: mode)
                        }.disabled(blocker != nil).help(blocker ?? (mode == .quit ? "Ask this process to close" : "End this process immediately"))
                    }
                }
                Chart(store.processHistory) { point in
                    if let cpu = point.value.cpu { LineMark(x: .value("Time", point.id), y: .value("CPU % of one core", cpu)).foregroundStyle(HUD.cyan) }
                }.frame(height: 130).chartYAxisLabel("CPU % · one core")
                Text("History starts when inspected. Tracking is session-only and bound to PID + start time.").font(.caption).foregroundStyle(HUD.muted)
                Text("Observed children").font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach((store.latest?.processes ?? []).filter { $0.parent == p.pid && $0.started >= p.started }) { child in
                            Button { store.inspect(child) } label: { Label("\(child.name) · \(child.pid) · \(percent(child.cpu))", systemImage: "arrow.turn.down.right") }.buttonStyle(.plain)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Process exited or unavailable", systemImage: "stop.circle", description: Text("A reused PID will not be substituted for the inspected process."))
            }
        }.padding(24).frame(width: 540, height: 650).background(HUD.background).foregroundStyle(HUD.text).preferredColorScheme(.dark)
    }
}

struct WorkloadsView: View {
    @Bindable var store: MonitorStore
    @AppStorage("workloadSort") private var sort = ConsumptionSort.cpu
    @State private var selection = Set<String>()
    var body: some View {
        let workloads = store.workloads.sorted(by: sort)
        VStack(spacing: 16) {
            WorkloadsPanel(workloads: workloads, inspect: store.inspect, limit: 64, sort: $sort, selection: $selection, quit: store.requestQuit)
            ForEach(workloads) { workload in
                Panel(title: "\(workload.title) · PID \(workload.root.pid)", subtitle: "\(percent(workload.cpu)) CPU · \(bytes(workload.memory)) RSS · READ \(rate(workload.read)) · WRITE \(rate(workload.write))") {
                    Text("Observed dependency tree").font(.headline)
                    ForEach(tree(workload)) { node in
                        let member = node.process
                        Button { store.inspect(member) } label: {
                            HStack {
                                Image(systemName: member.id == workload.root.id ? "circle.hexagongrid" : "arrow.turn.down.right").foregroundStyle(HUD.cyan)
                                Text(member.name)
                                Text("\(member.pid) ← \(member.parent)").font(.caption.monospaced()).foregroundStyle(HUD.muted)
                                Spacer()
                                Text(percent(member.cpu)).monospacedDigit()
                                Text(member.memory.map(bytes) ?? "—").frame(width: 90, alignment: .trailing)
                            }.padding(10).background(HUD.cyan.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUD.cyan.opacity(0.15)))
                                .padding(.leading, CGFloat(min(node.depth, 8)) * 18)
                        }.buttonStyle(.plain).modifier(QuitMenu(processes: [member], quit: store.requestQuit))
                    }
                    Text("Edges are current parent relationships. Reparented or unobservable processes may be absent. Model identity is not available from OS process counters.").font(.caption).foregroundStyle(HUD.muted)
                }
            }
        }
    }
    private struct Node: Identifiable {
        let process: ProcessSample
        let depth: Int
        var id: String { process.id }
    }
    private func tree(_ workload: Workload) -> [Node] {
        let children = Dictionary(grouping: workload.members, by: \.parent)
        var pending = [Node(process: workload.root, depth: 0)]
        var seen = Set<String>()
        var result: [Node] = []
        while let node = pending.popLast(), result.count < 80 {
            guard seen.insert(node.id).inserted else { continue }
            result.append(node)
            pending.append(contentsOf: (children[node.process.pid] ?? []).sorted { $0.pid > $1.pid }.map { Node(process: $0, depth: node.depth + 1) })
        }
        return result
    }
}
