import SwiftUI

@main
struct DayDrainApp: App {
    @StateObject private var dayManager: DayManager
    @StateObject private var toDoManager: ToDoManager
    private let menuBarController: MenuBarController

    init() {
        let manager = DayManager()
        let todo = ToDoManager()
        _dayManager = StateObject(wrappedValue: manager)
        _toDoManager = StateObject(wrappedValue: todo)
        self.menuBarController = MenuBarController(dayManager: manager, toDoManager: todo)
    }

    var body: some Scene {
        Settings {
            SettingsView(dayManager: dayManager)
        }
    }
}
