import MillisalaryCore
import SwiftUI

/// A period of the Earnings section: the dial, a line on where the workday
/// stands, and the rates and the next payday under it, or, with no salary
/// yet, the form that sets one up
struct EarningsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(ExchangeRateStore.self) private var rates
    @Environment(Ticker.self) private var ticker

    var body: some View {
        let settings = store.settings
        let display = settings.amountDisplay(rates)
        let now = ticker.now
        let earnings = settings.earnings(at: now, display)
        let period = settings.selectedPeriod
        let workday = WorkdayState(settings, at: now)

        Group {
            if settings.monthlySalary > 0 {
                VStack(spacing: 0) {
                    // The dial and its line stay together, centred in the
                    // height the facts leave
                    VStack(spacing: 14) {
                        EarningsDial(
                            earned: earnings[period].earned,
                            total: earnings[period].total,
                            currency: display.currency,
                            period: period,
                            scale: DialScale(period, workday, settings, at: now)
                        )
                        // A new dial for each period, so its ring grows in
                        // from empty: animating from the last period's fill
                        // ran it backwards over segments that weren't its own
                        .id(period)
                        .frame(minWidth: 176, maxWidth: 384)
                        Text(workday.status(for: period, at: now))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 16)
                    .frame(maxHeight: .infinity)

                    if !settings.dialFacts.isEmpty {
                        FactsRow(facts: settings.dialFacts, figures: DialFactFigures(settings, display, earnings))
                    }
                }
                .padding(.horizontal, 20)
                // The facts' Form adds its own 20 pt around the card
                .padding(.bottom, 4)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Nothing scrolls under the toolbar here, so it has no bar;
                // the setup form does scroll, and keeps it
                .toolbarBackground(.hidden, for: .windowToolbar)
            } else {
                SalarySetupView()
            }
        }
    }
}

/// Today's working window and whether it pays, as the earnings model sees
/// them, and when the next one starts
struct WorkdayState {
    let window: WorkingWindow
    let isScheduled: Bool
    let isEarning: Bool
    /// The next paid window's start after today's, and how many days on
    let next: (start: Date, days: Int)?

    private static let english = Locale(identifier: "en_US")
    private struct NextKey: Equatable {
        let today: Date
        let workday: WorkdaySettings
    }
    private static let nextMemo = DayMemo<NextKey, (start: Date, days: Int)?>()

    init(_ settings: MillisalaryCore.Settings, at now: Date) {
        let model = EarningsModel()
        let workday = settings.workday
        window = model.workingWindow(on: now, workday)
        isScheduled = model.isScheduledDay(now, workingDays: settings.workingDays)
        isEarning = isScheduled && window.start <= now && now < window.end

        let today = model.calendar.startOfDay(for: now)
        next = Self.nextMemo.value(for: NextKey(today: today, workday: workday)) {
            (1...31).lazy.compactMap { days -> (start: Date, days: Int)? in
                let day = model.calendar.date(byAdding: .day, value: days, to: today)!
                guard model.isScheduledDay(day, workingDays: workday.workingDays) else { return nil }
                return (model.workingWindow(on: day, workday).start, days)
            }.first
        }
    }

    /// "3 h 30 min left today, until 17:00", or when earning starts again
    func status(for period: Period, at now: Date) -> String {
        let time = Date.FormatStyle.dateTime.hour().minute()
        if isEarning {
            let left = Self.duration(window.end.timeIntervalSince(now))
            if period == .week {
                let weekday = (EarningsModel().calendar.component(.weekday, from: now) + 5) % 7 + 1
                return "Day \(weekday) of 5, \(left) left today"
            }
            return "\(left) left today, until \(window.end.formatted(time))"
        }
        if isScheduled && now < window.start {
            return "Earning starts today at \(window.start.formatted(time))"
        }
        let opening = isScheduled ? "Done for today." : "Day off."
        guard let next else { return opening }
        let when = switch next.days {
        case 1: "tomorrow"
        case ..<7: next.start.formatted(.dateTime.weekday(.wide).locale(Self.english))
        default: "on " + next.start.formatted(.dateTime.day().month(.wide).locale(Self.english))
        }
        return "\(opening) Earning resumes \(when) at \(next.start.formatted(time))"
    }

    /// "3 h 30 min", rounded up to the minute as a countdown is
    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        switch (minutes / 60, minutes % 60) {
        case (0, let minutes): return "\(minutes) min"
        case (let hours, 0): return "\(hours) h"
        case (let hours, let minutes): return "\(hours) h \(minutes) min"
        }
    }
}

/// One value kept until its key changes: what the Earnings pane works out
/// once a day (the next paid day, the month's paid days, each a loop of
/// calendar arithmetic) rather than on every 100 ms tick. The keys hold the
/// day or month as the model's calendar starts it, so a change of time zone
/// makes a new one
final class DayMemo<Key: Equatable, Value> {
    private var key: Key?
    private var value: Value?

    func value(for key: Key, _ make: () -> Value) -> Value {
        if let value, self.key == key {
            return value
        }
        let made = make()
        self.key = key
        value = made
        return made
    }
}

