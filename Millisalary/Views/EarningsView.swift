import MillisalaryCore
import SwiftUI

/// A period of the Earnings section: the dial, and under it today's, this
/// week's and this month's amounts (or, with no salary yet, a way to
/// Settings)
struct EarningsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(Navigation.self) private var navigation
    @Environment(ExchangeRateStore.self) private var rates
    @Environment(Ticker.self) private var ticker
    @Environment(Analytics.self) private var analytics

    var body: some View {
        let settings = store.settings
        let display = settings.amountDisplay(rates)
        let earnings = settings.earnings(at: ticker.now, display)
        let period = settings.selectedPeriod

        VStack(spacing: 0) {
            EarningsDial(
                earned: earnings[period].earned,
                total: earnings[period].total,
                currency: display.currency,
                period: period
            )
            .frame(minWidth: 176, maxWidth: 384, maxHeight: .infinity)
            .padding(.vertical, 16)

            if settings.monthlySalary > 0 {
                StatsRow(earnings: earnings, currency: display.currency)
            } else {
                SetupHint {
                    navigation.select(.settings, source: .setupHint, store: store, analytics: analytics)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: 448)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Nothing scrolls under the toolbar here, so it has no bar
        .toolbarBackground(.hidden, for: .windowToolbar)
    }
}

/// The ring fills with the period's progress around the face and the amount
/// earned so far, its last two of four decimals smaller. The ring grows in
/// when it appears and when the period changes; the ticks in between apply
/// directly
struct EarningsDial: View {
    let earned: Double
    let total: Double
    let currency: String
    let period: Period

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
            // The Electron app's SVG: a radius of 44 and a stroke of 6 in 100
            let ring = Circle().inset(by: side * 0.06)
            let stroke = side * 0.06

            ZStack {
                ring.stroke(.quaternary, lineWidth: stroke)
                ring.trim(from: 0, to: shownProgress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // A round cap would show a dot at 0
                    .opacity(shownProgress > 0 ? 1 : 0)

                VStack(spacing: side * 0.02) {
                    MoneyFace()
                        .frame(width: side * 0.16, height: side * 0.16)
                        // Where the splash's face lands, hidden until it has
                        .background(WindowFrameReporter { splash.dialFaceFrame = $0 })
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
        .onChange(of: period, growRing)
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

private struct StatsRow: View {
    let earnings: EarningsSnapshot
    let currency: String

    var body: some View {
        let stats: [(label: String, amount: Double)] = [
            ("Today", earnings.day.earned),
            ("This week", earnings.week.earned),
            ("This month", earnings.month.earned),
        ]

        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Divider()
                }
                VStack(spacing: 2) {
                    Text(formatCurrency(stat.amount, currency: currency))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                    Text(stat.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SetupHint: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Add your monthly salary to start tracking earnings.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings", action: openSettings)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }
}
