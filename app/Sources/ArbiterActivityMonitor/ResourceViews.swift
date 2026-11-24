import SwiftUI
import Charts
import ArbiterCore

struct ResourcesPanel: View {
    let sample: SystemSample?
    var navigate: (Destination) -> Void = { _ in }
    var history: [SystemSample] = []
    var body: some View {
        Panel(title: "System performance", subtitle: "APPLE SILICON / LOCAL TELEMETRY") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                Button { navigate(.cpu) } label: { MetricTile(title: "CPU", value: percent(sample?.cpu), detail: "\(ProcessInfo.processInfo.processorCount) cores · total capacity", symbol: "cpu", progress: sample?.cpu, readings: history.suffix(30).compactMap(\.cpu), timestamp: sample?.id, source: "Mach CPU tick deltas · percent") }
                Button { navigate(.memory) } label: { MetricTile(title: "Unified memory", value: sample.map { bytes($0.memoryUsed) } ?? "—", detail: sample.map { "of \(bytes($0.memoryTotal)) · \($0.pressure)" } ?? "Collecting…", symbol: "memorychip", color: HUD.purple, progress: sample?.memoryPercent, readings: history.suffix(30).compactMap(\.memoryPercent), timestamp: sample?.id, source: "Mach VM pages · recent readings in percent") }
                Button { navigate(.storage) } label: { MetricTile(title: "Storage", value: sample.flatMap { $0.diskTotal > 0 ? bytes($0.diskFree) : nil } ?? "—", detail: "Available · Data volume", symbol: "internaldrive", progress: sample.flatMap { $0.diskTotal > 0 ? 100 * Double($0.diskTotal - min($0.diskFree, $0.diskTotal)) / Double($0.diskTotal) : nil }) }
                Button { navigate(.network) } label: { MetricTile(title: "Network", value: rate(sample?.download), detail: "↑ \(rate(sample?.upload))", symbol: "network", color: HUD.cyan, readings: history.suffix(30).compactMap(\.download), timestamp: sample?.id, source: "Physical interface counters · bytes/second") }
                Button { navigate(.battery) } label: { MetricTile(title: "Battery", value: percent(sample?.battery), detail: sample?.battery == nil ? "No battery reading" : sample?.onPower == true ? "External power" : "On battery", symbol: "battery.75percent", color: HUD.green, progress: sample?.battery, timestamp: sample?.id, source: "IOKit power-source capacity · percent") }
                Button { navigate(.thermals) } label: { MetricTile(title: "Thermals", value: sample?.thermal ?? "—", detail: "macOS thermal pressure", symbol: "thermometer.medium", color: sample?.thermal == "Critical" ? HUD.red : HUD.green) }
            }
            .buttonStyle(.plain)
        }
    }
}

