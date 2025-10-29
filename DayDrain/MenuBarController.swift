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
    private var latestProgress: Double = 0
    private var latestMenuValue: String = ""
    private let statusItemHorizontalPadding: CGFloat = 8
    private var currentStatusItemLength: CGFloat = 0

    init(dayManager: DayManager) {
        self.dayManager = dayManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = buildMenu()
        statusItem.isVisible = true
        statusItem.button?.toolTip = "DayDrain"

        NSApp.setActivationPolicy(.accessory)

        latestProgress = max(0, min(1, dayManager.progress))
        latestMenuValue = dayManager.menuValueText
        currentStatusItemLength = calculatedStatusItemLength(for: latestMenuValue)
        statusItem.length = currentStatusItemLength

        setupBindings()
        updateStatusBarView()
    }

    private func setupBindings() {
        dayManager.$progress
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                let clamped = max(0, min(1, progress))
                self?.latestProgress = clamped
                self?.updateStatusBarView()
            }
            .store(in: &cancellables)

        dayManager.$menuValueText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.latestMenuValue = text
                self?.updateStatusBarView()
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

    private func updateStatusBarView() {
        guard let button = statusItem.button else { return }
        let view = StatusBarView(progress: latestProgress, menuLabel: latestMenuValue)

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
                hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -2)
            ])

            self.hostingView = hosting
        }

        let newLength = calculatedStatusItemLength(for: latestMenuValue)
        updateStatusItemLengthIfNeeded(newLength)
    }

    private func calculatedStatusItemLength(for label: String) -> CGFloat {
        let labelWidth = measuredLabelWidth(for: label)
        let spacing = labelWidth > 0 ? StatusBarView.Constants.labelSpacing : 0
        let meterWidth = StatusBarView.Constants.barWidth
        return meterWidth + spacing + labelWidth + statusItemHorizontalPadding
    }

    private func measuredLabelWidth(for text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let width = (text as NSString).size(withAttributes: attributes).width
        return ceil(width)
    }

    private func updateStatusItemLengthIfNeeded(_ newLength: CGFloat) {
        guard abs(currentStatusItemLength - newLength) > 0.5 else { return }
        currentStatusItemLength = newLength

        DispatchQueue.main.async { [weak self] in
            self?.statusItem.length = newLength
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
