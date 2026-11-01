import AppKit
import MillisalaryCore
import Observation
import os

/// The exchange rate for the pair the settings name (exchangeRate.ts in the
/// Electron app). The same currency is always 1; otherwise the last known
/// rate for the pair, kept in UserDefaults so an offline launch keeps
/// converting, until a fresh one arrives. Fetched when the pair changes,
/// every 6 h after that and on wake; a failure is retried after a minute,
/// doubling up to half an hour (the app runs for weeks in the menu bar, and
/// a launch at login often beats the network)
@Observable
final class ExchangeRateStore {
    struct Rate: Equatable {
        let pair: CurrencyPair
        let rate: Double
    }

    /// The followed pair's rate, nil while none is known
    private(set) var current: Rate?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var cache: [String: Double]
    @ObservationIgnored private var pair: CurrencyPair?
    @ObservationIgnored private var task: Task<Void, Never>?

    private static let cacheKey = "exchangeRates"
    private static let log = Logger(category: "exchange-rate")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cache = sanitizeRates(defaults.dictionary(forKey: Self.cacheKey))
    }

    /// The rate for `pair` when it's the one followed: a rate only applies
    /// to the pair it was fetched for
    func rate(for pair: CurrencyPair) -> Double? {
        if pair.isSameCurrency { return 1 }
        return current?.pair == pair ? current?.rate : nil
    }

    /// Points the store at `pair`: the cached rate at once, then a fetch.
    /// Call it at launch and whenever a currency changes
    func follow(_ pair: CurrencyPair) {
        guard pair != self.pair else { return }
        self.pair = pair
        task?.cancel()
        task = nil

        if pair.isSameCurrency {
            current = Rate(pair: pair, rate: 1)
            return
        }
        current = cache[pair.key].map { Rate(pair: pair, rate: $0) }
        startFetching(pair)
    }

    /// Fetches again now, e.g. after the Mac wakes: a night's sleep would
    /// otherwise delay the refresh
    func refresh() {
        guard let pair, !pair.isSameCurrency else { return }
        startFetching(pair)
    }

    /// Rates taken over from the Electron app; ones already known here win
    func importCache(_ rates: [String: Double]) {
        cache.merge(rates) { known, _ in known }
        defaults.set(cache, forKey: Self.cacheKey)
    }

    private func startFetching(_ pair: CurrencyPair) {
        task?.cancel()
        task = Task { [weak self] in
            var retryDelay = ExchangeRateAPI.firstRetryDelay

            while !Task.isCancelled {
                let delay: TimeInterval
                do {
                    let rate = try await Self.fetch(pair)
                    self?.store(rate, for: pair)
                    Self.log.info("\(pair.key, privacy: .public) is \(rate, privacy: .public)")
                    retryDelay = ExchangeRateAPI.firstRetryDelay
                    delay = ExchangeRateAPI.refreshInterval
                } catch where Task.isCancelled {
                    // Another pair followed, or a refresh, while the request
                    // was out: not a failure. URLSession throws
                    // URLError(.cancelled) then, not CancellationError
                    return
                } catch {
                    Self.log.error("\(pair.key, privacy: .public) failed, retrying in \(Int(retryDelay), privacy: .public) s: \(error.localizedDescription, privacy: .public)")
                    delay = retryDelay
                    retryDelay = ExchangeRateAPI.nextRetryDelay(after: retryDelay)
                }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func store(_ rate: Double, for pair: CurrencyPair) {
        // The user may have switched pairs while the request was out
        guard pair == self.pair else { return }
        cache[pair.key] = rate
        defaults.set(cache, forKey: Self.cacheKey)
        current = Rate(pair: pair, rate: rate)
    }

    private nonisolated static func fetch(_ pair: CurrencyPair) async throws -> Double {
        let (data, response) = try await URLSession.shared.data(from: ExchangeRateAPI.url(for: pair, base: apiBase))
        // 4xx and 5xx are failures too, not just network errors
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try ExchangeRateAPI.rate(in: data, for: pair)
    }

    /// Debug builds can point it elsewhere with `-debugExchangeRateURL <base>`
    /// (e.g. an address nothing listens on, to watch the retries)
    private nonisolated static var apiBase: URL {
        #if DEBUG
        if let base = UserDefaults.standard.string(forKey: "debugExchangeRateURL"), let url = URL(string: base) {
            return url
        }
        #endif
        return ExchangeRateAPI.baseURL
    }
}
