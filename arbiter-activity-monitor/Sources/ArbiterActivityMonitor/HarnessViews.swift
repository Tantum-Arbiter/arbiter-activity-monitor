import SwiftUI
import ArbiterCore

func elapsed(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval))
    if seconds >= 86400 { return "\(seconds / 86400)d \(seconds % 86400 / 3600)h" }
    if seconds >= 3600 { return "\(seconds / 3600)h \(seconds % 3600 / 60)m" }
    if seconds >= 60 { return "\(seconds / 60)m \(seconds % 60)s" }
    return "\(seconds)s"
}

func statusLabel(_ status: String) -> String {
    status == "Observed" ? "Activity unconfirmed" : status == MLXRuntimes.status ? "Runtime loaded" : status
}

/// One box in the observed-harness graph. Every value is measured or reported; "Not reported" stands for a missing one.
struct HarnessNode: Identifiable {
    enum Kind: String, CaseIterable { case process, harness, model, tools, subagents, children, response, output }
    struct Fact: Identifiable { let label: String; let value: String; var id: String { label } }
    let kind: Kind
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    /// False when the node has nothing observed behind it, so it is drawn dimmed with a dashed link.
    let observed: Bool
    let facts: [Fact]
    var id: String { kind.rawValue }
    var summary: String { ([title + ": " + detail] + facts.map { "\($0.label) \($0.value)" }).joined(separator: ". ") }

    static func nodes(for harness: Harness, now: Date = Date()) -> [HarnessNode] {
        let session = harness.session
        let hasEvents = !session.events.isEmpty
        var result: [HarnessNode] = []

        var processFacts: [Fact] = []
        if let root = harness.root {
            processFacts = [Fact(label: "Name", value: root.name), Fact(label: "PID / parent", value: "\(root.pid) / \(root.parent)"),
                            Fact(label: "State", value: root.state), Fact(label: "CPU (one core)", value: percent(root.cpu)),
                            Fact(label: "Memory", value: root.memory.map(bytes) ?? "—"), Fact(label: "Threads", value: root.threads.map(String.init) ?? "—"),
                            Fact(label: "Running for", value: elapsed(now.timeIntervalSince(root.startDate))),
                            Fact(label: "Child processes", value: String(harness.processes.count))]
        } else { processFacts = [Fact(label: "Process", value: harness.processNote)] }
        result.append(HarnessNode(kind: .process, title: "Process", detail: harness.root.map { "\($0.name) · \($0.pid)" } ?? "Not reported",
                                  symbol: "terminal", color: HUD.blue, observed: harness.root != nil, facts: processFacts))

        result.append(HarnessNode(kind: .harness, title: session.app.rawValue, detail: statusLabel(session.status),
                                  symbol: "point.3.connected.trianglepath.dotted", color: HUD.green, observed: true, facts: [
            Fact(label: "Status", value: statusLabel(session.status)), Fact(label: "Session", value: String(session.id.prefix(18))),
            Fact(label: "Source", value: session.source), Fact(label: "Started", value: session.started.formatted(date: .omitted, time: .shortened)),
            Fact(label: "Last update", value: elapsed(now.timeIntervalSince(session.updated)) + " ago"),
            Fact(label: "Turns seen", value: hasEvents ? String(harness.turns) : "No events"),
            Fact(label: "Events recorded", value: String(session.events.count))]))

        result.append(HarnessNode(kind: .model, title: "Model", detail: session.model ?? "Not reported", symbol: "cpu", color: HUD.cyan,
                                  observed: session.model != nil, facts: [
            Fact(label: "Model", value: session.model ?? "Not reported by this harness"),
            Fact(label: "Tokens", value: session.tokens.map { "\(String($0)) cumulative" } ?? "Not reported"),
            Fact(label: "Source", value: session.source)]))

        let toolDetail = harness.runningTool.map { "\($0.name) · running" } ?? harness.tools.first.map { "\($0.name) · last used" } ?? (hasEvents ? "None reported" : "Awaiting events")
        let toolFacts = harness.tools.isEmpty
            ? [Fact(label: "Tools", value: hasEvents ? "No tool events in the recorded window" : "Lifecycle hooks are needed for tool events")]
            : harness.tools.prefix(7).map { Fact(label: $0.name, value: "\($0.calls) calls" + ($0.failures > 0 ? " · \($0.failures) failed" : "") + ($0.running ? " · running" : "")) }
        result.append(HarnessNode(kind: .tools, title: harness.tools.isEmpty ? "Tools" : "Tools · \(harness.tools.count)", detail: toolDetail,
                                  symbol: "chevron.left.forwardslash.chevron.right", color: HUD.blue, observed: !harness.tools.isEmpty, facts: toolFacts))

        let runningAgents = harness.subagents.filter(\.isRunning).count
        let agentFacts = harness.subagents.isEmpty
            ? [Fact(label: "Subagents", value: "None observed for this session")]
            : harness.subagents.prefix(7).map { Fact(label: String($0.id.prefix(12)), value: statusLabel($0.state) + ($0.model.map { " · \($0)" } ?? "")) }
        result.append(HarnessNode(kind: .subagents, title: "Subagents", detail: harness.subagents.isEmpty ? "None observed" : "\(runningAgents) running · \(harness.subagents.count) seen",
                                  symbol: "square.stack.3d.up", color: HUD.magenta, observed: !harness.subagents.isEmpty, facts: agentFacts))

        let childDetail = harness.root == nil ? "Not reported" : harness.processes.first.map { "\(harness.processes.count) · \($0.name) \(percent($0.cpu))" } ?? "No child processes"
        let childFacts = harness.root == nil ? [Fact(label: "Processes", value: harness.processNote)]
            : harness.processes.isEmpty ? [Fact(label: "Processes", value: "The harness process has no observable children")]
            : harness.processes.prefix(7).map { Fact(label: "\($0.name) · \($0.pid)", value: "\(percent($0.cpu)) · \($0.memory.map(bytes) ?? "—")") }
        result.append(HarnessNode(kind: .children, title: "Processes", detail: childDetail, symbol: "square.3.layers.3d", color: HUD.purple,
                                  observed: !harness.processes.isEmpty, facts: childFacts))

        let response = session.isRunning ? "Working" : session.events.contains { $0.event == "Stop" } ? "Last turn ended" : "Awaiting event"
        result.append(HarnessNode(kind: .response, title: "Response", detail: response, symbol: "text.bubble", color: HUD.magenta, observed: hasEvents, facts: [
            Fact(label: "Last event", value: harness.lastEvent?.event ?? "None recorded"),
            Fact(label: "When", value: harness.lastEvent.map { elapsed(now.timeIntervalSince($0.date)) + " ago" } ?? "—"),
            Fact(label: "Turns seen", value: hasEvents ? String(harness.turns) : "—"),
            Fact(label: "Tree CPU", value: percent(harness.cpu)), Fact(label: "Tree memory", value: harness.memory.map(bytes) ?? "—")]))

        result.append(HarnessNode(kind: .output, title: "Output", detail: session.status == "Ended" ? "Ended" : session.status == "Idle" ? "Idle" : "—",
                                  symbol: "checkmark.circle", color: HUD.green, observed: ["Ended", "Idle"].contains(session.status), facts: [
            Fact(label: "Status", value: statusLabel(session.status)),
            Fact(label: "Last update", value: session.updated.formatted(date: .omitted, time: .standard))]))
        return result
    }
}

