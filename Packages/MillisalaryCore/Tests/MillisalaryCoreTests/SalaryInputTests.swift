import Foundation
import Testing
@testable import MillisalaryCore

private let ukrainian = Locale(identifier: "uk_UA")
private let american = Locale(identifier: "en_US")
private let german = Locale(identifier: "de_DE")

@Test func salaryInputKeepsDigitsSpacesAndSeparators() {
    #expect(salaryInput("54\u{00A0}321,5", locale: ukrainian) == "54\u{00A0}321,5")
    #expect(salaryInput("54 321,50", locale: ukrainian) == "54 321,50")
    #expect(salaryInput("54,321.5", locale: american) == "54,321.5")
    #expect(salaryInput("54.321,5", locale: german) == "54.321,5")
    #expect(salaryInput("", locale: ukrainian) == "")
}

@Test func salaryInputTakesTheOtherPointAsTheDecimalSeparator() {
    // Where it isn't the grouping separator; uk_UA's parse stopped at "."
    #expect(salaryInput("54321.50", locale: ukrainian) == "54321,50")
    // en_US groups with ",", de_DE with "."
    #expect(salaryInput("1,500", locale: american) == "1,500")
    #expect(salaryInput("1.500", locale: german) == "1.500")
}

@Test func salaryInputRejectsAnythingElse() {
    #expect(salaryInput("-500", locale: ukrainian) == nil)
    #expect(salaryInput("12a", locale: ukrainian) == nil)
    #expect(salaryInput("5e3", locale: american) == nil)
    #expect(salaryInput("+500", locale: american) == nil)
    #expect(salaryInput("1,2,3", locale: ukrainian) == nil)
    #expect(salaryInput("1.2.3", locale: american) == nil)
    #expect(salaryInput("500 UAH", locale: ukrainian) == nil)
}

@Test func salaryInputKeepsWhatTheFieldShows() {
    // Every locale's own formatting of a salary, its digits included
    for identifier in ["uk_UA", "en_US", "de_DE", "fr_FR", "de_CH", "ar_EG", "hi_IN"] {
        let locale = Locale(identifier: identifier)
        let shown = 1234567.89.formatted(.number.locale(locale))
        #expect(salaryInput(shown, locale: locale) == shown, "\(identifier): \(shown)")
    }
}
