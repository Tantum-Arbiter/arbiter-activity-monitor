import SwiftUI
import ArbiterCore

/// Width class of the content area (window minus sidebar). Pages reflow at these breakpoints instead of stretching.
enum LayoutWidth: Int, Comparable {
    /// One column: cards stack, tables keep their essential columns, graphs become lists.
    case slim
    /// Stacked panels sized to their content, two-column grids.
    case stacked
    /// The reference multi-column dashboard.
    case wide
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    static func forContent(_ width: CGFloat) -> Self { width < 560 ? .slim : width < 940 ? .stacked : .wide }
}

private struct HUDLayoutKey: EnvironmentKey { static let defaultValue = LayoutWidth.wide }
extension EnvironmentValues {
    var hudLayout: LayoutWidth { get { self[HUDLayoutKey.self] } set { self[HUDLayoutKey.self] = newValue } }
}

/// A compact ring for the stacked overview: measured value in the middle, label and detail beside it.
struct PulseRing: View {
    let title: String
    let value: Double?
    let detail: String
    let color: Color
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(color.opacity(0.14), lineWidth: 7)
                Circle().trim(from: 0, to: min(1, max(0, (value ?? 0) / 100)))
                    .stroke(LinearGradient(colors: [color.opacity(0.65), color], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90)).shadow(color: color.opacity(0.45), radius: 4)
                Text(percent(value)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
            }.frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail).font(.system(size: 9)).foregroundStyle(Color(hex: 0xa7baca)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [color.opacity(0.1), HUD.background.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(color.opacity(0.28), lineWidth: 0.7))
            .accessibilityElement(children: .combine)
    }
}

/// Agent Orchestration as a vertical list for slim windows: the same observed nodes, one per row.
struct HarnessList: View {
    let harness: Harness
    let open: () -> Void
    var body: some View {
        let nodes = HarnessNode.nodes(for: harness)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                Button(action: open) {
                    HStack(alignment: .top, spacing: 9) {
                        VStack(spacing: 0) {
                            Image(systemName: node.symbol).font(.system(size: 12)).foregroundStyle(node.color).frame(width: 26, height: 26)
                                .background(node.color.opacity(node.observed ? 0.16 : 0.05), in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(node.color.opacity(node.observed ? 0.7 : 0.25), style: StrokeStyle(lineWidth: 0.8, dash: node.observed ? [] : [3, 3])))
                            if index < nodes.count - 1 {
                                Rectangle().fill(LinearGradient(colors: [node.color.opacity(0.6), HUD.purple.opacity(0.3)], startPoint: .top, endPoint: .bottom)).frame(width: 1).frame(minHeight: 10, maxHeight: .infinity)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(node.title).font(.system(size: 11, weight: .semibold))
                                Spacer(minLength: 4)
                                Text(node.detail).font(.system(size: 10)).foregroundStyle(node.observed ? HUD.text : HUD.muted).lineLimit(1)
                            }
                            if let fact = node.facts.first(where: { $0.value != node.detail }) {
                                Text("\(fact.label): \(fact.value)").font(.system(size: 9)).foregroundStyle(HUD.muted).lineLimit(1)
                            }
                        }.padding(.top, 4).padding(.bottom, 8)
                    }.contentShape(Rectangle()).opacity(node.observed ? 1 : 0.7)
                }.buttonStyle(HUDRowStyle()).help(node.summary).accessibilityLabel(node.summary).accessibilityHint("Opens the session inspector")
            }
        }
    }
}