struct SystemDial: View {
    let sample: SystemSample?
    let paused: Bool
    var health: Health = .unknown
    var navigate: (Destination) -> Void = { _ in }
    var body: some View {
        VStack(spacing: 12) {
            Text("SYSTEM / AI OPERATIONS").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(HUD.muted)
            ZStack {
                Circle().fill(RadialGradient(colors: [HUD.cyan.opacity(0.09), HUD.purple.opacity(0.03), .clear], center: .center, startRadius: 15, endRadius: 125))
                ForEach([0, 1, 2], id: \.self) { ring in
                    Circle().stroke(HUD.cyan.opacity(ring == 0 ? 0.2 : 0.08), style: StrokeStyle(lineWidth: 1, dash: ring == 1 ? [2, 8] : []))
                        .padding(CGFloat(ring) * 19)
                }
                Circle().trim(from: 0, to: 0.75).stroke(HUD.cyan.opacity(0.12), style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(135)).padding(9)
                Button { navigate(.cpu) } label: {
                    Circle().trim(from: 0, to: 0.75 * (sample?.cpu ?? 0) / 100).stroke(HUD.cyan, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(135)).padding(9)
                }.buttonStyle(.plain).help("CPU \(percent(sample?.cpu)) · Mach host ticks").accessibilityLabel("CPU gauge, \(percent(sample?.cpu))")
                Circle().trim(from: 0, to: 0.75 * (sample?.gpu ?? 0) / 100).stroke(HUD.blue.opacity(0.8), style: StrokeStyle(lineWidth: 2)).rotationEffect(.degrees(135)).padding(20).accessibilityLabel("GPU \(percent(sample?.gpu))")
                Button { navigate(.memory) } label: {
                    Circle().trim(from: 0, to: 0.75 * (sample?.memoryPercent ?? 0) / 100).stroke(HUD.purple, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(135)).padding(28)
                }.buttonStyle(.plain).help("Memory \(percent(sample?.memoryPercent)) · Mach VM statistics").accessibilityLabel("Memory gauge, \(percent(sample?.memoryPercent))")
                VStack(spacing: 7) {
                    Image(systemName: "desktopcomputer").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(HUD.cyan)
                    Text(percent(sample?.cpu)).font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit()
                    Text(health.rawValue.uppercased()).font(.system(size: 9, design: .monospaced)).tracking(1).foregroundStyle(HUD.muted)
                }.allowsHitTesting(false)
            }.frame(maxWidth: 240, maxHeight: 240).aspectRatio(1, contentMode: .fit)
            HStack(spacing: 16) {
                Button { navigate(.cpu) } label: { Label("CPU", systemImage: "circle.fill").foregroundStyle(HUD.cyan) }
                Button { navigate(.memory) } label: { Label("Memory", systemImage: "circle.fill").foregroundStyle(HUD.purple) }
            }.font(.system(size: 9)).buttonStyle(.plain)
            Button("GPU \(percent(sample?.gpu))") { navigate(.gpu) }.font(.system(size: 9)).foregroundStyle(HUD.muted).buttonStyle(.plain)
            StatusPill(text: paused ? "Sampling paused" : "Local monitoring", color: paused ? HUD.amber : HUD.green)
            Text("No cloud calls. No elevated privileges.").font(.system(size: 9)).foregroundStyle(HUD.muted)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(16)
        .accessibilityElement(children: .contain)
    }
}

struct HeatmapPanel: View {
    let history: [SystemSample]
    var body: some View {
        Panel(title: "Resource heatmap", subtitle: "LATEST 30 PLOTTED OBSERVATIONS · 0–100%") {
            VStack(spacing: 12) {
                heatRow("CPU", color: HUD.cyan) { $0.cpu }
                heatRow("GPU", color: HUD.blue) { $0.gpu }
                heatRow("Memory", color: HUD.purple) { $0.memoryPercent }
                heatRow("AI apps", color: HUD.green) { s in
                    guard s.apps.contains(where: { $0.cpuPercent != nil }) else { return nil }
                    return s.apps.compactMap(\.cpuPercent).reduce(0, +) / Double(ProcessInfo.processInfo.processorCount)
                }
            }
            Text("Low                                      High").font(.system(size: 9, design: .monospaced)).foregroundStyle(HUD.muted)
            Text("GPU · driver utilization where available").font(.system(size: 10)).foregroundStyle(HUD.muted)
        }.frame(height: 226)
    }
    private func heatRow(_ name: String, color: Color, value: @escaping (SystemSample) -> Double?) -> some View {
        let samples = Array(history.suffix(30))
        return HStack(spacing: 8) {
            Text(name).font(.system(size: 10)).frame(width: 45, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(samples) { sample in
                    RoundedRectangle(cornerRadius: 1).fill(color.opacity(value(sample).map { 0.12 + min(100, max(0, $0)) / 100 * 0.88 } ?? 0.03))
                        .help("\(name): \(percent(value(sample))) · \(sample.id.formatted(date: .abbreviated, time: .standard))")
                }
                if samples.isEmpty { Rectangle().fill(color.opacity(0.03)) }
            }.frame(height: 14)
        }.accessibilityLabel("\(name) recent utilization heatmap")
    }
}
