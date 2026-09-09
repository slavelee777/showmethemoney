import Foundation

struct ExchangeRates {
    let rates: [String: Decimal] // Units per USD
    let date: String
    var stale = false
    func convert(_ amount: Decimal, from currency: String, to target: String) -> Decimal? {
        let minor = currency == "GBp" || currency == "GBX"
        let source = minor ? "GBP" : currency.uppercased()
        let value = minor ? amount / 100 : amount
        if source == target { return value }
        guard let from = rates[source], let to = rates[target], from > 0, to > 0 else { return nil }
        let result = value / from * to
        return result.isNaN ? nil : result
    }
    static func parse(_ json: [String: Any]) throws -> ExchangeRates {
        guard json["base"] as? String == "USD", let date = json["date"] as? String,
              date.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil,
              let raw = json["rates"] as? [String: Any] else { throw MarketError.unavailable }
        var rates: [String: Decimal] = ["USD": 1]
        for (code, value) in raw {
            guard let number = value as? NSNumber, let rate = Decimal(string: number.stringValue), rate > 0, rate < 1_000_000_000 else { throw MarketError.unavailable }
            rates[code] = rate
        }
        guard rates["KRW"] != nil else { throw MarketError.unavailable }
        return ExchangeRates(rates: rates, date: date)
    }
}
actor ExchangeCache {
    static let shared = ExchangeCache()
    var cached: ExchangeRates?
    var nextFetch = Date.distantPast
    func latest() async -> ExchangeRates? {
        if Date() < nextFetch { return cached }
        // Reserve a retry window before suspension, including concurrent stock changes.
        nextFetch = Date().addingTimeInterval(300)
        do {
            let json = try await request("/v1/latest", query: [URLQueryItem(name: "base", value: "USD")], host: "https://api.frankfurter.dev")
            cached = try ExchangeRates.parse(json)
            nextFetch = Date().addingTimeInterval(3600)
        } catch { if Task.isCancelled { nextFetch = .distantPast } else { cached?.stale = true } }
        return cached
    }
}
