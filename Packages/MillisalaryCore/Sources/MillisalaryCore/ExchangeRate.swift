import Foundation

/// From the salary's currency to the one amounts are shown in. Its `key`,
/// e.g. "USD>UAH", is what a rate is cached under (getRatePair)
public struct CurrencyPair: Hashable, Sendable, CustomStringConvertible {
    public let from: String
    public let to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    public var key: String { "\(from)>\(to)" }
    public var description: String { key }

    /// The same currency on both sides: always a rate of 1, nothing to fetch
    public var isSameCurrency: Bool { from == to }
}

extension Settings {
    public var ratePair: CurrencyPair {
        CurrencyPair(from: monthlySalaryCurrency, to: earningsCurrency)
    }
}

/// exchangerate-api.com, as the Electron app uses it: one request per base
/// currency, the rate to the other one read from its `rates`
public enum ExchangeRateAPI {
    public static let baseURL = URL(string: "https://api.exchangerate-api.com/v4/latest/")!

    /// After a fresh rate, the next one is fetched this much later
    public static let refreshInterval: TimeInterval = 6 * 60 * 60
    /// A failed fetch (often a launch at login before the network is up) is
    /// retried after a minute, then after twice as long each time, up to
    /// half an hour
    public static let firstRetryDelay: TimeInterval = 60
    public static let maxRetryDelay: TimeInterval = 30 * 60

    public static func nextRetryDelay(after delay: TimeInterval) -> TimeInterval {
        min(delay * 2, maxRetryDelay)
    }

    public static func url(for pair: CurrencyPair, base: URL = baseURL) -> URL {
        base.appendingPathComponent(pair.from)
    }

    public enum Failure: Error, Equatable {
        case noUsableRate(CurrencyPair)
    }

    /// The pair's rate in a response; anything but a finite number above 0
    /// is no rate (fetchRate's checks)
    public static func rate(in data: Data, for pair: CurrencyPair) throws -> Double {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let rate = response.rates?[pair.to]?.value,
              rate.isFinite, rate > 0
        else { throw Failure.noUsableRate(pair) }
        return rate
    }

    private struct Response: Decodable {
        let rates: [String: Number]?
    }

    /// A rate that isn't a number is simply missing, rather than failing the
    /// whole response
    private struct Number: Decodable {
        let value: Double?

        init(from decoder: Decoder) throws {
            value = try? decoder.singleValueContainer().decode(Double.self)
        }
    }
}

/// The cached rates from untrusted data (stored values, the Electron app's
/// settings.json): pairs like "USD>UAH" with a finite rate above 0
/// (sanitizeRates)
public func sanitizeRates(_ raw: Any?) -> [String: Double] {
    guard let raw = raw as? [String: Any] else { return [:] }
    var rates: [String: Double] = [:]

    for (pair, value) in raw where pair.wholeMatch(of: /[A-Z]{3}>[A-Z]{3}/) != nil {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { continue }
        // JSONSerialization's NSDecimalNumber is exact only as text
        let rate = (number as? NSDecimalNumber).flatMap { Double($0.description) } ?? number.doubleValue
        if rate.isFinite, rate > 0 {
            rates[pair] = rate
        }
    }

    return rates
}
