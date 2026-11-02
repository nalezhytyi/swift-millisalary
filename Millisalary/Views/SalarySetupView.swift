import MillisalaryCore
import SwiftUI

/// The Earnings pane before there's a salary: the face in an empty ring and
/// what the earnings need to start, saved together by Start Earning. The
/// fields are a draft, so nothing is stored until then; the rest is in
/// Settings
struct SalarySetupView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(Analytics.self) private var analytics
    @Environment(\.openSettings) private var openSettings
    @Environment(SplashModel.self) private var splash

    @State private var draft = MillisalaryCore.Settings.defaults
    @State private var salaryText = ""
    @FocusState private var salaryFocused: Bool

    private static let ordinals: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = .app
        return formatter
    }()

    /// "10th" in English; in the other languages the number alone, which the
    /// translation inflects ("10-го числа"): their ordinals agree with a
    /// noun the formatter doesn't know ("10-ий"). The catalog's entry for
    /// "%@ of the month" says so
    private static func day(_ day: Int) -> String {
        Locale.appLanguage == .english ? ordinals.string(from: day as NSNumber) ?? "\(day)" : "\(day)"
    }

    /// "Everything else is in Settings.", the link's words in the accent
    /// colour. One sentence, since a translation inflects the link's words
    /// ("у налаштуваннях"): the catalog marks them as a markdown link, which
    /// becomes the colour here. The whole sentence is the button, so it
    /// takes keyboard focus and reads as one to VoiceOver, which a link
    /// inside a Text did neither
    private static var settingsHint: AttributedString {
        var text = AttributedString(localized: "Everything else is in [Settings](millisalary-settings:).")
        for range in text.runs.filter({ $0.link != nil }).map(\.range) {
            text[range].link = nil
            text[range].swiftUI.foregroundColor = .accentColor
        }
        return text
    }

    private var salary: Double? {
        guard let salary = try? Double(salaryText, format: .number), salary > 0 else { return nil }
        return salary
    }

    var body: some View {
        GeometryReader { proxy in
            form
                // The card at most 500 pt wide, as margins inside the Form
                // rather than a frame around it: the toolbar's band over a
                // scroll view is as wide as the scroll view, and an
                // inactive window drew it 500 pt wide over a wider pane
                .contentMargins(.horizontal, max(0, (proxy.size.width - 500) / 2), for: .scrollContent)
        }
        .defaultScrollAnchor(.center)
        .onAppear {
            draft = store.settings
            salaryFocused = true
        }
    }

    private var form: some View {
        Form {
            Section {
                LabeledContent("Monthly salary") {
                    HStack(spacing: 6) {
                        SalaryField(text: $salaryText, focus: $salaryFocused)
                            .onSubmit(start)
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
                    ForEach(Array(1...31).including(draft.payday), id: \.self) { day in
                        Text("\(Self.day(day)) of the month").tag(day)
                    }
                }
            } header: {
                header
            } footer: {
                footer
            }
        }
        .formStyle(.grouped)
    }

    private var header: some View {
        VStack(spacing: 0) {
            ZStack {
                // The dial's ring before there's anything to fill it: a
                // working day's eight hours as faint segments
                DialSegments(units: 8, fraction: 1, lineWidth: 8)
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
            Button {
                analytics.track("settings_opened", ["source": .string(ActionSource.setupHint.rawValue)])
                openSettings()
            } label: {
                Text(Self.settingsHint)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
    }

    private func currencyPicker(_ label: String, selection: Binding<String>) -> some View {
        Picker(label, selection: selection) {
            CurrencyOptions(current: selection.wrappedValue)
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
