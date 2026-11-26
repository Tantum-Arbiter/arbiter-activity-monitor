import SwiftUI
import AppKit

/// Uses the window's actual display, including when moved between displays.
struct AdaptiveWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> ScreenFitView { ScreenFitView() }
    func updateNSView(_ view: ScreenFitView, context: Context) {}
}

final class ScreenFitView: NSView {
    private weak var observedWindow: NSWindow?
    private var initialFit = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, observedWindow !== window else { return }
        NotificationCenter.default.removeObserver(self)
        observedWindow = window
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSWindow.didChangeScreenNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSWindow.didEndLiveResizeNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Wait for SwiftUI's restored frame before applying screen constraints.
        Task { @MainActor [weak self] in self?.fit(initial: true) }
    }
    @objc private func screenChanged() { fit(initial: false) }
    private func fit(initial: Bool) {
        guard let window, let screen = window.screen, !window.styleMask.contains(.fullScreen), !window.inLiveResize else { return }
        let area = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        var frame = window.frame
        if initial && !initialFit {
            initialFit = true
            frame.size = NSSize(width: min(1920, area.width), height: min(1200, area.height))
            frame.origin = NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2)
        } else {
            frame.size.width = min(frame.width, area.width)
            frame.size.height = min(frame.height, area.height)
            frame.origin.x = min(max(frame.minX, area.minX), area.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, area.minY), area.maxY - frame.height)
        }
        if frame != window.frame { window.setFrame(frame, display: true) }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}

struct HUDGrid: View {
    var body: some View {
        Canvas { context, size in
            for spacing in [30.0, 150.0] {
                var lines = Path()
                for x in stride(from: 0.0, through: size.width, by: spacing) {
                    lines.move(to: CGPoint(x: x, y: 0)); lines.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 0.0, through: size.height, by: spacing) {
                    lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(lines, with: .color(HUD.cyan.opacity(spacing == 30 ? 0.055 : 0.10)), lineWidth: 0.6)
            }
        }
        .background(RadialGradient(colors: [HUD.cyan.opacity(0.08), .clear], center: .center, startRadius: 50, endRadius: 700))
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
