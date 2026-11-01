import Foundation

public enum Theme: String, CaseIterable, Sendable {
    case system, light, dark
}

public enum MenuBarAmount: String, CaseIterable, Sendable {
    case day, selected
}

/// What the card under the Earnings dial can show, in the order Settings
/// lists them
public enum DialFact: String, CaseIterable, Sendable {
    case perSecond, perMinute, perHour, perDay, nextPayday, paycheck, leftToEarn, earnedToday, exchangeRate

    /// The card fits four
    public static let maximum = 4
    public static let defaults: [DialFact] = [.perSecond, .perHour, .perDay]
}

/// The app's settings: the keys, values and defaults of the Electron app's
/// settings.json (settings.ts), plus `dialFacts`, which only this app has.
/// Start and end times are "HH:mm" strings, or "" when cleared
public struct Settings: Equatable, Sendable {
    public var monthlySalary: Double = 0
    public var monthlySalaryCurrency = "USD"
    public var earningsCurrency = "UAH"
    public var workingHoursPerDay = defaultWorkingHoursPerDay
    public var workingDays = defaultWorkingDays
    public var payday = 1
    public var startHour = "09:00"
    public var endHour = String(format: "%02d:00", 9 + Int(defaultWorkingHoursPerDay))
    public var selectedPeriod = Period.day
    public var theme = Theme.system
    /// The earnings ticking in the macOS menu bar
    public var showInMenuBar = true
    /// Which amount the menu bar shows: today's, or the selected period's
    public var menuBarAmount = MenuBarAmount.day
    /// Start with the Mac, in the menu bar only
    public var launchAtLogin = false
    /// A notification when the workday ends, with what you earned
    public var notifyEndOfDay = true
    /// A notification on payday
    public var notifyPayday = true
    /// The facts in the card under the Earnings dial, in order, at most
    /// `DialFact.maximum`; none hides the card
    public var dialFacts = DialFact.defaults

    public init() {}

    public static let defaults = Settings()

    public enum Key: String, CaseIterable, Sendable {
        case monthlySalary, monthlySalaryCurrency, earningsCurrency
        case workingHoursPerDay, workingDays, payday, startHour, endHour
        case selectedPeriod, theme, showInMenuBar, menuBarAmount
        case launchAtLogin, notifyEndOfDay, notifyPayday
        case dialFacts
    }
}

// MARK: - Validation

extension Settings {
    static let maxSalary: Double = 1_000_000_000

    /// Settings from untrusted data (stored values, a settings.json), with
    /// the defaults for anything missing or bad (sanitizeSettings)
    public init(sanitizing raw: Any?) {
        self = Settings.defaults.applying(raw)
    }

    /// `self` with each valid field of `raw`, a dictionary keyed like
    /// settings.json; unknown keys and bad values are ignored (sanitizePatch)
    public func applying(_ raw: Any?) -> Settings {
        var result = self
        guard let raw = raw as? [String: Any] else { return result }

        for key in Key.allCases {
            if let value = raw[key.rawValue] {
                result.apply(value, for: key)
            }
        }

        return result
    }

