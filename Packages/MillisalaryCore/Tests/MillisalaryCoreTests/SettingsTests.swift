import Foundation
import Testing
@testable import MillisalaryCore

private func customised() -> Settings {
    var settings = Settings()
    settings.monthlySalary = 54321.5
    settings.monthlySalaryCurrency = "EUR"
    settings.earningsCurrency = "PLN"
    settings.workingHoursPerDay = 8.33
    settings.workingDays = 20
    settings.payday = 25
    settings.startHour = "08:30"
    settings.endHour = ""
    settings.selectedPeriod = .month
    settings.theme = .dark
    settings.showInMenuBar = false
    settings.menuBarAmount = .selected
    settings.launchAtLogin = true
    settings.notifyEndOfDay = false
    settings.notifyPayday = false
    settings.dialFacts = [.nextPayday, .exchangeRate]
    return settings
}

@Test func dialFactsAreCleanedUp() {
    let known = Settings(sanitizing: [
        "dialFacts": ["perHour", "perHour", "fromALaterVersion", 3, "perDay", "paycheck", "earnedToday", "perSecond"],
    ])
    #expect(known.dialFacts == [.perHour, .perDay, .paycheck, .earnedToday])
    #expect(Settings(sanitizing: ["dialFacts": [String]()]).dialFacts.isEmpty)
    #expect(Settings(sanitizing: ["dialFacts": "perHour"]).dialFacts == DialFact.defaults)
}

@Test func propertyListRoundTrips() {
    let settings = customised()
    #expect(Settings(sanitizing: settings.propertyList) == settings)
    #expect(Settings(sanitizing: Settings.defaults.propertyList) == .defaults)
}

// What the app does: each key stored on its own in UserDefaults, read back
// through the validator. Booleans must stay booleans and numbers numbers
@Test func userDefaultsRoundTrips() throws {
    let suite = "MillisalaryCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let settings = customised()
    for (key, value) in settings.propertyList {
        defaults.set(value, forKey: key)
    }

    #expect(Settings(sanitizing: defaults.dictionaryRepresentation()) == settings)
}

@Test func storedValuesOfTheWrongTypeAreIgnored() {
    let settings = Settings(sanitizing: [
        "monthlySalary": true,
        "showInMenuBar": 0,
        "payday": "5",
        "workingDays": 12,
    ])
    #expect(settings.monthlySalary == 0)
    #expect(settings.showInMenuBar)
    #expect(settings.payday == 1)
    #expect(settings.workingDays == 12)
}

@Test func workdayReadsTheStoredTimes() {
    var settings = Settings()
    settings.startHour = "22:00"
    settings.endHour = ""
    #expect(settings.workday.startHour == TimeOfDay(hour: 22, minute: 0))
    #expect(settings.workday.endHour == nil)
}
