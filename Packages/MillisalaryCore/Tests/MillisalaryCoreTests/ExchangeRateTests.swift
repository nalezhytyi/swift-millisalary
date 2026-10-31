import Foundation
import Testing
@testable import MillisalaryCore

private let usdToUah = CurrencyPair(from: "USD", to: "UAH")

@Test func pairFollowsTheSettings() {
    var settings = Settings()
    #expect(settings.ratePair.key == "USD>UAH")
    #expect(!settings.ratePair.isSameCurrency)

    settings.earningsCurrency = "USD"
    #expect(settings.ratePair.isSameCurrency)
}

@Test func requestIsForTheSalaryCurrency() {
    #expect(ExchangeRateAPI.url(for: usdToUah).absoluteString == "https://api.exchangerate-api.com/v4/latest/USD")
}

@Test func rateIsReadFromTheResponse() throws {
    let data = Data(#"{"base":"USD","rates":{"USD":1,"UAH":41.37,"EUR":0.9216}}"#.utf8)
    #expect(try ExchangeRateAPI.rate(in: data, for: usdToUah) == 41.37)
}

@Test(arguments: [
    #"{"rates":{"EUR":0.92}}"#,
    #"{"rates":{"UAH":"41.37"}}"#,
    #"{"rates":{"UAH":0}}"#,
    #"{"rates":{"UAH":-1}}"#,
    #"{"rates":{"UAH":true}}"#,
    #"{"result":"error"}"#,
    #"not json"#,
])
func unusableResponsesHaveNoRate(_ body: String) {
    #expect(throws: ExchangeRateAPI.Failure.noUsableRate(usdToUah)) {
        try ExchangeRateAPI.rate(in: Data(body.utf8), for: usdToUah)
    }
}

@Test func otherBadRatesDontSpoilTheOneAskedFor() throws {
    let data = Data(#"{"rates":{"UAH":41.37,"XYZ":null,"ABC":"n/a"}}"#.utf8)
    #expect(try ExchangeRateAPI.rate(in: data, for: usdToUah) == 41.37)
}

@Test func retriesBackOffUpToHalfAnHour() {
    var delays = [ExchangeRateAPI.firstRetryDelay]
    while delays.count < 7 {
        delays.append(ExchangeRateAPI.nextRetryDelay(after: delays.last!))
    }
    #expect(delays == [60, 120, 240, 480, 960, 1800, 1800])
}

@Test func cachedRatesAreValidated() throws {
    let json = #"{"USD>UAH":41.37,"USD>EUR":0.92160000000000000001,"usd>pln":4,"USD>CZK":0,"EUR>RON":"5","GBP>USD":true,"PLN":3}"#
    let raw = try JSONSerialization.jsonObject(with: Data(json.utf8))
    #expect(sanitizeRates(raw) == ["USD>UAH": 41.37, "USD>EUR": 0.9216])
    #expect(sanitizeRates(nil).isEmpty)
    #expect(sanitizeRates([1, 2]).isEmpty)
}