/// The selected session drawn as its real harness: process, agent, model, reported tools and subagents, spawned processes.
struct HarnessGraph: View {
    let harness: Harness
    var previewHover: HarnessNode.Kind?
    let open: () -> Void
    @State private var hovered: HarnessNode.Kind?
    private static let lanes: [HarnessNode.Kind] = [.model, .tools, .subagents, .children]
    private struct Slot { let x: Double; let y: Double; let width: Double; let height: CGFloat }
    private func slot(_ kind: HarnessNode.Kind) -> Slot {
        switch kind {
        case .process: Slot(x: 0.075, y: 0.5, width: 0.15, height: 40)
        case .harness: Slot(x: 0.275, y: 0.5, width: 0.16, height: 40)
        case .response: Slot(x: 0.785, y: 0.5, width: 0.15, height: 40)
        case .output: Slot(x: 0.94, y: 0.5, width: 0.115, height: 40)
        default: Slot(x: 0.53, y: (Double(Self.lanes.firstIndex(of: kind) ?? 0) + 0.5) / Double(Self.lanes.count), width: 0.25, height: 33)
        }
    }
    private func route(_ from: HarnessNode.Kind, _ to: HarnessNode.Kind) -> NeonRoute {
        let a = slot(from), b = slot(to)
        return NeonRoute(x1: a.x + a.width / 2, y1: a.y, x2: b.x - b.width / 2, y2: b.y)
    }
    private var links: [(route: NeonRoute, to: HarnessNode.Kind)] {
        [(route(.process, .harness), .process)] + Self.lanes.map { (route(.harness, $0), $0) } + Self.lanes.map { (route($0, .response), $0) } + [(route(.response, .output), .response)]
    }
    var body: some View {
        let nodes = HarnessNode.nodes(for: harness)
        let observed = Dictionary(uniqueKeysWithValues: nodes.map { ($0.kind, $0.observed) })
        let session = harness.session
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            ZStack {
                Canvas { context, size in
                    for link in links {
                        var path = Path()
                        let a = CGPoint(x: link.route.x1 * size.width, y: link.route.y1 * size.height), b = CGPoint(x: link.route.x2 * size.width, y: link.route.y2 * size.height)
                        path.move(to: a); path.addCurve(to: b, control1: CGPoint(x: (a.x + b.x) / 2, y: a.y), control2: CGPoint(x: (a.x + b.x) / 2, y: b.y))
                        let solid = observed[link.to] == true
                        context.stroke(path, with: .linearGradient(Gradient(colors: [HUD.cyan, HUD.purple, HUD.magenta, HUD.green]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                                       style: StrokeStyle(lineWidth: solid ? 1.5 : 1, dash: solid ? [] : [3, 3]))
                    }
                }.opacity(0.9)
                if session.isRunning && session.events.last.map({ Date().timeIntervalSince($0.date) < 10 }) == true { NeonFlow(effect: .routes(links.map(\.route))) }
                ForEach(nodes) { node in
                    let place = slot(node.kind)
                    Button(action: open) { box(node, height: place.height) }
                        .buttonStyle(.plain)
                        .frame(width: w * place.width).position(x: w * place.x, y: h * place.y)
                        .onHover { inside in if inside { hovered = node.kind } else if hovered == node.kind { hovered = nil } }
                        .accessibilityLabel(node.summary).accessibilityHint("Opens the session inspector")
                }
                if let kind = hovered ?? previewHover, let node = nodes.first(where: { $0.kind == kind }) {
                    let place = slot(kind)
                    let cardWidth = min(230.0, w * 0.42), cardHeight = 34.0 + 14.0 * Double(node.facts.count)
                    let side = place.x < 0.5 ? 1.0 : -1.0
                    let x = w * place.x + side * (w * place.width / 2 + 8 + cardWidth / 2)
                    HarnessHoverCard(node: node).frame(width: cardWidth)
                        .position(x: min(max(cardWidth / 2, x), w - cardWidth / 2), y: min(max(cardHeight / 2, h * place.y), max(cardHeight / 2, h - cardHeight / 2)))
                        .allowsHitTesting(false).transition(.opacity)
                }
            }
        }
    }
    private func box(_ node: HarnessNode, height: CGFloat) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) { Image(systemName: node.symbol).font(.system(size: 12)); Text(node.title).font(.system(size: 10, weight: .semibold)) }
                .foregroundStyle(node.color).lineLimit(1).minimumScaleFactor(0.7)
            Text(node.detail).font(.system(size: 8)).foregroundStyle(node.observed ? HUD.text : HUD.muted).lineLimit(1).minimumScaleFactor(0.65)
        }.padding(.horizontal, 4).frame(maxWidth: .infinity).frame(height: height)
        .background(LinearGradient(colors: [node.color.opacity(node.observed ? 0.22 : 0.08), HUD.background], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 10))
        .background(HUD.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(node.color.opacity(hovered == node.kind ? 1 : node.observed ? 0.9 : 0.4), lineWidth: hovered == node.kind ? 1.6 : 1))
        .shadow(color: node.color.opacity(node.observed ? 0.4 : 0.1), radius: 5)
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct HarnessHoverCard: View {
    let node: HarnessNode
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: node.symbol).foregroundStyle(node.color)
                Text(node.title).font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 4)
                Text("Click to inspect").font(.system(size: 8)).foregroundStyle(HUD.muted)
            }
            ForEach(node.facts) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(fact.label).foregroundStyle(HUD.muted).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(fact.value).monospacedDigit().lineLimit(node.facts.count == 1 ? 3 : 1).multilineTextAlignment(.trailing).minimumScaleFactor(0.75)
                }.font(.system(size: 9))
            }
        }.padding(9)
        .background(Color(hex: 0x06101a).opacity(0.97), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(node.color.opacity(0.7), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.6), radius: 8, y: 3)
    }
}

