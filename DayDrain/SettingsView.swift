import SwiftUI

struct SettingsView: View {
    @ObservedObject var dayManager: DayManager

    var body: some View {
        TabView {
            GeneralSettingsView(dayManager: dayManager)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct GeneralSettingsView: View {
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
                Toggle("Show value next to the bar", isOn: $dayManager.showMenuValue)

                Picker("Value format", selection: $dayManager.displayMode) {
                    ForEach(DayDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(dayManagerDescription)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Overflow")) {
                Toggle("Keep overflow open between sessions", isOn: $dayManager.persistOverflowState)
                
                Text("Enable this if you use the overflow list frequently. When disabled, overflow is always collapsed when you open the panel.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var dayManagerDescription: String {
        if dayManager.isActive {
            return dayManager.displayText.isEmpty
                ? "DayDrain stays visible all day on selected weekdays and updates as your schedule progresses."
                : dayManager.displayText
        }

        return "Pick the weekdays you want. The menu bar item will stay available before, during, and after the hours you set."
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("DayDrain")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("A menu bar app that visualizes your workday progress")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 60)
            
            Divider()
                .padding(.horizontal, 60)
            
            Text("Made with ❤️ using SwiftUI")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
