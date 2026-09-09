import Cocoa

if CommandLine.arguments.contains("--self-test") {
    AppLanguage.code = "en"
    precondition(directSymbol("005930") == "005930.KS")
    precondition(directSymbol("086520.kq") == "086520.KQ")
    precondition(directSymbol("<bad>") == nil)
    precondition(localSearch("삼성").first?.symbol == "005930.KS")
    precondition(localSearch("엔비디아").first?.symbol == "NVDA")
    let fixture: [String: Any] = ["chart": ["result": [["meta": ["regularMarketPrice": 123.45, "regularMarketTime": 1700000000.0, "currency": "USD"]]]]]
    let quote = try Quote.parse(fixture)
    precondition(quote.formatted == "$123.45")
    precondition(quote.time.timeIntervalSince1970 == 1700000000)
    precondition((try? Quote.parse([:])) == nil)
    let naverFixture: [String: Any] = ["datas": [["itemCode": "005930", "closePrice": "271,000", "localTradedAt": "2026-09-09T13:44:06.932264+09:00", "marketStatus": "OPEN"]]]
    let naverQuote = try Quote.parseNaver(naverFixture, code: "005930")
    precondition(naverQuote.price == 271000 && naverQuote.source == "네이버 · KRX")
    precondition(abs(naverQuote.time.timeIntervalSince1970 - 1788929046.932264) < 0.01)
    precondition((try? Quote.parseNaver(naverFixture, code: "000660")) == nil)
    precondition(isKoreanStock("005930.KS") && isKoreanStock("086520.KQ") && !isKoreanStock("AAPL"))
    let position = Holding(averageCost: 250000, shares: 10, showTotal: true)
    let gain = position.valuation(price: 270000)!
    precondition(gain.total == 2700000 && gain.profit == 200000 && gain.percent == 8)
    let loss = position.valuation(price: 225000)!
    precondition(loss.total == 2250000 && loss.profit == -250000 && loss.percent == -10)
    let fractional = Holding(averageCost: Decimal(string: "100.25")!, shares: Decimal(string: "0.5")!, showTotal: true).valuation(price: 110.25)!
    precondition(fractional.total == Decimal(string: "55.125")! && fractional.profit == 5)
    precondition(Holding.positiveNumber("0") == nil && Holding.positiveNumber("-2") == nil && Holding.positiveNumber("NaN") == nil)
    precondition(Holding.positiveNumber("250,000") == 250000)
    precondition(Holding(averageCost: 0, shares: 10, showTotal: true).valuation(price: 100) == nil)
    precondition(position.valuation(price: .infinity) == nil)
    let restored = try JSONDecoder().decode([String: Holding].self, from: JSONEncoder().encode(["005930.KS": position]))
    precondition(restored["005930.KS"]?.showTotal == true && restored["AAPL"] == nil)
    precondition(holdingPercent(gain.percent) == "+8.00%" && holdingPercent(loss.percent) == "-10.00%")
    if let index = CommandLine.arguments.firstIndex(of: "--naver-fixture"), CommandLine.arguments.indices.contains(index + 1) {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1]))) as! [String: Any]
        let live = try Quote.parseNaver(json, code: "005930")
        print("NAVER: \(live.formatted), source=\(live.source), quoteTime=\(live.time), ageSeconds=\(Int(Date().timeIntervalSince(live.time)))")
    }
    precondition(directSymbol("086520") == "086520.KQ")
    precondition(directSymbol("123456") == nil)
    let identity: [String: Any] = ["itemCode": "123456", "stockName": "Example", "stockExchangeType": ["code": "KQ"]]
    let resolved = try parseIdentity(identity, code: "123456")
    precondition(resolved.symbol == "123456.KQ")
    precondition((try? parseIdentity(identity, code: "000000")) == nil)
    precondition(pollDelay(symbol: "005930.KS", quote: naverQuote, failures: 0) == 7)
    var closed = naverQuote; closed.sessionOpen = false
    precondition(pollDelay(symbol: "005930.KS", quote: closed, failures: 0) == 60)
    precondition(pollDelay(symbol: "AAPL", quote: nil, failures: 1) == 30)
    precondition(pollDelay(symbol: "AAPL", quote: nil, failures: 2) == 60)
    precondition(pollDelay(symbol: "AAPL", quote: nil, failures: 100) == 300)
    for bad in [0.0, -1.0, Double.infinity, 1e20] {
        let invalid: [String: Any] = ["chart": ["result": [["meta": ["regularMarketPrice": bad, "regularMarketTime": 1700000000.0]]]]]
        precondition((try? Quote.parse(invalid)) == nil)
    }
    let fx = try ExchangeRates.parse(["base":"USD", "date":"2026-09-09", "rates":["KRW":1000, "EUR":0.8, "GBP":0.5]])
    precondition(fx.convert(100, from: "USD", to: "KRW") == 100000)
    precondition(fx.convert(100000, from: "KRW", to: "USD") == 100)
    precondition(fx.convert(80, from: "EUR", to: "USD") == 100)
    precondition(fx.convert(100, from: "GBp", to: "USD") == 2)
    var converted = quote; converted.exchange = fx
    AppLanguage.code = "ko"
    precondition(converted.formatted == "₩123,450")
    precondition(quote.formatted == "—" && quote.exchangeNote.contains("환율"))
    precondition(naverQuote.formatted == "₩271,000")
    var convertedKR = naverQuote; convertedKR.exchange = fx
    AppLanguage.code = "en"
    precondition(convertedKR.formatted == "$271.00")
    precondition(convertedKR.money(2700000) == "$2,700.00")
    precondition(fx.convert(1, from: "UNKNOWN", to: "USD") == nil)
    precondition((try? ExchangeRates.parse(["base":"USD", "date":"2026-09-09", "rates":["KRW":0]])) == nil)
    let fxFolder = FileManager.default.temporaryDirectory.appendingPathComponent("smtm-fx-" + UUID().uuidString)
    let fxFile = fxFolder.appendingPathComponent("rates.json")
    try ExchangeStore.save(fx, to: fxFile)
    let restoredFX = ExchangeStore.load(from: fxFile)
    precondition(restoredFX?.stale == true && restoredFX?.date == fx.date)
    precondition(restoredFX?.convert(100, from: "USD", to: "KRW") == 100000)
    try Data("broken".utf8).write(to: fxFile)
    precondition(ExchangeStore.load(from: fxFile) == nil)
    try FileManager.default.removeItem(at: fxFolder)
    let summary = convertedKR.sourceSummary(symbol: "005930.KS", failures: 0)
    precondition(summary.contains("Naver") && summary.contains("7s") && summary.contains("Reference FX") && summary.contains("\n"))
    precondition(convertedKR.sourceSummary(symbol: "005930.KS", failures: 2).contains("60s"))
    print("PASS: symbol normalization, Korean search, quote parsing, missing-data rejection")
} else {
    MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--english") { AppLanguage.code = "en" }
    if CommandLine.arguments.contains("--korean") { AppLanguage.code = "ko" }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
    }
}
