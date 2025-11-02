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
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.setFrameAutosaveName("DayDrainFloatingNoteWindow")
        panel.contentMinSize = NSSize(width: 360, height: 360)

        let hosting = NSHostingController(rootView: FloatingNoteView(manager: toDoManager, viewModel: viewModel))
        hosting.view.wantsLayer = true
        hosting.view.layer?.cornerRadius = 18
        hosting.view.layer?.masksToBounds = true

        panel.contentViewController = hosting
        updateWindowLevel(viewModel.isPinned, on: panel)

        self.panel = panel
        self.hostingController = hosting
    }

    private func updateRootView() {
        hostingController?.rootView = FloatingNoteView(manager: toDoManager, viewModel: viewModel)
    }

    private func storePinnedState(_ pinned: Bool) {
        UserDefaults.standard.set(pinned, forKey: pinDefaultsKey)
    }

    private func updateWindowLevel(_ pinned: Bool, on panel: NSPanel? = nil) {
        let target = panel ?? self.panel
        target?.level = pinned ? .floating : .normal
    }

}
