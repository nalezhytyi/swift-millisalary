import Foundation
import Testing
@testable import MillisalaryCore

// The Swift port against the Electron app's TypeScript: Fixtures/parity.json
// holds what the TypeScript returned for the same inputs, written by
// scripts/parity/generate-fixtures.sh. Money is compared exactly: the port
// does the same floating-point operations in the same order.
//
// The fixture is read with JSONDecoder: JSONSerialization hands long
// decimals over as NSDecimalNumber, whose doubleValue is off in the last
// bits. Only the raw settings inputs, which have to stay untyped, go
// through JSONSerialization.

private struct Fixture: Decodable {
    struct Schedule: Decodable {
        let monthlySalary: Double
        let workingDays: Double
        let workingHoursPerDay: Double
        let startHour: String
        let endHour: String
        let payday: Int
        let exchangeRate: Double
    }

    struct NextPayday: Decodable {
        let date: Double
        let daysLeft: Int
        let isToday: Bool
        let amount: Double

        init(from decoder: Decoder) throws {
            var values = try decoder.unkeyedContainer()
            date = try values.decode(Double.self)
            daysLeft = try values.decode(Int.self)
            isToday = try values.decode(Bool.self)
            amount = try values.decode(Double.self)
        }
    }

    struct EarningsCase: Decodable {
        let timeZone: String
        let schedule: String
        let now: Double
        let window: [Double]
        let scheduled: Bool
        let hour: [Double]
        let day: [Double]
        let week: [Double]
        let month: [Double]
        let year: [Double]
        let rates: [Double]
        let nextPayday: NextPayday

        subscript(period: Period) -> [Double] {
            switch period {
            case .hour: hour
            case .day: day
            case .week: week
            case .month: month
            case .year: year
            }
        }
    }

    struct PaydayCase: Decodable {
        let year: Int
        let month: Int
        let days: [Int]
    }

    struct CurrencyCase: Decodable {
        let amount: Double
        let currency: String
        let digits: Int
        let text: String
    }

    struct NormalizerCase: Decodable {
        /// NaN and the infinities come as strings
        let input: Double
        let workingDays: Double
        let payday: Int
        let workingHoursPerDay: Double

        enum CodingKeys: String, CodingKey {
            case input, workingDays, payday, workingHoursPerDay
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            if let number = try? values.decode(Double.self, forKey: .input) {
                input = number
            } else {
                let text = try values.decode(String.self, forKey: .input)
                input = Double(text.replacingOccurrences(of: "Infinity", with: "inf"))!
            }
            workingDays = try values.decode(Double.self, forKey: .workingDays)
            payday = try values.decode(Int.self, forKey: .payday)
            workingHoursPerDay = try values.decode(Double.self, forKey: .workingHoursPerDay)
        }
    }

    struct TimeCase: Decodable {
        let input: String
        let output: String?
    }

    struct ExpectedSettings: Decodable {
        let output: ExpectedSettingsValues
    }

    struct ExpectedSettingsValues: Decodable {
        let monthlySalary: Double
        let monthlySalaryCurrency: String
        let earningsCurrency: String
        let workingHoursPerDay: Double
        let workingDays: Double
        let payday: Int
        let startHour: String
        let endHour: String
        let selectedPeriod: String
        let theme: String
        let showInMenuBar: Bool
        let menuBarAmount: String
        let launchAtLogin: Bool
        let notifyEndOfDay: Bool
        let notifyPayday: Bool
    }

    let schedules: [String: Schedule]
    let earnings: [EarningsCase]
    let paydays: [PaydayCase]
    let currency: [CurrencyCase]
    let normalizers: [NormalizerCase]
    let times: [TimeCase]
    let settings: [ExpectedSettings]
}

private let fixtureData: Data = {
    let url = Bundle.module.url(forResource: "parity", withExtension: "json", subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
}()

private let fixture = try! JSONDecoder().decode(Fixture.self, from: fixtureData)

private func calendar(in timeZone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZone)!
    return calendar
}

private func milliseconds(_ date: Date) -> Double {
    (date.timeIntervalSince1970 * 1000).rounded()
}