/// How the dial's ring is cut: one segment per unit of the period (the
/// working day's hours, the paid weekdays, the months), a label for each,
/// and the one under way, which is shown brighter
struct DialScale {
    var units: Double
    /// How many units the period's total is worth: the fill is the progress
    /// times this. The units, except for a month with fewer paid days than
    /// the working days its salary is split over, and a day, whose clock
    /// hours can take in part of an hour before the start or after the end
    var unitsPerTotal: Double
    /// Where the fill begins, in units: the minutes of a clock hour before a
    /// workday that starts at 09:30, on This Hour's five-minute segments and
    /// on Today's hours
    var fillStart = 0.0
    var labels: [String]
    var current: Int?

    private struct PaidDaysKey: Equatable {
        let month: Date
        let workingDays: Double
    }
    private static let paidDaysMemo = DayMemo<PaidDaysKey, [Date]>()

    init(_ period: Period, _ workday: WorkdayState, _ settings: MillisalaryCore.Settings, at now: Date) {
        let model = EarningsModel()
        var calendar = model.calendar
        calendar.locale = Locale(identifier: "en_US")
        let window = workday.window
        var perTotal: Double?
        switch period {
        case .hour:
            // The clock's minutes; the hour's pay starts when the workday
            // does, if that's within it
            let hour = calendar.dateInterval(of: .hour, for: now)!.start
            units = 12
            fillStart = min(12, max(0, window.start.timeIntervalSince(hour) / 300))
            labels = stride(from: 0, to: 60, by: 5).map { String(format: "%02ld", $0) }
            current = workday.isEarning ? calendar.component(.minute, from: now) / 5 : nil
        case .day:
            // Clock hours, from the one the workday starts in to the one it
            // ends in: a 09:30 start fills "9" from its middle
            let firstHour = calendar.dateInterval(of: .hour, for: window.start)!.start
            let hours = max(1.0 / 60, window.end.timeIntervalSince(window.start) / 3600)
            fillStart = window.start.timeIntervalSince(firstHour) / 3600
            units = max(1, (fillStart + hours).rounded(.up))
            let first = calendar.component(.hour, from: firstHour)
            labels = (0..<Int(units)).map { String((first + $0) % 24) }
            current = workday.isEarning ? Int(now.timeIntervalSince(firstHour) / 3600) : nil
            perTotal = hours
        case .week:
            units = 5
            labels = Array(calendar.shortWeekdaySymbols[1...5])
            // Only a paid weekday: one past the working days a month isn't
            let weekday = (calendar.component(.weekday, from: now) + 5) % 7
            current = weekday < 5 && workday.isScheduled ? weekday : nil
        case .month:
            // The month's paid days, dated: its weekdays until the working
            // days a month run out (the model's isScheduledDay). With fewer
            // weekdays than working days the salary still counts them all,
            // so the last segments' worth is never reached and the ring
            // fills by days
            let start = calendar.dateInterval(of: .month, for: now)!.start
            let paid = Self.paidDaysMemo.value(for: PaidDaysKey(month: start, workingDays: settings.workingDays)) {
                calendar.range(of: .day, in: .month, for: now)!
                    .map { calendar.date(byAdding: .day, value: $0 - 1, to: start)! }
                    .filter { model.isScheduledDay($0, workingDays: settings.workingDays) }
            }
            units = max(1, min(Double(paid.count), settings.workingDays))
            labels = paid.prefix(Int(units.rounded(.up))).map { String(calendar.component(.day, from: $0)) }
            current = paid.firstIndex { calendar.isDate($0, inSameDayAs: now) }
            perTotal = max(1, settings.workingDays)
        case .year:
            units = 12
            labels = calendar.veryShortMonthSymbols
            current = calendar.component(.month, from: now) - 1
        }
        unitsPerTotal = perTotal ?? units
    }
}

/// The ring fills with the period's progress around the face and the amount
/// earned so far, its last two of four decimals smaller. The ring grows in
/// from empty when it appears (each period gets a dial of its own); the
/// ticks after that apply directly
struct EarningsDial: View {
    let earned: Double
    let total: Double
    let currency: String
    let period: Period
    let scale: DialScale

    @Environment(SplashModel.self) private var splash
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownProgress = 0.0
    @State private var animatingUntil = Date.distantPast

    private var progress: Double {
        total > 0 ? min(1, max(0, earned / total)) : 0
    }

