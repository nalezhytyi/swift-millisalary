import MillisalaryCore
import SwiftUI

/// The Earnings pane before there's a salary: the face in an empty ring and
/// what the earnings need to start, saved together by Start Earning. The
/// fields are a draft, so nothing is stored until then; the rest is in
/// Settings
struct SalarySetupView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(Navigation.self) private var navigation
    @Environment(Analytics.self) private var analytics
    @Environment(SplashModel.self) private var splash

    @State private var draft = MillisalaryCore.Settings.defaults
    @State private var salaryText = ""
    @FocusState private var salaryFocused: Bool

    private static let ordinals: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private var salary: Double? {
        guard let salary = try? Double(salaryText, format: .number), salary > 0 else { return nil }
        return salary
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Monthly salary") {
                    HStack(spacing: 6) {
                        TextField("Monthly salary", text: $salaryText, prompt: Text(0, format: .number.precision(.fractionLength(2))))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 150)
                            .focused($salaryFocused)
                            .onSubmit(start)
                            .onChange(of: salaryText) { old, text in
                                if let replacement = salaryFieldText(after: old, text) {
                                    salaryText = replacement
                                }
                            }
                        currencyPicker("Salary currency", selection: $draft.monthlySalaryCurrency)
                    }
                }
                LabeledContent("Show amounts in") {
                    currencyPicker("Show amounts in", selection: $draft.earningsCurrency)
                }
                LabeledContent("Working hours, Mon–Fri") {
                    HStack(spacing: 6) {
                        DatePicker(
                            "Start time",
                            selection: time(draft.startTime) { $0.setStartHour($1) },
                            displayedComponents: .hourAndMinute
                        )
                        Text("–")
                            .foregroundStyle(.secondary)
                        DatePicker(
                            "End time",
                            selection: time(draft.endTime) { $0.setEndHour($1) },
                            displayedComponents: .hourAndMinute
                        )
                    }
                    .labelsHidden()
                }
                Picker("Payday", selection: Binding { draft.payday } set: { draft.setPayday(Double($0)) }) {
                    ForEach(SettingsView.withCurrent(Array(1...31), draft.payday), id: \.self) { day in
                        Text("\(Self.ordinals.string(from: day as NSNumber) ?? "\(day)") of the month").tag(day)
                    }
                }
            } header: {
                header
            } footer: {
                footer
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity)
        .defaultScrollAnchor(.center)
        .onAppear {
            draft = store.settings
            salaryFocused = true
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            ZStack {
                // The dial's ring before there's anything to fill it: a
                // working day's eight hours as faint segments
                DialSegments(units: 8, filled: 8, lineWidth: 8)
                    .stroke(.quaternary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .padding(6)
                    .accessibilityHidden(true)
                MoneyFace()
                    .frame(width: 80, height: 80)
                    // Where the splash's face lands, as on the dial
                    .background(WindowFrameReporter { splash.dialFaceFrame = $0 } measure: { splash.measureDialFace = $0 })
                    .opacity(splash.hidesDialFace ? 0 : 1)
            }
            .frame(width: 168, height: 168)
            Text("See your salary grow, second by second")
                .font(.title.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.top, 22)
            Text("Tell Millisalary what you earn a month. It spreads the amount over your working hours and counts it up live, here and in the menu bar.")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button("Start Earning", action: start)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(salary == nil)
            HStack(spacing: 0) {
                Text("Everything else is in ")
                    .foregroundStyle(.secondary)
                Button("Settings") {
                    navigation.select(.settings, source: .setupHint, store: store, analytics: analytics)
                }
                .buttonStyle(.link)
                Text(".")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
    }

    private func currencyPicker(_ label: String, selection: Binding<String>) -> some View {
        Picker(label, selection: selection) {
            ForEach(SettingsView.withCurrent(SettingsView.currencies, selection.wrappedValue), id: \.self) {
                Text($0)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    /// The draft's Start and End keep hours a day in step, as in Settings
    private func time(_ value: TimeOfDay, _ apply: @escaping (inout MillisalaryCore.Settings, TimeOfDay) -> Void) -> Binding<Date> {
        Binding {
            value.pickerDate
        } set: { date in
            apply(&draft, TimeOfDay(pickerDate: date))
        }
    }

    /// Saves the draft; with a salary stored the pane turns into the dial
    private func start() {
        guard let salary else {
            NSSound.beep()
            return
        }
        let before = store.settings
        store.update { settings in
            settings.monthlySalary = salary
            settings.monthlySalaryCurrency = draft.monthlySalaryCurrency
            settings.earningsCurrency = draft.earningsCurrency
            settings.startHour = draft.startHour
            settings.endHour = draft.endHour
            settings.workingHoursPerDay = draft.workingHoursPerDay
            settings.payday = draft.payday
        }
        analytics.settingsChanged(from: before, to: store.settings)
    }
}
