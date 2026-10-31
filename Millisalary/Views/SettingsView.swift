import MillisalaryCore
import SwiftUI

/// The settings, laid out like a System Settings pane. Every edit applies at
/// once; the schedule's Start, End and hours a day keep each other in step
/// (Settings.setStartHour and friends). Only what works so far is here:
/// Open at login and the notifications come with their features
struct SettingsView: View {
    @Environment(SettingsStore.self) private var store

    private static let currencies = ["UAH", "USD", "EUR", "PLN", "CZK", "RON"]
    private static let days = (1...31).map(Double.init)
    private static let hours = (1...24).map(Double.init)

    var body: some View {
        let settings = store.settings

        Form {
            Section {
                TextField("Monthly salary", value: binding(\.monthlySalary), format: .number)
                    .multilineTextAlignment(.trailing)
                Picker("Salary currency", selection: binding(\.monthlySalaryCurrency)) {
                    ForEach(withCurrent(Self.currencies, settings.monthlySalaryCurrency), id: \.self) {
                        Text($0)
                    }
                }
                Picker("Display currency", selection: binding(\.earningsCurrency)) {
                    ForEach(withCurrent(Self.currencies, settings.earningsCurrency), id: \.self) {
                        Text($0)
                    }
                }
            } header: {
                Text("Salary")
            } footer: {
                footer("Your monthly salary is spread over your working days and hours. Earnings are shown in the display currency.")
            }

            Section {
                Picker("Working days / month", selection: edit(settings.workingDays) { $0.setWorkingDays($1) }) {
                    numbers(withCurrent(Self.days, settings.workingDays))
                }
                Picker("Working hours / day", selection: edit(settings.workingHoursPerDay) { $0.setWorkingHoursPerDay($1) }) {
                    numbers(withCurrent(Self.hours, settings.workingHoursPerDay))
                }
                DatePicker(
                    "Start time",
                    selection: time(start(settings)) { $0.setStartHour($1) },
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "End time",
                    selection: time(end(settings)) { $0.setEndHour($1) },
                    displayedComponents: .hourAndMinute
                )
            } header: {
                Text("Schedule")
            } footer: {
                footer("Hours per day follow the Start and End times: changing one updates the other.")
            }

            Section {
                Picker("Day of month", selection: edit(Double(settings.payday)) { $0.setPayday($1) }) {
                    numbers(withCurrent(Self.days, Double(settings.payday)))
                }
            } header: {
                Text("Payday")
            } footer: {
                footer("Day of the month your salary arrives. In shorter months the last day is used.")
            }

            Section {
                Toggle("Show in menu bar", isOn: binding(\.showInMenuBar))
                Picker("Amount", selection: binding(\.menuBarAmount)) {
                    Text("Today").tag(MenuBarAmount.day)
                    Text("Selected period").tag(MenuBarAmount.selected)
                }
                .disabled(!settings.showInMenuBar)
            } header: {
                Text("Menu bar")
            } footer: {
                footer("Shows your earnings next to an icon in the macOS menu bar, even when the window is closed.")
            }

            Section {
                Picker("Appearance", selection: binding(\.theme)) {
                    Text("System").tag(Theme.system)
                    Text("Light").tag(Theme.light)
                    Text("Dark").tag(Theme.dark)
                }
            } footer: {
                footer("System follows the macOS appearance.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Bindings

    private func binding<Value>(_ keyPath: WritableKeyPath<MillisalaryCore.Settings, Value>) -> Binding<Value> {
        Binding {
            store.settings[keyPath: keyPath]
        } set: { value in
            store.update { $0[keyPath: keyPath] = value }
        }
    }

    /// A value that is changed through one of the coupled-field edits
    private func edit<Value>(_ value: Value, _ apply: @escaping (inout MillisalaryCore.Settings, Value) -> Void) -> Binding<Value> {
        Binding {
            value
        } set: { newValue in
            store.update { apply(&$0, newValue) }
        }
    }

    // DatePicker edits a Date: a fixed day carries the time, one without a
    // DST change so every time of day exists on it
    private static let timeDay = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))

    private func time(_ value: TimeOfDay, _ apply: @escaping (inout MillisalaryCore.Settings, TimeOfDay) -> Void) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: value.hour, minute: value.minute, second: 0, of: Self.timeDay)!
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            let time = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            store.update { apply(&$0, time) }
        }
    }

    /// The times the earnings use when one is cleared: 09:00, and Start plus
    /// hours a day
    private func start(_ settings: MillisalaryCore.Settings) -> TimeOfDay {
        TimeOfDay(parsing: settings.startHour) ?? TimeOfDay(hour: 9, minute: 0)
    }

    private func end(_ settings: MillisalaryCore.Settings) -> TimeOfDay {
        TimeOfDay(parsing: settings.endHour)
            ?? endHour(from: start(settings), workingHoursPerDay: settings.workingHoursPerDay)
    }

    // MARK: - Pieces

    /// The choices plus the current value when it isn't one of them (hours a
    /// day follow Start and End, so 09:00-17:20 makes 8.33)
    private func withCurrent<Value: Comparable>(_ choices: [Value], _ current: Value) -> [Value] {
        choices.contains(current) ? choices : (choices + [current]).sorted()
    }

    private func numbers(_ values: [Double]) -> some View {
        ForEach(values, id: \.self) { value in
            Text(value, format: .number).tag(value)
        }
    }

    private func footer(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }
}
