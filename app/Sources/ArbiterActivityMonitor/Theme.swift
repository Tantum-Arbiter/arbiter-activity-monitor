import SwiftUI

enum HUD {
    static let background = Color(hex: 0x080f1e)
    static let panel = Color(hex: 0x0c1929)
    static let cyan = Color(hex: 0x20f4ff)
    static let purple = Color(hex: 0xb947ff)
    static let blue = Color(hex: 0x278bff)
    static let magenta = Color(hex: 0xff42ed)
    static let green = Color(hex: 0x00ff88)
    static let amber = Color(hex: 0xffbb22)
    static let red = Color(hex: 0xff2255)
    static let text = Color(hex: 0xd8eef8)
    static let muted = Color(hex: 0x78a8bc)
}

private struct HUDReducedMotionKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var hudReducedMotion: Bool {
        get { self[HUDReducedMotionKey.self] }
        set { self[HUDReducedMotionKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "—" }
func bytes(_ value: UInt64) -> String {
    let units = ["B", "KiB", "MiB", "GiB", "TiB"]
    var number = Double(value)
    var index = 0
    while number >= 1024 && index < units.count - 1 { number /= 1024; index += 1 }
    return String(format: index > 0 && number < 100 ? "%.1f %@" : "%.0f %@", number, units[index])
}
func rate(_ value: Double?) -> String { value.map { bytes(UInt64(max(0, $0))) + "/s" } ?? "—" }

struct Panel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @State private var hovered = false
    @Environment(\.hudReducedMotion) private var reducedMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(HUD.muted)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [HUD.panel, HUD.background], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(HUD.cyan.opacity(hovered ? 0.38 : 0.18)))
        .onHover { hovered = $0 }
        .animation(reducedMotion ? nil : .easeOut(duration: 0.14), value: hovered)
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = HUD.green
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(color.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.22)))
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    var color: Color = HUD.cyan
    var progress: Double?
    var readings: [Double] = []
    var timestamp: Date?
    var source: String = "Native macOS collector"
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: symbol).foregroundStyle(color).font(.system(size: 15))
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(HUD.muted)
                Spacer(minLength: 0)
            }
            Text(value).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            Text(detail).font(.system(size: 9)).foregroundStyle(HUD.muted).lineLimit(2)
            if readings.count > 1 {
                Canvas { context, size in
                    let maxValue = max(1, readings.max() ?? 1)
                    var path = Path()
                    for (index, value) in readings.enumerated() {
                        let point = CGPoint(x: Double(index) / Double(readings.count - 1) * size.width, y: (1 - value / maxValue) * size.height)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(path, with: .color(color), lineWidth: 1)
                }.frame(height: 14).accessibilityHidden(true)
            }
            GeometryReader { geometry in
                Capsule().fill(color.opacity(0.1))
                    .overlay(alignment: .leading) {
                        if let progress { Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, progress / 100))) }
                    }
            }.frame(height: 3)
        }
        .padding(12).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
        .help(source + (timestamp.map { "\nMeasured " + $0.formatted(date: .omitted, time: .standard) } ?? "") + (readings.isEmpty ? "" : String(format: "\nRecent raw readings: average %.1f · peak %.1f", readings.reduce(0, +) / Double(readings.count), readings.max() ?? 0)))
    }
}
