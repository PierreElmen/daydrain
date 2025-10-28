import AppKit
import SwiftUI
import Combine

/// Wraps the NSStatusBar configuration and keeps it in sync with the published values from
/// the `DayManager`.
final class MenuBarController {
    private let statusItem: NSStatusItem
    private var hostingView: NSHostingView<StatusBarView>?
    private var cancellables: Set<AnyCancellable> = []
    private let dayManager: DayManager
    private let barWidth: CGFloat = 70

    init(dayManager: DayManager) {
        self.dayManager = dayManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.length = barWidth + 12
        statusItem.menu = buildMenu()

        NSApp.setActivationPolicy(.accessory)

        setupBindings()
    }

    private func setupBindings() {
        dayManager.$progress
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                self?.updateProgress(progress)
            }
            .store(in: &cancellables)

        dayManager.$isActive
            .receive(on: RunLoop.main)
            .sink { [weak self] isActive in
                self?.statusItem.isVisible = isActive
                if !isActive {
                    self?.statusItem.button?.toolTip = "DayDrain"
                }
            }
            .store(in: &cancellables)

        dayManager.$displayText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.statusItem.button?.toolTip = text
            }
            .store(in: &cancellables)
    }

    private func updateProgress(_ progress: Double) {
        guard let button = statusItem.button else { return }
        let clamped = max(0, min(1, progress))
        let view = StatusBarView(progress: clamped)

        if let hostingView {
            hostingView.rootView = view
        } else {
            let hosting = NSHostingView(rootView: view)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hosting)

            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
                hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
                hosting.topAnchor.constraint(equalTo: button.topAnchor, constant: 2),
                hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -2),
                hosting.widthAnchor.constraint(equalToConstant: barWidth)
            ])

            self.hostingView = hosting
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit DayDrain", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openSettings() {
        NSApp.sendAction(#selector(NSApplication.showPreferencesWindow(_:)), to: nil, from: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Simple SwiftUI view that renders the draining bar inside the status bar.
struct StatusBarView: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: geometry.size.height / 2)
                    .stroke(Color.primary.opacity(0.35), lineWidth: 1)
                RoundedRectangle(cornerRadius: geometry.size.height / 2)
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * CGFloat(progress))
            }
            .animation(.easeInOut(duration: 0.25), value: progress)
        }
        .frame(width: 70, height: 12)
    }
}
