import MillisalaryCore
import SwiftUI

/// How the dial's ring is cut: one segment per unit of the period (the
/// working day's hours, the paid weekdays, the months), a label for each,
/// and the one under way, which is shown brighter
struct DialScale: Equatable {
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

    init(_ period: Period, _ workday: WorkdayState, _ settings: MillisalaryCore.Settings, at now: Date, model: EarningsModel = EarningsModel()) {
        var calendar = model.calendar
        calendar.locale = .app
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
            // "Jan", "січ": one letter repeats ("J" three times, "Л" for
            // лютий, липень and листопад). Without Ukrainian's abbreviation
            // dots, as on a calendar
            labels = calendar.shortStandaloneMonthSymbols.map { $0.replacing(".", with: "") }
            current = calendar.component(.month, from: now) - 1
        }
        unitsPerTotal = perTotal ?? units
    }
}

/// The ring fills with the period's progress around the face and the amount
/// earned so far, its last two of four decimals smaller. The ring grows in
/// when it appears, and when the period changes it sweeps from the last
/// period's fill to the new one; the ticks in between apply directly
struct EarningsDial: View {
    let earned: Double
    let total: Double
    let currency: String
    let period: Period
    let scale: DialScale

    private var progress: Double {
        total > 0 ? min(1, max(0, earned / total)) : 0
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            // The ring leaves a band outside it for the labels
            let radius = side * 0.395
            let stroke = side * 0.032

            ZStack {
                DialTrack(units: scale.units, labels: scale.labels, current: scale.current, side: side)
                    .equatable()
                DialFill(progress: progress, period: period, scale: scale, lineWidth: stroke)
                    .frame(width: radius * 2, height: radius * 2)

                VStack(spacing: side * 0.02) {
                    DialFace(side: side * 0.16)
                        .equatable()
                    amount(side: side)
                    DialTotal(total: formatCurrency(total, currency: currency), caption: period.dialCaption, side: side)
                        .equatable()
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(formatCurrency(earned, currency: currency)) earned \(period.dialCaption), \(Int((progress * 100).rounded()))% of \(formatCurrency(total, currency: currency))"
        )
    }

    /// Sized to fit inside the ring, as the Electron app estimates it: about
    /// 0.58 em a glyph in 60% of the width. Pieces of text side by side on
    /// one baseline rather than one Text interpolating the others, which
    /// went through a localized string's lookup and formatting on every
    /// tick: this way a tick only lays out the piece that changed, mostly
    /// the last two digits
    private func amount(side: CGFloat) -> some View {
        let parts = formatCurrencyParts(earned, currency: currency, fractionDigits: 4)
        let big = String(parts.fraction.prefix(2))
        let small = String(parts.fraction.dropFirst(2))
        let glyphs = Double(parts.integer.count + 1 + big.count) + Double(small.count) * 0.6
            + Double(parts.symbol.count + 1) * 0.7
        let size = side * min(17, 60 / (glyphs * 0.58)) / 100

        let symbol = Text(verbatim: parts.symbol)
            .font(.system(size: size * 0.7, weight: .semibold))
            .foregroundStyle(Color.accentColor)

        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            if parts.symbolPosition == .prefix {
                symbol
            }
            Text(verbatim: parts.sign + parts.integer + parts.decimal + big)
            Text(verbatim: small)
                .font(.system(size: size * 0.62, weight: .semibold))
                .foregroundStyle(.secondary)
            if parts.symbolPosition == .suffix {
                Text(verbatim: " ")
                symbol
            }
        }
        .font(.system(size: size, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }
}

/// "of 1 500,00 $ today" under the amount. Its own view, so the tick that
/// changes only the amount doesn't resolve the text again
private struct DialTotal: View, Equatable {
    let total: String
    let caption: String
    let side: CGFloat

    var body: some View {
        Text("of \(total) \(caption)")
            .font(.system(size: side * 0.038))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: side * 0.62)
    }
}

/// The ring's track, cut into the period's units, and their labels in a
/// band outside it, the one under way bold. Redrawn only when the scale or
/// the size changes, not on the ticks
private struct DialTrack: View, Equatable {
    let units: Double
    let labels: [String]
    let current: Int?
    let side: CGFloat

