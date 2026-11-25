import SwiftUI
import ArbiterCore

/// Ordering for app and process consumption lists.
enum ConsumptionSort: String, CaseIterable { case cpu = "CPU", memory = "Memory" }

extension Array where Element == ProcessSample {
    func sorted(by sort: ConsumptionSort) -> [ProcessSample] {
        sorted { a, b in
            switch sort {
            case .cpu: (a.cpu ?? -1) == (b.cpu ?? -1) ? a.pid < b.pid : (a.cpu ?? -1) > (b.cpu ?? -1)
            case .memory: (a.memory ?? 0) == (b.memory ?? 0) ? a.pid < b.pid : (a.memory ?? 0) > (b.memory ?? 0)
            }
        }
    }
}

extension Array where Element == Workload {
    func sorted(by sort: ConsumptionSort) -> [Workload] {
        sorted { a, b in
            switch sort {
            case .cpu: (a.cpu ?? -1) == (b.cpu ?? -1) ? a.root.pid < b.root.pid : (a.cpu ?? -1) > (b.cpu ?? -1)
            case .memory: a.memory == b.memory ? a.root.pid < b.root.pid : a.memory > b.memory
            }
        }
    }
}

/// A checkbox for multi-select lists.
struct SelectBox: View {
    let selected: Bool
    var partial = false
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            Image(systemName: selected ? "checkmark.square.fill" : partial ? "minus.square.fill" : "square")
                .font(.system(size: 12)).foregroundStyle(selected || partial ? HUD.cyan : HUD.muted).frame(width: 16, height: 16)
        }.buttonStyle(.plain).accessibilityLabel(selected ? "Deselect" : "Select")
    }
}

/// A column title that sorts the list when clicked.
struct SortHeader: View {
    let title: String
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(title)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).opacity(active ? 1 : 0)
            }.foregroundStyle(active ? HUD.cyan : HUD.muted)
        }.buttonStyle(.plain).help("Sort by \(title.lowercased()), highest first")
    }
}

/// Appears while processes are selected: Quit, Force Quit or clear the selection.
struct QuitBar: View {
    let count: Int
    let clear: () -> Void
    let quit: (QuitMode) -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.square.fill").foregroundStyle(HUD.cyan)
            Text("\(count) selected").monospacedDigit()
            Spacer(minLength: 4)
            Button("Clear", action: clear).buttonStyle(.plain).foregroundStyle(HUD.muted)
            Button { quit(.quit) } label: { Label("Quit", systemImage: "xmark.circle") }.buttonStyle(.plain).foregroundStyle(HUD.cyan)
                .help("Ask the selected processes to close")
            Button { quit(.forceQuit) } label: { Label("Force Quit", systemImage: "xmark.octagon") }.buttonStyle(.plain).foregroundStyle(HUD.amber)
                .help("End the selected processes immediately")
        }.font(.system(size: 10, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 5)
            .background(HUD.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(HUD.cyan.opacity(0.25), lineWidth: 0.6))
    }
}

/// Right-click Quit / Force Quit for a single process row.
struct QuitMenu: ViewModifier {
    let processes: [ProcessSample]
    let quit: (([ProcessSample], QuitMode) -> Void)?
    func body(content: Content) -> some View {
        if let quit {
            content.contextMenu {
                let blocker = processes.count == 1 ? ProcessControl.blocker(for: processes[0]) : nil
                Button("Quit") { quit(processes, .quit) }.disabled(blocker != nil)
                Button("Force Quit") { quit(processes, .forceQuit) }.disabled(blocker != nil)
                if let blocker { Text(blocker) }
            }
        } else { content }
    }
}

/// The confirmation for every Quit / Force Quit, wherever it was started.
struct QuitConfirmation: ViewModifier {
    @Bindable var store: MonitorStore
    func body(content: Content) -> some View {
        content.alert(store.quitRequest?.title ?? "", isPresented: Binding(get: { store.quitRequest != nil }, set: { if !$0 { store.quitRequest = nil } }), presenting: store.quitRequest) { request in
            Button(request.mode.rawValue, role: .destructive) { store.confirmQuit() }
            Button("Cancel", role: .cancel) { store.quitRequest = nil }
        } message: { request in Text(request.message) }
    }
}
