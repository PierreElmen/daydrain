import SwiftUI

struct SettingsView: View {
    @ObservedObject var dayManager: DayManager

    var body: some View {
        Form {
            Section(header: Text("Workdays")) {
                Text("Select the days when DayDrain should appear in the menu bar.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                WeekdayGrid(selectedWeekdays: $dayManager.selectedWeekdays)
            }

            Section(header: Text("Working hours")) {
                DatePicker("Start", selection: $dayManager.startTime, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $dayManager.endTime, displayedComponents: .hourAndMinute)
            }

            Section(header: Text("Display")) {
                Picker("Tooltip", selection: $dayManager.displayMode) {
                    ForEach(DayDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(dayManagerDescription)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var dayManagerDescription: String {
        if dayManager.isActive {
            return dayManager.displayText
        } else {
            return "DayDrain will appear only during the configured work hours on selected days."
        }
    }
}

private struct WeekdayGrid: View {
    @Binding var selectedWeekdays: Set<Weekday>
    private let columns: [GridItem] = Array(repeating: .init(.flexible()), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Weekday.allCases) { weekday in
                Toggle(isOn: binding(for: weekday)) {
                    Text(weekday.localizedName)
                        .frame(maxWidth: .infinity)
                }
                .toggleStyle(.button)
            }
        }
    }

    private func binding(for weekday: Weekday) -> Binding<Bool> {
        Binding(
            get: { selectedWeekdays.contains(weekday) },
            set: { isOn in
                if isOn {
                    selectedWeekdays.insert(weekday)
                } else {
                    selectedWeekdays.remove(weekday)
                }
            }
        )
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(dayManager: DayManager())
            .frame(width: 360)
    }
}
