import Foundation

struct Stock: Codable, Equatable {
    let symbol: String
    let name: String
    var displayName: String { AppLanguage.code == "en" ? AppLanguage.stockNames[symbol] ?? L(name) : name }
}
let catalog: [Stock] = [
    Stock(symbol: "005930.KS", name: "삼성전자"), Stock(symbol: "000660.KS", name: "SK하이닉스"),
    Stock(symbol: "035420.KS", name: "네이버 NAVER"), Stock(symbol: "035720.KS", name: "카카오"),
    Stock(symbol: "005380.KS", name: "현대차"), Stock(symbol: "373220.KS", name: "LG에너지솔루션"),
    Stock(symbol: "086520.KQ", name: "에코프로"), Stock(symbol: "247540.KQ", name: "에코프로비엠"),
    Stock(symbol: "AAPL", name: "애플 Apple"), Stock(symbol: "NVDA", name: "엔비디아 NVIDIA"),
    Stock(symbol: "TSLA", name: "테슬라 Tesla"), Stock(symbol: "MSFT", name: "마이크로소프트 Microsoft"),
    Stock(symbol: "GOOGL", name: "알파벳 Google"), Stock(symbol: "AMZN", name: "아마존 Amazon")
]
func localSearch(_ query: String) -> [Stock] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if q.isEmpty { return Array(catalog.prefix(8)) }
    return catalog.filter { $0.name.localizedCaseInsensitiveContains(q) || (AppLanguage.stockNames[$0.symbol]?.localizedCaseInsensitiveContains(q) ?? false) || $0.symbol.localizedCaseInsensitiveContains(q) }
}
func directSymbol(_ query: String) -> String? {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if q.range(of: "^[0-9]{6}$", options: .regularExpression) != nil { return catalog.first(where: { $0.symbol.hasPrefix(q + ".") })?.symbol }
    return q.range(of: "^[A-Z0-9^][A-Z0-9.^=-]{0,19}$", options: .regularExpression) != nil ? q : nil
}
enum MarketError: LocalizedError {
    case unavailable
    var errorDescription: String? { L("시세를 불러오지 못했습니다.") }
}
func request(_ path: String, query: [URLQueryItem], host: String = "https://query1.finance.yahoo.com") async throws -> [String: Any] {
    var url = URLComponents(string: host + path)!
    url.queryItems = query
    var request = URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
    request.setValue("ShowMeTheMoney/1.0", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MarketError.unavailable }
    return json
}
struct Quote {
    let price: Double
    let currency: String
    let time: Date
    var source = "Yahoo · 지연 가능"
    var marketStatus = ""
    var sessionOpen: Bool? = nil
    var exchange: ExchangeRates? = nil
    var previousClose: Decimal? = nil
    var dailyPercent: Decimal? {
        guard let previous = previousClose, previous >= Decimal(string: "0.00000001")!, previous <= 999_999_999_999,
              price.isFinite, price > 0, price <= 999_999_999_999,
              let current = Decimal(string: String(price)) else { return nil }
        return (current - previous) / previous * 100
    }
    var dailyFormatted: String { dailyPercent.map(holdingPercent) ?? "—" }
    static func number(_ value: Any?) -> Decimal? {
        let text = ((value as? String) ?? (value as? NSNumber)?.stringValue ?? "").replacingOccurrences(of: ",", with: "")
        guard text.range(of: "^[+-]?[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
    static func previousValue(_ value: Any?) -> Decimal? {
        guard let n = number(value),
              n >= Decimal(string: "0.00000001")!, n <= 999_999_999_999 else { return nil }
        return n
    }
    var displayCurrency: String { AppLanguage.code == "ko" ? "KRW" : "USD" }
    func money(_ amount: Decimal) -> String {
        if currency == displayCurrency { return holdingMoney(amount, currency: displayCurrency) }
        guard let converted = exchange?.convert(amount, from: currency, to: displayCurrency) else { return "—" }
        return holdingMoney(converted, currency: displayCurrency)
    }
    var formatted: String { money(Decimal(string: String(price)) ?? 0) }
    func sourceSummary(symbol: String, failures: Int) -> String {
        let stamp = DateFormatter(); stamp.locale = AppLanguage.locale; stamp.dateFormat = "MM/dd HH:mm"
        let provider = isKoreanStock(symbol) ? "Naver · KRX" : "Yahoo"
        let seconds = Int(pollDelay(symbol: symbol, quote: self, failures: failures))
        let unit = AppLanguage.code == "ko" ? "초" : "s"
        let first = "\(failures > 0 ? "⚠ " : "")\(provider) · \(seconds)\(unit) · \(stamp.string(from: time))"
        return first + (exchangeNote.isEmpty ? "" : "\n" + exchangeNote)
    }
    var exchangeNote: String {
        if currency == displayCurrency { return "" }
        guard let fx = exchange, fx.convert(1, from: currency, to: displayCurrency) != nil else {
            return AppLanguage.code == "ko" ? "환율 확인 불가 · 환산 금액 표시 대기" : "Exchange rate unavailable · Converted value pending"
        }
        let label = AppLanguage.code == "ko" ? "참고 환율" : "Reference FX"
        let old = fx.stale ? (AppLanguage.code == "ko" ? " · 갱신 실패, 이전 환율" : " · Update failed, cached rate") : ""
        return "\(label) \(fx.date) · Frankfurter\(old)"
    }
    static func parse(_ json: [String: Any]) throws -> Quote {
        guard let chart = json["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let meta = results.first?["meta"] as? [String: Any],
              let price = meta["regularMarketPrice"] as? Double, price.isFinite, price > 0, price <= 999_999_999_999,
              let timestamp = meta["regularMarketTime"] as? Double, timestamp.isFinite, timestamp > 0 else { throw MarketError.unavailable }
        var open: Bool? = nil
        if let periods = meta["currentTradingPeriod"] as? [String: Any], let regular = periods["regular"] as? [String: Any],
           let start = regular["start"] as? Double, let end = regular["end"] as? Double {
            let now = Date().timeIntervalSince1970
            open = start <= now && now < end
        }
        return Quote(price: price, currency: meta["currency"] as? String ?? "", time: Date(timeIntervalSince1970: timestamp), sessionOpen: open, previousClose: previousValue(meta["chartPreviousClose"]) ?? previousValue(meta["previousClose"]))
    }
    static func parseNaver(_ json: [String: Any], code: String) throws -> Quote {
        guard let items = json["datas"] as? [[String: Any]],
              let item = items.first(where: { $0["itemCode"] as? String == code }),
              let rawPrice = item["closePrice"] as? String,
              let price = Double(rawPrice.replacingOccurrences(of: ",", with: "")), price.isFinite, price > 0, price <= 999_999_999_999,
              let rawTime = item["localTradedAt"] as? String else { throw MarketError.unavailable }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractionalTime = formatter.date(from: rawTime)
        formatter.formatOptions = [.withInternetDateTime]
        guard let time = fractionalTime ?? formatter.date(from: rawTime) else { throw MarketError.unavailable }
        let isOpen = item["marketStatus"] as? String == "OPEN"
        var previous: Decimal? = nil
        if let raw = item["compareToPreviousClosePrice"] as? String,
           let difference = Self.number(raw),
           abs(difference) <= 999_999_999_999, let current = Decimal(string: String(price)) {
            previous = Self.previousValue(NSDecimalNumber(decimal: current - difference))
        }
        return Quote(price: price, currency: "KRW", time: time, source: "네이버 · KRX", marketStatus: isOpen ? "장중" : "장 마감/거래 대기", sessionOpen: isOpen, previousClose: previous)
    }
}
func isKoreanStock(_ symbol: String) -> Bool {
    symbol.range(of: "^[0-9]{6}\\.(KS|KQ)$", options: .regularExpression) != nil
}
func latestQuote(_ symbol: String) async throws -> Quote {
    if isKoreanStock(symbol) {
        let code = String(symbol.prefix(6))
        let json = try await request("/api/realtime/domestic/stock/" + code, query: [], host: "https://polling.finance.naver.com")
        return try Quote.parseNaver(json, code: code)
    }
    let json = try await request("/v8/finance/chart/" + symbol, query: [URLQueryItem(name: "interval", value: "1d"), URLQueryItem(name: "range", value: "1d")])
    return try Quote.parse(json)
}

func pollDelay(symbol: String, quote: Quote?, failures: Int) -> TimeInterval {
    let base: TimeInterval = isKoreanStock(symbol) ? 7 : 15
    if failures > 0 { return min(300, max(15, base) * pow(2, Double(min(failures, 5)))) }
    return quote?.sessionOpen == false ? 60 : base
}
func parseIdentity(_ json: [String: Any], code: String) throws -> Stock {
    guard json["itemCode"] as? String == code,
          let exchange = json["stockExchangeType"] as? [String: Any],
          let suffix = exchange["code"] as? String, ["KS", "KQ"].contains(suffix) else { throw MarketError.unavailable }
    return Stock(symbol: code + "." + suffix, name: json["stockName"] as? String ?? code)
}
func searchStocks(_ query: String) async throws -> [Stock] {
    if query.range(of: "^[0-9]{6}$", options: .regularExpression) != nil {
        let json = try await request("/api/stock/" + query + "/basic", query: [], host: "https://m.stock.naver.com")
        return [try parseIdentity(json, code: query)]
    }
    let json = try await request("/v1/finance/search", query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "quotesCount", value: "8"), URLQueryItem(name: "newsCount", value: "0")])
    return (json["quotes"] as? [[String: Any]] ?? []).compactMap { item in
        guard let symbol = item["symbol"] as? String, directSymbol(symbol) != nil,
              let type = item["quoteType"] as? String, ["EQUITY", "ETF", "INDEX"].contains(type) else { return nil }
        return Stock(symbol: symbol, name: item["shortname"] as? String ?? item["longname"] as? String ?? symbol)
    }
}
