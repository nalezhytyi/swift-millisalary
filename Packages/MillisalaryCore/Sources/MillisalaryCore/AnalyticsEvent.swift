/// An analytics event as the Electron app sent it to Amplitude: snake_case
/// names and properties
public struct AnalyticsEvent: Equatable, Sendable {
    public enum Value: Equatable, Sendable {
        case string(String)
        case number(Double)
        case bool(Bool)
    }

    public let name: String
    public let properties: [String: Value]

    public init(_ name: String, _ properties: [String: Value] = [:]) {
        self.name = name
        self.properties = properties
    }
}

extension AnalyticsEvent {
    /// What the Settings pane reports for an edit that turned `before` into
    /// `after`: one event per changed form field, in the order of the
    /// Electron app's getChangedFields and named as in its
    /// settingsEvents.ts (a coupled edit, e.g. Start moving End, reports
    /// both), then the switches' and pop-ups' own events
    public static func settingsChanges(from before: Settings, to after: Settings) -> [AnalyticsEvent] {
        var events: [AnalyticsEvent] = []

        if after.monthlySalary != before.monthlySalary {
            // The amount goes out, as in the Electron app (the user's choice)
            events.append(AnalyticsEvent("salary_input_blurred", [
                "salary_value": .number(after.monthlySalary),
                "has_salary_value": .bool(after.monthlySalary > 0),
            ]))
        }
        if after.monthlySalaryCurrency != before.monthlySalaryCurrency {
            events.append(AnalyticsEvent("salary_currency_changed", ["currency": .string(after.monthlySalaryCurrency)]))
        }
        if after.earningsCurrency != before.earningsCurrency {
            events.append(AnalyticsEvent("earnings_currency_changed", ["currency": .string(after.earningsCurrency)]))
        }
        if after.workingDays != before.workingDays {
            events.append(AnalyticsEvent("working_days_changed", ["working_days": .number(after.workingDays)]))
        }
        if after.workingHoursPerDay != before.workingHoursPerDay {
            events.append(AnalyticsEvent("working_hours_per_day_changed", [
                "working_hours_per_day": .number(after.workingHoursPerDay),
            ]))
        }
        if after.startHour != before.startHour {
            events.append(AnalyticsEvent("workday_start_time_changed", time("start_time", after.startHour)))
        }
        if after.endHour != before.endHour {
            events.append(AnalyticsEvent("workday_end_time_changed", time("end_time", after.endHour)))
        }
        if after.payday != before.payday {
            events.append(AnalyticsEvent("payday_changed", ["payday": .number(Double(after.payday))]))
        }
        if after.launchAtLogin != before.launchAtLogin {
            events.append(AnalyticsEvent("launch_at_login_changed", ["enabled": .bool(after.launchAtLogin)]))
        }
        if after.notifyEndOfDay != before.notifyEndOfDay || after.notifyPayday != before.notifyPayday {
            events.append(AnalyticsEvent("notifications_changed", [
                "end_of_day": .bool(after.notifyEndOfDay),
                "payday": .bool(after.notifyPayday),
            ]))
        }
        if after.showInMenuBar != before.showInMenuBar || after.menuBarAmount != before.menuBarAmount {
            events.append(AnalyticsEvent("menu_bar_display_changed", [
                "shown": .bool(after.showInMenuBar),
                "amount": .string(after.menuBarAmount.rawValue),
            ]))
        }
        if after.theme != before.theme {
            events.append(AnalyticsEvent("theme_changed", ["theme": .string(after.theme.rawValue)]))
        }

        return events
    }

    /// "09:00" as formatEventTime wrote it; a cleared time has no property
    private static func time(_ key: String, _ value: String) -> [String: Value] {
        value.isEmpty ? [:] : [key: .string(value)]
    }
}
