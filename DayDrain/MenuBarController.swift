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
    private let toDoManager: ToDoManager
    private var settingsWindowController: NSWindowController?
    private var latestProgress: Double = 0
    private var latestMenuValue: String = ""
    private let statusItemHorizontalPadding: CGFloat = 8
    private var currentStatusItemLength: CGFloat = 0
    private var latestPulseToken: Int = 0
    private var shouldDimBar: Bool = false
    private var shortcutMonitor: Any?

    private lazy var contextMenu: NSMenu = buildMenu()
    private let panelPopover = NSPopover()
    private var panelHostingController: NSHostingController<ToDoPanel>?

    init(dayManager: DayManager, toDoManager: ToDoManager) {
        self.dayManager = dayManager
        self.toDoManager = toDoManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        statusItem.button?.toolTip = "DayDrain"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemTap)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        NSApp.setActivationPolicy(.accessory)

        latestProgress = max(0, min(1, dayManager.progress))
        latestMenuValue = dayManager.menuValueText
        currentStatusItemLength = calculatedStatusItemLength(for: latestMenuValue)
        statusItem.length = currentStatusItemLength

        panelPopover.behavior = .transient
        panelPopover.animates = true

        setupBindings()
        dayManager.onDayComplete = { [weak self] in
            Task { @MainActor in
                self?.toDoManager.triggerWindDownPrompt()
            }
        }
        registerShortcuts()
        updateStatusBarView()
    }

    deinit {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
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

        toDoManager.$pulseToken
            .receive(on: RunLoop.main)
            .sink { [weak self] token in
                self?.latestPulseToken = token
                self?.updateStatusBarView()
            }
            .store(in: &cancellables)

        toDoManager.$allTasksCompleted
            .receive(on: RunLoop.main)
            .sink { [weak self] completed in
                self?.shouldDimBar = completed
                self?.updateStatusBarView()
            }
            .store(in: &cancellables)
    }

    private func updateStatusBarView() {
        guard let button = statusItem.button else { return }
        let view = StatusBarView(
            progress: latestProgress,
            menuLabel: latestMenuValue,
            pulseToken: latestPulseToken,
            isDimmed: shouldDimBar
        )

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

    @objc private func handleStatusItemTap(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePanel()
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .rightMouseUp || event.type == .rightMouseDown || flags.contains(.control) {
            hidePanel()
            // Use the status item's menu property instead of deprecated popUpMenu(_:)
            statusItem.menu = contextMenu
            // AppKit will present the menu for the click; clear it after to keep left-click behavior custom.
            DispatchQueue.main.async { [weak self] in
                self?.statusItem.menu = nil
            }
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        if panelPopover.isShown {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button else { return }
        updatePopoverContent()
        panelPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = panelPopover.contentViewController?.view.window {
            window.makeKey()
        }
    }

    private func hidePanel() {
        panelPopover.performClose(nil)
    }

    private func updatePopoverContent() {
        let panelView = ToDoPanel(
            manager: toDoManager,
            openSettings: { [weak self] in
                self?.hidePanel()
                self?.openSettings()
            },
            quitApplication: { [weak self] in
                self?.hidePanel()
                self?.quit()
            }
        )

        if let hosting = panelHostingController {
            hosting.rootView = panelView
        } else {
            let hosting = NSHostingController(rootView: panelView)
            panelPopover.contentViewController = hosting
            panelHostingController = hosting
        }
    }

    private func registerShortcuts() {
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if flags.contains([.command, .shift]) {
                if let character = event.charactersIgnoringModifiers?.lowercased() {
                    switch character {
                    case "t":
                        if toDoManager.quickAddTask() {
                            showPanel()
                            return nil
                        }
                        return event
                    case "i":
                        toDoManager.showInboxPanel()
                        showPanel()
                        return nil
                    case "o":
                        withAnimation(.easeInOut(duration: 0.2)) {
                            toDoManager.toggleOverflowSection()
                        }
                        showPanel()
                        return nil
                    case "f":
                        showPanel()
                        toDoManager.focusedTaskID = toDoManager.highlightedTaskID
                        return nil
                    default:
                        break
                    }
                }

                if event.keyCode == 126 { // arrow up
                    toDoManager.moveActiveContextTowardFocus(defaultPriority: .medium)
                    showPanel()
                    return nil
                }

                if event.keyCode == 125 { // arrow down
                    toDoManager.moveActiveContextAwayFromFocus(defaultPriority: .medium)
                    showPanel()
                    return nil
                }
            }

            if flags == [.command], event.keyCode == 36 {
                if toDoManager.markTopIncompleteTaskDone() {
                    return nil
                }
            }

            return event
        }
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