    var body: some View {
        let radius = side * 0.395
        let stroke = side * 0.032
        let labelRadius = side * 0.453

        ZStack {
            DialSegments(units: units, fraction: 1, lineWidth: stroke)
                .stroke(.quaternary, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .frame(width: radius * 2, height: radius * 2)

            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                // The middle of the label's segment, clockwise from the top
                let angle = (Double(index) + min(1, units - Double(index)) / 2) / units * 2 * .pi
                Text(verbatim: label)
                    .font(.system(size: max(9, side * 0.029), weight: index == current ? .bold : .medium))
                    .foregroundStyle(index == current ? HierarchicalShapeStyle.primary : .secondary)
                    .monospacedDigit()
                    .fixedSize()
                    .position(x: side / 2 + labelRadius * sin(angle), y: side / 2 - labelRadius * cos(angle))
            }
        }
        .frame(width: side, height: side)
    }
}

/// The ring's fill. It grows in when it appears and sweeps when the period
/// changes (0.6 s, ease in and out); the ticks set it directly once a sweep
/// is over. Its own view, so setting what it shows after a tick only redraws
/// the fill, not the whole dial
private struct DialFill: View {
    let progress: Double
    let period: Period
    let scale: DialScale
    let lineWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownProgress = 0.0
    @State private var animatingUntil = Date.distantPast

    var body: some View {
        DialSegments(
            units: scale.units,
            from: scale.fillStart,
            fraction: (scale.fillStart + shownProgress * scale.unitsPerTotal) / scale.units,
            lineWidth: lineWidth
        )
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .onAppear(perform: grow)
        .onChange(of: period, grow)
        .onChange(of: progress) {
            if Date.now >= animatingUntil {
                shownProgress = progress
            }
        }
    }

    private func grow() {
        guard !reduceMotion else {
            shownProgress = progress
            return
        }
        // Ease in and out, which ends on the value: a spring's long tail
        // near an empty ring left a round cap's dot on screen for a second
        animatingUntil = Date.now.addingTimeInterval(0.7)
        withAnimation(.easeInOut(duration: 0.6)) {
            shownProgress = progress
        }
    }
}

/// The face in the middle of the dial, where the splash's face lands: hidden
/// until it has, and reporting where it is
private struct DialFace: View, Equatable {
    let side: CGFloat

    @Environment(SplashModel.self) private var splash

    var body: some View {
        MoneyFace()
            .frame(width: side, height: side)
            .background(WindowFrameReporter { splash.dialFaceFrame = $0 } measure: { splash.measureDialFace = $0 })
            .opacity(splash.hidesDialFace ? 0 : 1)
    }

    static func == (a: Self, b: Self) -> Bool {
        a.side == b.side
    }
}

/// The dial's ring cut into the period's units, from the top clockwise and
/// filled from `from` units to `fraction` of the way round (the last unit
/// can be a part of one). The fill animates as a fraction of the ring, not
/// in units, so a switch from This Year's twelve segments to This Month's
/// twenty-one sweeps from where the fill was. Round caps reach past an
/// arc's ends, so by default each gap leaves room for two of them besides
/// the 3° that show; the menu bar's ring, stroked with butt caps, gives its
/// own. Off the main actor, as `Shape` needs
nonisolated struct DialSegments: Shape {
    var units: Double
    var from = 0.0
    var fraction: Double
    var lineWidth: CGFloat
    /// The degrees between one segment's end and the next one's start
    var gap: Double?

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let cap = Double(lineWidth / 2 / radius) * 180 / .pi
        let gap = self.gap ?? 3 + 2 * cap
        let degreesPerUnit = 360 / units
        let filled = fraction * units

        var path = Path()
        for index in 0..<Int(units.rounded(.up)) {
            let unit = Double(index)
            let length = min(1, units - unit)
            guard filled > unit else { break }
            guard from < unit + length else { continue }
            let start = unit * degreesPerUnit + gap / 2
            let end = (unit + length) * degreesPerUnit - gap / 2
            guard end > start else { continue }
            // The unit's share of the fill, laid over the part of the
            // segment that's drawn, so the head moves at an even pace from
            // one end to the other. Placing it at the fill's own angle less
            // a cap held it at the start for the first third of a This Month
            // day, until the fill caught up with the gap and the cap
            let lower = start + (end - start) * min(1, max(0, (from - unit) / length))
            let upper = start + (end - start) * min(1, max(0, (filled - unit) / length))
            let radians = (lower - 90) * .pi / 180
            path.move(to: CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians)))
            path.addArc(center: center, radius: radius, startAngle: .degrees(lower - 90), endAngle: .degrees(upper - 90), clockwise: false)
        }
        return path
    }
}
