import AppKit
import SwiftUI
import Combine

/// Wraps an NSStatusItem and keeps it in sync with DayManager.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private var hostingView: NSHostingView<StatusBarView>?
    private var cancellables: Set<AnyCancellable> = []
    private let dayManager: DayManager
    private var settingsWindowController: NSWindowController?
    private let barWidth: CGFloat = 70

    init(dayManager: DayManager) {
        self.dayManager = dayManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.length = barWidth + 12
        statusItem.menu = buildMenu()
        statusItem.isVisible = true
        statusItem.button?.toolTip = "DayDrain"

        NSApp.setActivationPolicy(.accessory)

        setupBindings()
        updateProgress(dayManager.progress)
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
                guard let button = self?.statusItem.button else { return }
                button.alphaValue = isActive ? 1.0 : 0.55
            }
            .store(in: &cancellables)

        dayManager.$displayText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                let tooltip = text.isEmpty ? "DayDrain" : text
                self?.statusItem.button?.toolTip = tooltip
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
        if let window = settingsWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView(dayManager: dayManager))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DayDrain Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.contentMinSize = NSSize(width: 520, height: 420)
        window.setContentSize(NSSize(width: 520, height: 420))
        window.center()
        window.setFrameAutosaveName("DayDrainSettingsWindow")

        let controller = NSWindowController(window: window)
        settingsWindowController = controller

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
