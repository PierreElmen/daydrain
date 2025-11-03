import AppKit
import SwiftUI
import Combine

final class FloatingNoteWindow: NSObject, NSWindowDelegate {
    private let toDoManager: ToDoManager
    private var panel: NSPanel?
    private var hostingController: NSHostingController<FloatingNoteView>?
    private var cancellables: Set<AnyCancellable> = []
    private let viewModel: FloatingNoteViewModel
    private let pinDefaultsKey = "FloatingNoteWindowPinned"
    private let baseCollectionBehavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]

    init(toDoManager: ToDoManager) {
        self.toDoManager = toDoManager
        let storedPin = UserDefaults.standard.object(forKey: pinDefaultsKey) as? Bool ?? false
        self.viewModel = FloatingNoteViewModel(isPinned: storedPin)
        super.init()

        viewModel.$isPinned
            .removeDuplicates()
            .sink { [weak self] pinned in
                self?.storePinnedState(pinned)
                self?.updateWindowLevel(pinned)
            }
            .store(in: &cancellables)
    }

    func show() {
        if panel == nil {
            createWindow()
        }
        updateRootView()
        updateWindowLevel(viewModel.isPinned)
        guard let panel else { return }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func createWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.styleMask.remove(.miniaturizable)
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.collectionBehavior = baseCollectionBehavior
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.setFrameAutosaveName("DayDrainFloatingNoteWindow")
        panel.contentMinSize = NSSize(width: 360, height: 360)
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.isHidden = true

        let hosting = NSHostingController(
            rootView: FloatingNoteView(
                manager: toDoManager,
                viewModel: viewModel,
                onClose: { [weak panel] in
                    panel?.performClose(nil)
                }
            )
        )
        hosting.view.wantsLayer = true
        hosting.view.layer?.cornerRadius = 18
        hosting.view.layer?.masksToBounds = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor

        panel.contentViewController = hosting
        updateWindowLevel(viewModel.isPinned, on: panel)

        self.panel = panel
        self.hostingController = hosting
    }

    private func updateRootView() {
        hostingController?.rootView = FloatingNoteView(
            manager: toDoManager,
            viewModel: viewModel,
            onClose: { [weak self] in
                self?.panel?.performClose(nil)
            }
        )
    }

    private func storePinnedState(_ pinned: Bool) {
        UserDefaults.standard.set(pinned, forKey: pinDefaultsKey)
    }

    private func updateWindowLevel(_ pinned: Bool, on panel: NSPanel? = nil) {
        guard let target = panel ?? self.panel else { return }
        target.level = pinned ? .floating : .normal
        target.hidesOnDeactivate = !pinned
        target.collectionBehavior = pinned ? baseCollectionBehavior.union([.ignoresCycle]) : baseCollectionBehavior

        if pinned {
            target.orderFrontRegardless()
        }
    }

}