    private var caption: String {
        switch period {
        case .hour: "per hour"
        case .day: "today"
        case .week: "this week"
        case .month: "this month"
        case .year: "this year"
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            // The ring leaves a band outside it for the labels
            let radius = side * 0.395
            let stroke = side * 0.032
            let labelRadius = side * 0.453

            ZStack {
                DialSegments(units: scale.units, filled: scale.units, lineWidth: stroke)
                    .stroke(.quaternary, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .frame(width: radius * 2, height: radius * 2)
                DialSegments(
                    units: scale.units,
                    from: scale.fillStart,
                    filled: scale.fillStart + shownProgress * scale.unitsPerTotal,
                    lineWidth: stroke
                )
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .frame(width: radius * 2, height: radius * 2)

                ForEach(Array(scale.labels.enumerated()), id: \.offset) { index, label in
                    // The middle of the label's segment, clockwise from the top
                    let angle = (Double(index) + min(1, scale.units - Double(index)) / 2) / scale.units * 2 * .pi
                    Text(label)
                        .font(.system(size: max(9, side * 0.029), weight: index == scale.current ? .bold : .medium))
                        .foregroundStyle(index == scale.current ? HierarchicalShapeStyle.primary : .secondary)
                        .monospacedDigit()
                        .fixedSize()
                        .position(x: side / 2 + labelRadius * sin(angle), y: side / 2 - labelRadius * cos(angle))
                }

                VStack(spacing: side * 0.02) {
                    MoneyFace()
                        .frame(width: side * 0.16, height: side * 0.16)
                        // Where the splash's face lands, hidden until it has
                        .background(WindowFrameReporter { splash.dialFaceFrame = $0 } measure: { splash.measureDialFace = $0 })
                        .opacity(splash.hidesDialFace ? 0 : 1)
                    amount(side: side)
                    Text("of \(formatCurrency(total, currency: currency)) \(caption)")
                        .font(.system(size: side * 0.038))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: side * 0.62)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(formatCurrency(earned, currency: currency)) earned \(caption), "
                + "\(Int((progress * 100).rounded()))% of \(formatCurrency(total, currency: currency))"
        )
        .onAppear(perform: growRing)
        .onChange(of: progress) {
            if Date.now >= animatingUntil {
                shownProgress = progress
            }
        }
    }

    private func growRing() {
        guard !reduceMotion else {
            shownProgress = progress
            return
        }
        animatingUntil = Date.now.addingTimeInterval(0.8)
        withAnimation(.smooth(duration: 0.7)) {
            shownProgress = progress
        }
    }

    /// Sized to fit inside the ring, as the Electron app estimates it: about
    /// 0.58 em a glyph in 60% of the width
    private func amount(side: CGFloat) -> some View {
        let parts = formatCurrencyParts(earned, currency: currency, fractionDigits: 4)
        let big = String(parts.fraction.prefix(2))
        let small = String(parts.fraction.dropFirst(2))
        let glyphs = Double(parts.integer.count + 1 + big.count) + Double(small.count) * 0.6
            + Double(parts.symbol.count + 1) * 0.7
        let size = side * min(17, 60 / (glyphs * 0.58)) / 100

        let number = Text(parts.sign + parts.integer + parts.decimal + big)
        let tail = Text(small).font(.system(size: size * 0.62, weight: .semibold)).foregroundStyle(.secondary)
        let symbol = Text(parts.symbol).font(.system(size: size * 0.7, weight: .semibold)).foregroundStyle(Color.accentColor)
        let text = parts.symbolPosition == .prefix
            ? Text("\(symbol)\(number)\(tail)")
            : Text("\(number)\(tail) \(symbol)")

        return text
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }
}

/// The dial's ring cut into the period's units, from the top clockwise and
/// filled from `from` to `filled` units (the last unit can be a part of
/// one). Round caps reach past an arc's ends, so each gap leaves room for
/// two of them besides the 3° that show, and a fill's ends are pulled in by
/// a cap. Off the main actor, as `Shape` needs
nonisolated struct DialSegments: Shape {
    var units: Double
    var from = 0.0
    var filled: Double
    var lineWidth: CGFloat

    var animatableData: Double {
        get { filled }
        set { filled = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let cap = Double(lineWidth / 2 / radius) * 180 / .pi
        let gap = 3 + 2 * cap
        let degreesPerUnit = 360 / units
        let fillFrom = from * degreesPerUnit
        let fillTo = filled * degreesPerUnit

        var path = Path()
        for index in 0..<Int(units.rounded(.up)) {
            let unit = Double(index)
            let segmentStart = unit * degreesPerUnit
            let segmentEnd = (unit + min(1, units - unit)) * degreesPerUnit
            guard fillTo > segmentStart else { break }
            guard fillFrom < segmentEnd else { continue }
            let start = segmentStart + gap / 2
            let end = segmentEnd - gap / 2
            guard end > start else { continue }
            let lower = min(end, max(start, fillFrom + cap))
            let upper = min(end, max(lower, fillTo - cap))
            let radians = (lower - 90) * .pi / 180
            path.move(to: CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians)))
            path.addArc(center: center, radius: radius, startAngle: .degrees(lower - 90), endAngle: .degrees(upper - 90), clockwise: false)
        }
        return path
    }
}

/// The facts chosen in Settings, in a row under the dial, the same for
/// every period
private struct FactsRow: View {
    let facts: [DialFact]
    let figures: DialFactFigures

    var body: some View {
        // A grouped Form's card, as Breakdown's rates are in; the Form is as
        // tall as its card and draws no background of its own here. Its
        // 20 pt margin stays: contentMargins (any placement) and
        // listRowInsets don't change it on macOS 27 (measured on captures,
        // 2026-11-01), so the pane allows for it
        Form {
            Section {
                DialFactCells(facts: facts, figures: figures)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}
