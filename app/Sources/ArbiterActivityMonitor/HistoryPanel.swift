import SwiftUI
import ArbiterCore

/// Three bounded vector paths instead of hundreds of independently diffed chart marks.
struct HistoryPanel: View {
    let history: [SystemSample]
    var height: CGFloat = 226
    var spotlight: String?
    var replayDate: Date?
    @State private var hidden = Set<String>()
    @State private var hoverX: CGFloat?
    @State private var zoom: ClosedRange<Date>?
    @State private var drag: ClosedRange<CGFloat>?
    private let series = ["CPU", "GPU", "Memory", "AI apps"]
    private var visible: [SystemSample] { zoom.map { window in history.filter { window.contains($0.id) } } ?? history }
    private func color(_ series: String) -> Color { series == "CPU" ? HUD.cyan : series == "GPU" ? HUD.blue : series == "Memory" ? HUD.purple : HUD.magenta }
    private func value(_ series: String, _ sample: SystemSample) -> Double? {
        switch series {
        case "CPU": sample.cpu
        case "GPU": sample.gpu
        case "Memory": sample.memoryPercent
        default: sample.apps.contains(where: { $0.cpuPercent != nil }) ? sample.apps.compactMap(\.cpuPercent).reduce(0, +) / Double(ProcessInfo.processInfo.processorCount) : nil
        }
    }
    var body: some View {
        ReferencePanel(title: "System & Workload Activity", subtitle: "Correlated utilization · CPU · GPU · memory % · Drag to zoom") {
            if history.count < 2 {
                ContentUnavailableView("Collecting history", systemImage: "waveform.path", description: Text("The chart appears after two samples."))
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 14) {
                        if zoom != nil { Button("Reset zoom") { zoom = nil }.font(.system(size: 10)) }
                        Spacer()
                        ForEach(series, id: \.self) { name in
                            Button {
                                if hidden.contains(name) { hidden.remove(name) } else { hidden.insert(name) }
                            } label: {
                                Label(name, systemImage: hidden.contains(name) ? "circle" : "circle.fill").foregroundStyle(color(name))
                            }.buttonStyle(.plain).font(.system(size: 10)).opacity(hidden.contains(name) ? 0.45 : 1)
                            .accessibilityLabel("\(hidden.contains(name) ? "Show" : "Hide") \(name) series")
                        }
                    }
                    GeometryReader { geometry in
                        let samples = visible
                        let first = samples.first?.id ?? Date()
                        let span = max(1, samples.last?.id.timeIntervalSince(first) ?? 1)
                        ZStack(alignment: .topLeading) {
                            Canvas { context, size in
                                for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                                    var line = Path(); line.move(to: CGPoint(x: 0, y: size.height * fraction)); line.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                                    context.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                                }
                                for name in series where !hidden.contains(name) {
                                    var line = Path(); var started = false; var previousTime: Date?
                                    var area = Path(); var segment: [CGPoint] = []
                                    func closeSegment() {
                                        guard let firstPoint = segment.first, let lastPoint = segment.last else { return }
                                        area.move(to: CGPoint(x: firstPoint.x, y: size.height))
                                        for point in segment { area.addLine(to: point) }
                                        area.addLine(to: CGPoint(x: lastPoint.x, y: size.height)); area.closeSubpath()
                                        segment.removeAll(keepingCapacity: true)
                                    }
                                    for sample in samples {
                                        guard let reading = value(name, sample) else { closeSegment(); started = false; continue }
                                        let point = CGPoint(x: sample.id.timeIntervalSince(first) / span * size.width, y: (1 - min(100, max(0, reading)) / 100) * size.height)
                                        if let previousTime, sample.id.timeIntervalSince(previousTime) > 60 { closeSegment(); started = false }
                                        if started { line.addLine(to: point) } else { line.move(to: point); started = true }
                                        previousTime = sample.id
                                        segment.append(point)
                                    }
                                    closeSegment()
                                    context.fill(area, with: .linearGradient(Gradient(colors: [color(name).opacity(0.28), color(name).opacity(0.015)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                                    context.stroke(line, with: .color(color(name).opacity(spotlight == name ? 0.35:0.12)), lineWidth: 6)
                                    context.stroke(line, with: .color(color(name)), style: StrokeStyle(lineWidth: spotlight == name ? 2.8:1.5, lineJoin: .round))
                                    if let last=samples.last, let reading=value(name,last) {
                                        let point=CGPoint(x:size.width-2,y:(1-min(100,max(0,reading))/100)*size.height)
                                        context.fill(Path(ellipseIn:CGRect(x:point.x-4,y:point.y-4,width:8,height:8)),with:.color(color(name).opacity(0.18)))
                                        context.fill(Path(ellipseIn:CGRect(x:point.x-1.7,y:point.y-1.7,width:3.4,height:3.4)),with:.color(color(name)))
                                    }
                                }
                                if let replayDate {
                                    let x=replayDate.timeIntervalSince(first)/span*size.width
                                    var mark=Path();mark.move(to:CGPoint(x:x,y:0));mark.addLine(to:CGPoint(x:x,y:size.height))
                                    context.stroke(mark,with:.color(HUD.amber),style:StrokeStyle(lineWidth:1,dash:[3,3]))
                                }
                                if let drag {
                                    context.fill(Path(CGRect(x: drag.lowerBound, y: 0, width: drag.upperBound - drag.lowerBound, height: size.height)), with: .color(HUD.cyan.opacity(0.1)))
                                }
                                if let hoverX {
                                    var line = Path(); line.move(to: CGPoint(x: hoverX, y: 0)); line.addLine(to: CGPoint(x: hoverX, y: size.height))
                                    context.stroke(line, with: .color(HUD.text.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                }
                            }
                            .overlay(alignment:.trailing) {SamplePulse(token:samples.last?.id.timeIntervalSince1970 ?? 0).frame(width:5)}
                            .overlay {
                                NeonFlow(effect:.track(flowPoints(samples,series:"CPU")),color:HUD.cyan)
                                NeonFlow(effect:.track(flowPoints(samples,series:"GPU")),color:HUD.blue)
                            }
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase { case .active(let location): hoverX = min(geometry.size.width, max(0, location.x)); case .ended: hoverX = nil }
                            }
                            .gesture(DragGesture(minimumDistance: 12)
                                .onChanged { event in
                                    let a = min(geometry.size.width, max(0, event.startLocation.x))
                                    let b = min(geometry.size.width, max(0, event.location.x))
                                    drag = min(a, b)...max(a, b)
                                }
                                .onEnded { _ in
                                    if let drag, drag.upperBound - drag.lowerBound > 15 {
                                        let a = first.addingTimeInterval(Double(drag.lowerBound / geometry.size.width) * span)
                                        let b = first.addingTimeInterval(Double(drag.upperBound / geometry.size.width) * span)
                                        if samples.filter({ (a...b).contains($0.id) }).count >= 2 { zoom = a...b }
                                    }
                                    drag = nil
                                })
                            if let hoverX, let selected = nearest(at: Double(hoverX / max(1, geometry.size.width)), samples: samples) {
                                Text("\(selected.id.formatted(date: .omitted, time: .standard))  CPU \(percent(selected.cpu))  MEM \(percent(selected.memoryPercent))")
                                    .font(.system(size: 9, design: .monospaced)).padding(5).background(HUD.background.opacity(0.95), in: RoundedRectangle(cornerRadius: 4)).allowsHitTesting(false)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("System history, 0 to 100 percent. Latest CPU \(percent(samples.last?.cpu)), memory \(percent(samples.last?.memoryPercent)). \(samples.count) observed samples.")
                        .overlay(alignment: .trailing) {
                            VStack { Text("100%"); Spacer(); Text("50%"); Spacer(); Text("0%") }.font(.system(size: 8, design: .monospaced)).foregroundStyle(HUD.muted).allowsHitTesting(false)
                        }
                    }
                    HStack {
                        Text(visible.first?.id.formatted(date: .omitted, time: .standard) ?? "—")
                        Spacer()
                        Text(visible.last?.id.formatted(date: .omitted, time: .standard) ?? "—")
                    }.font(.system(size: 9, design: .monospaced)).foregroundStyle(HUD.muted)
                }
            }
        }.frame(height: height)
        .onChange(of: replayDate) { zoom=nil; drag=nil; hoverX=nil }
    }
    private func nearest(at fraction: Double, samples: [SystemSample]) -> SystemSample? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let target = first.id.addingTimeInterval(last.id.timeIntervalSince(first.id) * fraction)
        return samples.min { abs($0.id.timeIntervalSince(target)) < abs($1.id.timeIntervalSince(target)) }
    }
    private func flowPoints(_ samples:[SystemSample],series:String)->[NeonPoint] {
        guard !hidden.contains(series),let first=samples.first,let last=samples.last else {return []}
        let span=max(1,last.id.timeIntervalSince(first.id))
        var result:[NeonPoint]=[];var previous=last.id
        for sample in samples.reversed() {
            guard let reading=value(series,sample),previous.timeIntervalSince(sample.id)<=60 else {break}
            result.append(NeonPoint(x:sample.id.timeIntervalSince(first.id)/span,y:1-min(100,max(0,reading))/100));previous=sample.id
        }
        return result.reversed()
    }
}
