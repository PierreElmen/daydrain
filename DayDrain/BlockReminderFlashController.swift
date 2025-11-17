import AppKit
import SwiftUI

@MainActor
final class BlockReminderFlashController {
    private struct PanelState {
        let panel: NSPanel
        let state: GlowState
    }

    private var panelStates: [PanelState] = []
    private var flashTask: Task<Void, Never>?

    init() {
        rebuildPanels()
    }

    func flash(color: NSColor, pulses: Int, fadeDuration: TimeInterval, peakOpacity: Double) {
        rebuildPanels()
        flashTask?.cancel()

        let swiftUIColor = Color(nsColor: color)
        panelStates.forEach { panelState in
            panelState.state.color = swiftUIColor
            panelState.state.opacity = 0
            panelState.panel.orderFrontRegardless()
        }

        flashTask = Task { [panelStates] in
            for _ in 0..<max(1, pulses) {
                withAnimation(.easeInOut(duration: fadeDuration)) {
                    panelStates.forEach { $0.state.opacity = peakOpacity }
                }
                try? await Task.sleep(nanoseconds: UInt64(fadeDuration * 1_000_000_000))
                withAnimation(.easeInOut(duration: fadeDuration)) {
                    panelStates.forEach { $0.state.opacity = 0 }
                }
                try? await Task.sleep(nanoseconds: UInt64(fadeDuration * 1_000_000_000))
            }

            withAnimation(.easeInOut(duration: fadeDuration)) {
                panelStates.forEach { $0.state.opacity = 0 }
            }
            try? await Task.sleep(nanoseconds: UInt64(fadeDuration * 1_000_000_000))
            panelStates.forEach { $0.panel.orderOut(nil) }
        }
    }

    private func rebuildPanels() {
        let screens = NSScreen.screens
        guard screens.count != panelStates.count else { return }

        panelStates.forEach { $0.panel.orderOut(nil) }
        panelStates.removeAll()

        for screen in screens {
            let panel = NSPanel(contentRect: screen.frame,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered,
                                defer: true,
                                screen: screen)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .screenSaver
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

            let state = GlowState()
            let hosting = NSHostingView(rootView: EdgeGlowView(state: state))
            hosting.frame = NSRect(origin: .zero, size: screen.frame.size)
            hosting.autoresizingMask = [.width, .height]
            panel.contentView = hosting
            panel.orderOut(nil)

            panelStates.append(.init(panel: panel, state: state))
        }
    }
}

private final class GlowState: ObservableObject {
    @Published var opacity: Double = 0
    @Published var color: Color = .clear
}

private struct EdgeGlowView: View {
    @ObservedObject var state: GlowState

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let verticalThickness = min(height * 0.18, 220)
            let horizontalThickness = min(width * 0.18, 220)
            let glowColor = state.color
            let alpha = state.opacity

            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                glowColor.opacity(alpha),
                                glowColor.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: verticalThickness)
                    .frame(maxHeight: .infinity, alignment: .top)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                glowColor.opacity(alpha),
                                glowColor.opacity(0)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: verticalThickness)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                glowColor.opacity(alpha),
                                glowColor.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: horizontalThickness)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                glowColor.opacity(alpha),
                                glowColor.opacity(0)
                            ],
                            startPoint: .trailing,
                            endPoint: .leading
                        )
                    )
                    .frame(width: horizontalThickness)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .blur(radius: 22)
            .compositingGroup()
            .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