    /// Sets one field from an untrusted value, cleaned up the way the
    /// Electron app's validator for it does; a value it can't use changes
    /// nothing and returns false
    @discardableResult
    public mutating func apply(_ value: Any, for key: Key) -> Bool {
        switch key {
        case .monthlySalary:
            guard let number = number(value), number >= 0 else { return false }
            monthlySalary = min(number, Self.maxSalary)
        case .monthlySalaryCurrency:
            guard let code = currency(value) else { return false }
            monthlySalaryCurrency = code
        case .earningsCurrency:
            guard let code = currency(value) else { return false }
            earningsCurrency = code
        case .workingHoursPerDay:
            guard let number = number(value), number > 0 else { return false }
            workingHoursPerDay = normalizeWorkingHoursPerDay(number)
        case .workingDays:
            guard let number = number(value), number > 0 else { return false }
            workingDays = normalizeWorkingDays(number)
        case .payday:
            guard let number = number(value), number >= 1 else { return false }
            payday = normalizePayday(number)
        case .startHour:
            guard let time = time(value) else { return false }
            startHour = time
        case .endHour:
            guard let time = time(value) else { return false }
            endHour = time
        case .selectedPeriod:
            guard let period = (value as? String).flatMap(Period.init) else { return false }
            selectedPeriod = period
        case .theme:
            guard let theme = (value as? String).flatMap(Theme.init) else { return false }
            self.theme = theme
        case .showInMenuBar:
            guard let flag = bool(value) else { return false }
            showInMenuBar = flag
        case .menuBarAmount:
            guard let amount = (value as? String).flatMap(MenuBarAmount.init) else { return false }
            menuBarAmount = amount
        case .launchAtLogin:
            guard let flag = bool(value) else { return false }
            launchAtLogin = flag
        case .notifyEndOfDay:
            guard let flag = bool(value) else { return false }
            notifyEndOfDay = flag
        case .notifyPayday:
            guard let flag = bool(value) else { return false }
            notifyPayday = flag
        case .dialFacts:
            guard let facts = facts(value) else { return false }
            dialFacts = facts
        }

        return true
    }

    /// The settings as property-list values keyed like settings.json, for
    /// UserDefaults
    public var propertyList: [String: Any] {
        [
            Key.monthlySalary.rawValue: monthlySalary,
            Key.monthlySalaryCurrency.rawValue: monthlySalaryCurrency,
            Key.earningsCurrency.rawValue: earningsCurrency,
            Key.workingHoursPerDay.rawValue: workingHoursPerDay,
            Key.workingDays.rawValue: workingDays,
            Key.payday.rawValue: payday,
            Key.startHour.rawValue: startHour,
            Key.endHour.rawValue: endHour,
            Key.selectedPeriod.rawValue: selectedPeriod.rawValue,
            Key.theme.rawValue: theme.rawValue,
            Key.showInMenuBar.rawValue: showInMenuBar,
            Key.menuBarAmount.rawValue: menuBarAmount.rawValue,
            Key.launchAtLogin.rawValue: launchAtLogin,
            Key.notifyEndOfDay.rawValue: notifyEndOfDay,
            Key.notifyPayday.rawValue: notifyPayday,
            Key.dialFacts.rawValue: dialFacts.map(\.rawValue),
        ]
    }

    /// What the earnings model needs from the settings
    public var workday: WorkdaySettings {
        WorkdaySettings(
            workingDays: workingDays,
            workingHoursPerDay: workingHoursPerDay,
            startHour: TimeOfDay(parsing: startHour),
            endHour: TimeOfDay(parsing: endHour)
        )
    }

    public func earningsSettings(exchangeRate: Double) -> EarningsSettings {
        EarningsSettings(
            monthlySalary: monthlySalary,
            workday: workday,
            payday: payday,
            exchangeRate: exchangeRate
        )
    }
}

// JSON and property lists both hand numbers and booleans over as NSNumber;
// like `typeof` in the Electron app's validators, a boolean is not a number
// and a number is not a boolean

private func number(_ value: Any) -> Double? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID()
    else { return nil }
    let double = number.doubleValue
    return double.isFinite ? double : nil
}

private func bool(_ value: Any) -> Bool? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID()
    else { return nil }
    return number.boolValue
}

private func currency(_ value: Any) -> String? {
    guard let string = value as? String,
          string.wholeMatch(of: /[A-Z]{3}/) != nil
    else { return nil }
    return string
}

/// A list of fact names: the ones this version knows (a later one may add
/// more), each once, the first `DialFact.maximum`
private func facts(_ value: Any) -> [DialFact]? {
    guard let names = value as? [Any] else { return nil }
    var facts: [DialFact] = []
    for case let name as String in names {
        if let fact = DialFact(rawValue: name), !facts.contains(fact) {
            facts.append(fact)
        }
    }
    return Array(facts.prefix(DialFact.maximum))
}

private func time(_ value: Any) -> String? {
    guard let string = value as? String,
          string.isEmpty || string.wholeMatch(of: /(?:[01][0-9]|2[0-3]):[0-5][0-9]/) != nil
    else { return nil }
    return string
}
