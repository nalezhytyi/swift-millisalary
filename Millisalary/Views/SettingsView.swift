import MillisalaryCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private extension UTType {
    /// A fact row dragged within Settings' At a Glance (declared in
    /// project.yml's Info.plist keys)
    static let dialFact = UTType(exportedAs: "com.nalezhytyi.millisalary.dial-fact")
}

/// The settings, laid out like a System Settings pane. Every edit applies at
/// once; the schedule's Start, End and hours a day keep each other in step
/// (Settings.setStartHour and friends)
struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(NotificationController.self) private var notifications
    @Environment(LoginItemController.self) private var loginItem
    @Environment(Analytics.self) private var analytics

    /// What the salary field shows, the stored salary between edits
    @State private var salaryText = ""
    @FocusState private var salaryFocused: Bool
    /// The row a dragged fact would land before
    @State private var dropTarget: DialFact?
    /// The fact being dragged; the drag itself carries nothing to read
    @State private var draggedFact: DialFact?

    static let currencies = ["UAH", "USD", "EUR", "PLN", "CZK", "RON"]
    private static let days = (1...31).map(Double.init)
    private static let hours = (1...24).map(Double.init)

    var body: some View {
        let settings = store.settings

        Form {
            Section {
                // A bordered field, as in the setup form, rather than the
                // Form's borderless inline one
                LabeledContent("Monthly salary") {
                    TextField("Monthly salary", text: $salaryText, prompt: Text(0, format: .number.precision(.fractionLength(2))))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 150)
                        .focused($salaryFocused)
                        .onSubmit(commitSalary)
                        .onChange(of: salaryFocused) { _, focused in
                            if !focused { commitSalary() }
                        }
                        // Leaving the pane or closing the window while typing
                        // commits too
                        .onDisappear(perform: commitSalary)
                        .onChange(of: settings.monthlySalary, initial: true) { _, salary in
                            salaryText = salary.formatted(.number)
                        }
                        .onChange(of: salaryText) { old, text in
                            filterSalary(old, text)
                        }
                }
                Picker("Salary currency", selection: binding(\.monthlySalaryCurrency)) {
                    ForEach(Self.withCurrent(Self.currencies, settings.monthlySalaryCurrency), id: \.self) {
                        Text($0)
                    }
                }
                Picker("Display currency", selection: binding(\.earningsCurrency)) {
                    ForEach(Self.withCurrent(Self.currencies, settings.earningsCurrency), id: \.self) {
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
                    numbers(Self.withCurrent(Self.days, settings.workingDays))
                }
                Picker("Working hours / day", selection: edit(settings.workingHoursPerDay) { $0.setWorkingHoursPerDay($1) }) {
                    numbers(Self.withCurrent(Self.hours, settings.workingHoursPerDay))
                }
                DatePicker(
                    "Start time",
                    selection: time(settings.startTime) { $0.setStartHour($1) },
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "End time",
                    selection: time(settings.endTime) { $0.setEndHour($1) },
                    displayedComponents: .hourAndMinute
                )
            } header: {
                Text("Schedule")
            } footer: {
                footer("Hours per day follow the Start and End times: changing one updates the other.")
            }

            Section {
                Picker("Day of month", selection: edit(Double(settings.payday)) { $0.setPayday($1) }) {
                    numbers(Self.withCurrent(Self.days, Double(settings.payday)))
                }
            } header: {
                Text("Payday")
            } footer: {
                footer("Day of the month your salary arrives. In shorter months the last day is used.")
            }

            Section {
                Toggle("Open at login", isOn: binding(\.launchAtLogin))
                    .toggleStyle(.switch)
            } header: {
                Text("General")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    footer("Opens in the menu bar when your Mac starts, without showing the window.")
                    if !LoginItemController.isManaged {
                        footer("This Debug build doesn't register itself: only a Release build does.")
                    } else if settings.launchAtLogin && loginItem.status == .requiresApproval {
                        footer("Allow Millisalary under Login Items in System Settings.")
                        Button("Open Login Items Settings…") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                }
            }

            Section {
                Toggle("End of the workday", isOn: binding(\.notifyEndOfDay))
                    .toggleStyle(.switch)
                Toggle("Payday", isOn: binding(\.notifyPayday))
                    .toggleStyle(.switch)
            } header: {
                Text("Notifications")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    footer("Sent while the app is running, including when only the menu bar item is showing.")
                    if notifications.authorization == .denied && (settings.notifyEndOfDay || settings.notifyPayday) {
                        footer("Notifications are turned off for Millisalary in System Settings.")
                        Button("Open Notification Settings…") {
                            notifications.openSystemSettings()
                        }
                    }
                }
            }

            Section {
                Toggle("Show in menu bar", isOn: binding(\.showInMenuBar))
                    .toggleStyle(.switch)
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
                DialFactsPreview()
                // The chosen facts first, in their order, then the rest
                ForEach(settings.dialFacts + DialFact.allCases.filter { !settings.dialFacts.contains($0) }, id: \.self) { fact in
                    dialFactRow(fact, chosen: settings.dialFacts)
                }
            } header: {
                Text("At a Glance")
            } footer: {
                footer("Up to four show under the dial on every period, in this order. Drag a checked row to move it.")
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
            update { $0[keyPath: keyPath] = value }
        }
    }

    /// Every edit goes through here, and each field it changed is reported
    private func update(_ edit: (inout MillisalaryCore.Settings) -> Void) {
        let before = store.settings
        store.update(edit)
        analytics.settingsChanged(from: before, to: store.settings)
    }

    /// The salary field takes only what a number can have, as a number
    /// field's formatter does: an edit that adds anything else (a minus, a
    /// letter) is undone with a beep, and "." or "," becomes the locale's
    /// decimal separator (salaryInput)
    private func filterSalary(_ old: String, _ text: String) {
        // The stored salary, shown again after a commit
        guard text != store.settings.monthlySalary.formatted(.number) else { return }
        if let replacement = salaryFieldText(after: old, text) {
            salaryText = replacement
        }
    }

    /// The salary field commits on Return or when focus leaves it, as a
    /// native number field does, and then shows the stored salary again:
    /// an amount the validator rejects or text that doesn't parse (a lone
    /// separator, nothing at all) goes back to it. A
    /// `TextField(value:format:)` kept showing a rejected amount, since
    /// the stored one it reads hadn't changed
    private func commitSalary() {
        // Passing through the field doesn't round the stored amount to the
        // digits shown
        guard salaryText != store.settings.monthlySalary.formatted(.number) else { return }
        if let salary = try? Double(salaryText, format: .number) {
            update { $0.monthlySalary = salary }
        }
        salaryText = store.settings.monthlySalary.formatted(.number)
    }

    /// A value that is changed through one of the coupled-field edits
    private func edit<Value>(_ value: Value, _ apply: @escaping (inout MillisalaryCore.Settings, Value) -> Void) -> Binding<Value> {
        Binding {
            value
        } set: { newValue in
            update { apply(&$0, newValue) }
        }
    }

    private func time(_ value: TimeOfDay, _ apply: @escaping (inout MillisalaryCore.Settings, TimeOfDay) -> Void) -> Binding<Date> {
        Binding {
            value.pickerDate
        } set: { date in
            let time = TimeOfDay(pickerDate: date)
            update { apply(&$0, time) }
        }
    }

    // MARK: - At a Glance

    /// A fact's checkbox and what it says now; a checked one can be dragged,
    /// and dropping one on a row puts it before that row (on an unchecked
    /// one, after the checked). A drag and drop rather than `onMove`, which
    /// a grouped Form doesn't promise to offer, as the app's own `dialFact`
    /// type, visible to this process only; Move Up and Move Down in the
    /// context menu and as accessibility actions do the same without a drag
    @ViewBuilder
    private func dialFactRow(_ fact: DialFact, chosen: [DialFact]) -> some View {
        let isOn = chosen.contains(fact)
        let position = chosen.firstIndex(of: fact)
        let row = HStack(spacing: 8) {
            Toggle(fact.title, isOn: Binding {
                isOn
            } set: { on in
                update { $0.dialFacts = on ? $0.dialFacts + [fact] : $0.dialFacts.filter { $0 != fact } }
            })
            .toggleStyle(.checkbox)
            .disabled(!isOn && chosen.count >= DialFact.maximum)
            Spacer()
            DialFactSample(fact: fact)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .opacity(isOn ? 1 : 0)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if dropTarget == fact {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .offset(y: -5)
            }
        }
        .onDrop(of: [.dialFact], isTargeted: Binding {
            dropTarget == fact
        } set: { targeted in
            if targeted {
                dropTarget = fact
            } else if dropTarget == fact {
                dropTarget = nil
            }
        }) { _ in
            guard let draggedFact else { return false }
            moveFact(draggedFact, before: fact)
            return true
        }
        .contextMenu {
            if let position {
                Button("Move Up") { shiftFact(fact, by: -1) }
                    .disabled(position == 0)
                Button("Move Down") { shiftFact(fact, by: 1) }
                    .disabled(position == chosen.count - 1)
            }
        }
        .accessibilityActions {
            if let position {
                if position > 0 {
                    Button("Move Up") { shiftFact(fact, by: -1) }
                }
                if position < chosen.count - 1 {
                    Button("Move Down") { shiftFact(fact, by: 1) }
                }
            }
        }

        if isOn {
            row.onDrag {
                draggedFact = fact
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: UTType.dialFact.identifier, visibility: .ownProcess) { load in
                    load(Data(), nil)
                    return nil
                }
                return provider
            }
        } else {
            row
        }
    }

    private func shiftFact(_ fact: DialFact, by offset: Int) {
        update { settings in
            guard let index = settings.dialFacts.firstIndex(of: fact),
                  settings.dialFacts.indices.contains(index + offset)
            else { return }
            settings.dialFacts.swapAt(index, index + offset)
        }
    }

    private func moveFact(_ moved: DialFact, before target: DialFact) {
        dropTarget = nil
        draggedFact = nil
        guard moved != target, store.settings.dialFacts.contains(moved) else { return }
        update { settings in
            var facts = settings.dialFacts.filter { $0 != moved }
            if let index = facts.firstIndex(of: target) {
                facts.insert(moved, at: index)
            } else {
                facts.append(moved)
            }
            settings.dialFacts = facts
        }
    }

    // MARK: - Pieces

    /// The choices plus the current value when it isn't one of them (hours a
    /// day follow Start and End, so 09:00-17:20 makes 8.33)
    static func withCurrent<Value: Comparable>(_ choices: [Value], _ current: Value) -> [Value] {
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

/// The card under the dial as the chosen facts make it
private struct DialFactsPreview: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        let facts = store.settings.dialFacts
        if facts.isEmpty {
            Text("Nothing shows under the dial.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else {
            SettingsFigures { figures in
                DialFactCells(facts: facts, figures: figures)
            }
        }
    }
}

/// What a fact says, beside its checkbox
private struct DialFactSample: View {
    let fact: DialFact

    var body: some View {
        SettingsFigures { figures in
            figures.sample(fact)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// The figures for Settings' At a Glance, worked out when the pane shows,
/// when the settings or the rate change, and once a minute, so what changes
/// over the day (earned today, the days to payday) doesn't go stale. Not on
/// the window's 100 ms ticks: every row worked the earnings out ten times a
/// second, which took Settings from 1.5% of a core to 17%, and once a second
/// for the changing ones still cost 2 to 3% (Debug build, 2026-11-01).
/// Settings shows what a fact is; the dial is where it ticks
private struct SettingsFigures<Content: View>: View {
    @ViewBuilder let content: (DialFactFigures) -> Content

    @Environment(SettingsStore.self) private var store
    @Environment(ExchangeRateStore.self) private var rates

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let settings = store.settings
            let display = settings.amountDisplay(rates)
            content(DialFactFigures(settings, display, settings.earnings(at: Clock.now, display)))
        }
    }
}
