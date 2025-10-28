import SwiftUI

@main
struct DayDrainApp: App {
    @StateObject private var dayManager: DayManager
    private let menuBarController: MenuBarController

    init() {
        let manager = DayManager()
        _dayManager = StateObject(wrappedValue: manager)
        self.menuBarController = MenuBarController(dayManager: manager)
    }

    var body: some Scene {
        Settings {
            SettingsView(dayManager: dayManager)
        }
        .settingsStyle(.toolbar)
    }
}