struct ExecutionTimeline: View {
    let events: [SessionEvent]
    var body: some View {
        Canvas { context, size in
            guard let first = events.first, let last = events.last else { return }
            let duration = max(1, last.timestamp - first.timestamp)
            for (index, event) in events.enumerated() {
                let x = (event.timestamp - first.timestamp) / duration * size.width
                let end = index + 1 < events.count ? (events[index + 1].timestamp - first.timestamp) / duration * size.width : size.width
                let color = event.event.contains("Tool") ? HUD.blue : event.event.contains("Subagent") ? HUD.magenta : event.event == "Stop" ? HUD.green : HUD.cyan
                context.fill(Path(CGRect(x: x, y: 0, width: max(2, end - x), height: size.height)), with: .linearGradient(Gradient(colors: [color, color.opacity(0.45)]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
            }
        }.clipShape(RoundedRectangle(cornerRadius: 4)).accessibilityLabel("Recorded execution events, from \(events.first?.date.formatted() ?? "unknown") to \(events.last?.date.formatted() ?? "unknown")")
    }
}

/// Deep dive into one session: identity, the process tree behind it, reported tools and subagents, and recorded events.
struct SessionInspector: View {
    @Bindable var store: MonitorStore
    @Environment(\.hudSnapshot) private var snapshot
    private var session: AgentSession? { store.sessions.first { $0.id == store.inspectedSessionID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Session inspector").font(.title2)
                Spacer()
                if !snapshot { Button("Close", systemImage: "xmark") { store.inspectedSessionID = nil }.labelStyle(.iconOnly).keyboardShortcut(.cancelAction) }
            }
            if let session {
                let harness = HarnessBuilder.build(session: session, sessions: store.sessions, processes: store.latest?.processes ?? [])
                let sections = VStack(alignment: .leading, spacing: 16) { identity(harness); processes(harness); tools(harness); subagents(harness); events(harness) }.padding(.trailing, 8)
                // ImageRenderer cannot draw scroll views, so snapshots lay the sections out directly.
                if snapshot { sections } else { ScrollView { sections } }
            } else {
                ContentUnavailableView("Session no longer listed", systemImage: "stop.circle", description: Text("It ended, was archived, or its process exited."))
            }
            Text("Metadata only: no prompts, commands, tool input or output, or transcripts are read.").font(.caption).foregroundStyle(HUD.muted)
        }.padding(24).frame(width: 760, height: snapshot ? nil : 720).background(HUD.background).foregroundStyle(HUD.text).preferredColorScheme(.dark)
    }

    private func identity(_ harness: Harness) -> some View {
        let session = harness.session
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(session.model ?? "Model not reported").font(.title3).foregroundStyle(HUD.cyan).lineLimit(1)
                StatusPill(text: statusLabel(session.status), color: session.isRunning ? HUD.green : session.status == "Waiting" ? HUD.amber : session.status == "Error" ? HUD.red : HUD.muted)
            }
            Text("\(session.app.rawValue) · \(session.id)").font(.system(size: 11, design: .monospaced)).foregroundStyle(HUD.muted).textSelection(.enabled).lineLimit(1)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 10) {
                fact("Started", session.started.formatted(date: .abbreviated, time: .shortened))
                fact("Last update", elapsed(Date().timeIntervalSince(session.updated)) + " ago")
                fact("Tokens", session.tokens.map { "\(String($0)) cumulative" } ?? "Not reported")
                fact("Turns seen", session.events.isEmpty ? "No events" : String(harness.turns))
                fact("Last event", harness.lastEvent?.event ?? "None recorded")
                fact("Tree CPU / memory", "\(percent(harness.cpu)) / \(harness.memory.map(bytes) ?? "—")")
                fact("Source", session.source)
                if let parent = session.parent { fact("Parent session", String(parent.prefix(18))) }
            }
        }
    }

    private func processes(_ harness: Harness) -> some View {
        section("Harness process", note: harness.processNote) {
            if let root = harness.root {
                processRow(root, root: true)
                ForEach(harness.processes.prefix(40)) { processRow($0, root: false) }
                if harness.processes.count > 40 { Text("\(harness.processes.count - 40) more child processes").font(.caption).foregroundStyle(HUD.muted) }
            }
        }
    }

    private func processRow(_ process: ProcessSample, root: Bool) -> some View {
        Button {
            store.inspectedSessionID = nil
            Task { try? await Task.sleep(for: .milliseconds(350)); store.inspect(process) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: root ? "circle.hexagongrid" : "arrow.turn.down.right").foregroundStyle(root ? HUD.cyan : HUD.purple).frame(width: 16)
                Text(process.name).lineLimit(1)
                Text("PID \(String(process.pid)) ← \(String(process.parent))").font(.system(size: 9, design: .monospaced)).foregroundStyle(HUD.muted)
                Spacer(minLength: 4)
                Text(process.state).foregroundStyle(HUD.muted).frame(width: 66, alignment: .trailing)
                Text(elapsed(Date().timeIntervalSince(process.startDate))).foregroundStyle(HUD.muted).frame(width: 60, alignment: .trailing)
                Text(percent(process.cpu)).monospacedDigit().foregroundStyle(HUD.cyan).frame(width: 44, alignment: .trailing)
                Text(process.memory.map(bytes) ?? "—").monospacedDigit().frame(width: 74, alignment: .trailing)
            }.font(.system(size: 11)).padding(.vertical, 5).padding(.horizontal, 7)
                .background(HUD.cyan.opacity(root ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).help("Open the process inspector for \(process.name)")
    }

    private func tools(_ harness: Harness) -> some View {
        section("Tools", note: harness.tools.isEmpty ? (harness.session.events.isEmpty ? "Lifecycle hooks are needed to see tool activity" : "No tool events in the recorded window") : "Names and counts from lifecycle events · last \(harness.session.events.count) events") {
            ForEach(harness.tools) { tool in
                HStack(spacing: 8) {
                    Circle().fill(tool.running ? HUD.green : HUD.muted.opacity(0.5)).frame(width: 6, height: 6)
                    Text(tool.name).lineLimit(1)
                    Spacer(minLength: 4)
                    if tool.failures > 0 { Text("\(tool.failures) failed").foregroundStyle(HUD.amber) }
                    Text("\(tool.calls) calls").monospacedDigit().frame(width: 62, alignment: .trailing)
                    Text(tool.running ? "running" : elapsed(Date().timeIntervalSince(tool.last)) + " ago").foregroundStyle(tool.running ? HUD.green : HUD.muted).frame(width: 84, alignment: .trailing)
                }.font(.system(size: 11)).padding(.vertical, 3)
            }
        }
    }

    private func subagents(_ harness: Harness) -> some View {
        section("Subagents", note: harness.subagents.isEmpty ? "None observed for this session" : "\(harness.subagents.filter(\.isRunning).count) running · \(harness.subagents.count) seen") {
            ForEach(harness.subagents) { agent in
                HStack(spacing: 8) {
                    Circle().fill(agent.isRunning ? HUD.green : HUD.muted.opacity(0.5)).frame(width: 6, height: 6)
                    Text(String(agent.id.prefix(24))).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                    if let model = agent.model { Text(model).foregroundStyle(HUD.muted).lineLimit(1) }
                    Spacer(minLength: 4)
                    Text(statusLabel(agent.state)).foregroundStyle(agent.isRunning ? HUD.green : HUD.muted)
                    if agent.linkedSession { Button("Open") { store.inspectedSessionID = agent.id; store.selectedSessionID = agent.id }.buttonStyle(.borderless) }
                }.font(.system(size: 11)).padding(.vertical, 3)
            }
        }
    }

    private func events(_ harness: Harness) -> some View {
        let recorded = harness.session.events
        return section("Recorded events", note: recorded.isEmpty ? "Session metadata only · lifecycle hooks add tool, turn and subagent events" : "Most recent first · event name, tool name and subagent ID only") {
            if !recorded.isEmpty {
                ExecutionTimeline(events: recorded).frame(height: 14)
                ForEach(Array(recorded.suffix(30).reversed())) { event in
                    HStack(spacing: 8) {
                        Text(event.date.formatted(date: .omitted, time: .standard)).font(.system(size: 10, design: .monospaced)).foregroundStyle(HUD.muted).frame(width: 78, alignment: .leading)
                        Text(event.event).frame(width: 150, alignment: .leading)
                        Text(event.tool ?? "").foregroundStyle(HUD.blue).lineLimit(1)
                        Spacer(minLength: 4)
                        if let agent = event.agent { Text(String(agent.prefix(12))).font(.system(size: 9, design: .monospaced)).foregroundStyle(HUD.magenta) }
                    }.font(.system(size: 11)).padding(.vertical, 1)
                }
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(HUD.muted)
            Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func section<Content: View>(_ title: String, note: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) { Text(title).font(.headline); Text(note).font(.system(size: 10)).foregroundStyle(HUD.muted).lineLimit(2) }
            content()
            Divider().overlay(HUD.cyan.opacity(0.12))
        }
    }
}