@Test func earningsMatchTypeScript() {
    #expect(fixture.earnings.count > 2000)
    var models: [String: EarningsModel] = [:]

    for item in fixture.earnings {
        let model = models[item.timeZone] ?? EarningsModel(calendar: calendar(in: item.timeZone))
        models[item.timeZone] = model

        let schedule = fixture.schedules[item.schedule]!
        let settings = EarningsSettings(
            monthlySalary: schedule.monthlySalary,
            workday: WorkdaySettings(
                workingDays: schedule.workingDays,
                workingHoursPerDay: schedule.workingHoursPerDay,
                startHour: TimeOfDay(parsing: schedule.startHour),
                endHour: TimeOfDay(parsing: schedule.endHour)
            ),
            payday: schedule.payday,
            exchangeRate: schedule.exchangeRate
        )
        let now = Date(timeIntervalSince1970: item.now / 1000)
        let label = "\(item.schedule) at \(Int(item.now)) in \(item.timeZone)"

        let window = model.workingWindow(on: now, settings.workday)
        #expect([milliseconds(window.start), milliseconds(window.end)] == item.window, "window, \(label)")
        #expect(model.isScheduledDay(now, workingDays: settings.workday.workingDays) == item.scheduled, "scheduled, \(label)")

        let snapshot = model.earnings(at: now, settings)
        for period in Period.allCases {
            #expect([snapshot[period].earned, snapshot[period].total] == item[period], "\(period), \(label)")
        }
        let rates = snapshot.rates
        #expect([rates.perSecond, rates.perMinute, rates.perHour, rates.perDay] == item.rates, "rates, \(label)")

        let payday = snapshot.nextPayday
        #expect(milliseconds(payday.date) == item.nextPayday.date, "payday date, \(label)")
        #expect(payday.daysLeft == item.nextPayday.daysLeft, "days left, \(label)")
        #expect(payday.isToday == item.nextPayday.isToday, "payday is today, \(label)")
        #expect(payday.amount == item.nextPayday.amount, "payday amount, \(label)")
    }
}

@Test func paydaysMatchTypeScript() {
    let model = EarningsModel(calendar: calendar(in: "Europe/Kyiv"))

    for item in fixture.paydays {
        let day = model.calendar.date(from: DateComponents(year: item.year, month: item.month, day: 10))!
        let actual = (1...31).map {
            model.calendar.component(.day, from: model.paydayInMonth(of: day, payday: $0))
        }
        #expect(actual == item.days, "\(item.year)-\(item.month)")
    }
}

@Test func currencyFormatMatchesTypeScript() {
    for item in fixture.currency {
        #expect(
            formatCurrency(item.amount, currency: item.currency, fractionDigits: item.digits) == item.text,
            "\(item.amount) \(item.currency), \(item.digits) digits"
        )
    }
}

@Test func normalizersMatchTypeScript() {
    for item in fixture.normalizers {
        #expect(normalizeWorkingDays(item.input) == item.workingDays, "working days for \(item.input)")
        #expect(normalizePayday(item.input) == item.payday, "payday for \(item.input)")
        #expect(normalizeWorkingHoursPerDay(item.input) == item.workingHoursPerDay, "hours a day for \(item.input)")
    }
}

@Test func timesMatchTypeScript() {
    for item in fixture.times {
        #expect(TimeOfDay(parsing: item.input)?.formatted == item.output, "\"\(item.input)\"")
    }
}

@Test func settingsValidationMatchesTypeScript() throws {
    let json = try JSONSerialization.jsonObject(with: fixtureData) as! [String: Any]
    let inputs = (json["settings"] as! [[String: Any]]).map { $0["input"]! }
    #expect(inputs.count == fixture.settings.count)

    for (input, expected) in zip(inputs, fixture.settings.map(\.output)) {
        let actual = Settings(sanitizing: input is NSNull ? nil : input)
        #expect(actual == Settings(exactly: expected), "\(input)")
    }
}

extension Settings {
    /// The expected values as they are, without validation
    fileprivate init(exactly values: Fixture.ExpectedSettingsValues) {
        self.init()
        monthlySalary = values.monthlySalary
        monthlySalaryCurrency = values.monthlySalaryCurrency
        earningsCurrency = values.earningsCurrency
        workingHoursPerDay = values.workingHoursPerDay
        workingDays = values.workingDays
        payday = values.payday
        startHour = values.startHour
        endHour = values.endHour
        selectedPeriod = Period(rawValue: values.selectedPeriod)!
        theme = Theme(rawValue: values.theme)!
        showInMenuBar = values.showInMenuBar
        menuBarAmount = MenuBarAmount(rawValue: values.menuBarAmount)!
        launchAtLogin = values.launchAtLogin
        notifyEndOfDay = values.notifyEndOfDay
        notifyPayday = values.notifyPayday
    }
}
