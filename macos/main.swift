import Cocoa

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
    if q.range(of: "^[0-9]{6}$", options: .regularExpression) != nil { return q + ".KS" }
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
    var formatted: String {
        let formatter = NumberFormatter()
        formatter.locale = AppLanguage.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = currency == "KRW" ? 0 : 2
        formatter.maximumFractionDigits = currency == "KRW" ? 0 : 2
        let prefix = currency == "KRW" ? "₩" : currency == "USD" ? "$" : currency + " "
        return prefix + (formatter.string(from: NSNumber(value: price)) ?? "—")
    }
    static func parse(_ json: [String: Any]) throws -> Quote {
        guard let chart = json["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let meta = results.first?["meta"] as? [String: Any],
              let price = meta["regularMarketPrice"] as? Double, price.isFinite,
              let timestamp = meta["regularMarketTime"] as? Double else { throw MarketError.unavailable }
        return Quote(price: price, currency: meta["currency"] as? String ?? "", time: Date(timeIntervalSince1970: timestamp))
    }
    static func parseNaver(_ json: [String: Any], code: String) throws -> Quote {
        guard let items = json["datas"] as? [[String: Any]],
              let item = items.first(where: { $0["itemCode"] as? String == code }),
              let rawPrice = item["closePrice"] as? String,
              let price = Double(rawPrice.replacingOccurrences(of: ",", with: "")), price.isFinite, price > 0,
              let rawTime = item["localTradedAt"] as? String else { throw MarketError.unavailable }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractionalTime = formatter.date(from: rawTime)
        formatter.formatOptions = [.withInternetDateTime]
        guard let time = fractionalTime ?? formatter.date(from: rawTime) else { throw MarketError.unavailable }
        let isOpen = item["marketStatus"] as? String == "OPEN"
        return Quote(price: price, currency: "KRW", time: time, source: "네이버 · KRX", marketStatus: isOpen ? "장중" : "장 마감/거래 대기")
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
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let status: NSStatusItem = {
        let name = "StockPrice"
        // Seed only our item's first placement; preserve subsequent user dragging.
        // AppKit's persisted position key is not a public positioning API.
        let key = "NSStatusItem Preferred Position " + name
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(0, forKey: key)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = name
        return item
    }()
    let popover = NSPopover()
    let search = NSSearchField(frame: NSRect(x: 14, y: 283, width: 302, height: 28))
    let table = NSTableView()
    let note = NSTextField(labelWithString: L("종목을 검색하고 선택하세요"))
    let sourceLabel = NSTextField(labelWithString: L("국내: 네이버 KRX 7초 · 해외: Yahoo 15초"))
    let symbolCheckbox = NSButton(checkboxWithTitle: L("종목 코드"), target: nil, action: nil)
    let totalCheckbox = NSButton(checkboxWithTitle: L("평가총액 + 수익률로 표시"), target: nil, action: nil)
    let averageField = NSTextField()
    let sharesField = NSTextField()
    let holdingTitle = NSTextField(labelWithString: L("내 보유"))
    let averageLabel = NSTextField(labelWithString: L("평균 매수가"))
    let holdingMessage = NSTextField(labelWithString: L("평단과 수량 입력 후 저장 · 수수료·세금 제외"))
    let saveHoldingButton = NSButton(title: L("저장"), target: nil, action: nil)
    let displayLabel = NSTextField(labelWithString: "")
    let sharesLabel = NSTextField(labelWithString: "")
    let quitButton = NSButton()
    let donateButton = NSButton()
    let languageMenu = NSPopUpButton(frame: NSRect(x: 165, y: 6, width: 100, height: 26), pullsDown: false)
    var holdings: [String: Holding] = {
        guard let data = UserDefaults.standard.data(forKey: "holdings"),
              let saved = try? JSONDecoder().decode([String: Holding].self, from: data) else { return [:] }
        return saved.filter { $0.value.isValid }
    }()
    var showSymbol = (UserDefaults.standard.object(forKey: "showSymbol") as? Bool)
        ?? (UserDefaults.standard.string(forKey: "displayStyle") != "price")
    var lastQuote: Quote?
    var quoteFailed = false
    var results = localSearch("")
    var selected: Stock?
    var quoteTask: Task<Void, Never>?
    var searchTask: Task<Void, Never>?
    var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let data = UserDefaults.standard.data(forKey: "selectedStock"),
           let saved = try? JSONDecoder().decode(Stock.self, from: data), directSymbol(saved.symbol) == saved.symbol { selected = saved }
        status.isVisible = true
        status.button?.target = self
        status.button?.action = #selector(toggle)
        status.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        renderStatus()
        status.button?.toolTip = L("주식 검색 · 클릭하여 종목 선택")
        makePopover()
        scheduleRefresh()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            if selected == nil || CommandLine.arguments.contains("--smoke-test") { toggle() }
            if CommandLine.arguments.contains("--smoke-test") {
                precondition(status.isVisible && status.button?.window != nil)
                precondition((status.button?.bounds.width ?? 0) > 0)
                precondition(popover.isShown)
                if let view = popover.contentViewController?.view,
                   let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/showmethemoney-popover.png"))
                }
                if let window = status.button?.window, let screen = window.screen,
                   let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                    precondition(window.frame.maxX <= left.maxX || window.frame.minX >= right.minX, "Menu item is behind the notch")
                }
                print("SMOKE_OK: visible=\(status.isVisible), title=\(status.button?.title ?? "nil"), frame=\(String(describing: status.button?.window?.frame)), searchShown=\(popover.isShown)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
            }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { toggle() }
        return false
    }
    func makePopover() {
        let vc = NSViewController()
        vc.view = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 445))
        search.frame.origin.y = 403
        search.placeholderString = L("종목명 또는 코드 검색")
        search.delegate = self
        vc.view.addSubview(search)
        let scroll = NSScrollView(frame: NSRect(x: 10, y: 226, width: 310, height: 166))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("stock"))
        column.width = 298
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 34
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(choose)
        scroll.documentView = table
        vc.view.addSubview(scroll)
        displayLabel.font = .systemFont(ofSize: 11)
        displayLabel.frame = NSRect(x: 14, y: 196, width: 100, height: 16)
        vc.view.addSubview(displayLabel)
        symbolCheckbox.frame = NSRect(x: 120, y: 192, width: 100, height: 22)
        symbolCheckbox.state = showSymbol ? .on : .off
        symbolCheckbox.font = .systemFont(ofSize: 11)
        symbolCheckbox.target = self
        symbolCheckbox.action = #selector(changeDisplayMode)
        vc.view.addSubview(symbolCheckbox)
        holdingTitle.frame = NSRect(x: 14, y: 164, width: 302, height: 18)
        holdingTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        holdingTitle.lineBreakMode = .byTruncatingTail
        vc.view.addSubview(holdingTitle)
        averageLabel.frame = NSRect(x: 14, y: 140, width: 142, height: 16)
        averageLabel.font = .systemFont(ofSize: 10)
        vc.view.addSubview(averageLabel)
        sharesLabel.frame = NSRect(x: 162, y: 140, width: 96, height: 16)
        sharesLabel.font = .systemFont(ofSize: 10)
        vc.view.addSubview(sharesLabel)
        averageField.frame = NSRect(x: 14, y: 110, width: 136, height: 26)
        sharesField.frame = NSRect(x: 162, y: 110, width: 88, height: 26)
        averageField.placeholderString = L("예: 250000")
        sharesField.placeholderString = L("예: 10")
        for field in [averageField, sharesField] {
            field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            field.target = self
            field.action = #selector(saveHolding)
            vc.view.addSubview(field)
        }
        averageField.setAccessibilityLabel(L("평균 매수가, 종목 통화 기준"))
        sharesField.setAccessibilityLabel(L("보유 수량, 주"))
        saveHoldingButton.frame = NSRect(x: 260, y: 108, width: 58, height: 30)
        saveHoldingButton.bezelStyle = .rounded
        saveHoldingButton.target = self
        saveHoldingButton.action = #selector(saveHolding)
        vc.view.addSubview(saveHoldingButton)
        totalCheckbox.frame = NSRect(x: 14, y: 80, width: 302, height: 22)
        totalCheckbox.font = .systemFont(ofSize: 11)
        totalCheckbox.target = self
        totalCheckbox.action = #selector(changeTotalMode)
        vc.view.addSubview(totalCheckbox)
        holdingMessage.frame = NSRect(x: 14, y: 60, width: 302, height: 16)
        holdingMessage.font = .systemFont(ofSize: 9)
        holdingMessage.textColor = .secondaryLabelColor
        vc.view.addSubview(holdingMessage)
        loadHoldingFields()
        note.frame = NSRect(x: 14, y: 28, width: 302, height: 28)
        note.font = .systemFont(ofSize: 10)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 2
        note.lineBreakMode = .byTruncatingTail
        vc.view.addSubview(note)
        sourceLabel.font = .systemFont(ofSize: 9)
        sourceLabel.textColor = .tertiaryLabelColor
        sourceLabel.frame = NSRect(x: 14, y: 11, width: 250, height: 14)
        vc.view.addSubview(sourceLabel)
        let quit = quitButton
        quit.target = self
        quit.action = #selector(quitApp)
        quit.bezelStyle = .inline
        quit.frame = NSRect(x: 275, y: 8, width: 42, height: 20)
        vc.view.addSubview(quit)
        // Keep support links in a separate footer, away from price settings.
        for view in vc.view.subviews { view.frame.origin.y += 30 }
        vc.view.frame.size.height += 30
        quit.frame.origin.y = 8
        let donate = donateButton
        donate.target = self
        donate.action = #selector(openDonation)
        donate.bezelStyle = .inline
        donate.font = .systemFont(ofSize: 11)
        donate.frame = NSRect(x: 14, y: 8, width: 144, height: 22)
        donate.isEnabled = donationURL != nil
        donate.toolTip = donationURL == nil ? L("후원 링크 준비 중") : L("브라우저에서 개발자 후원 페이지 열기")
        vc.view.addSubview(donate)
        languageMenu.addItems(withTitles: ["한국어", "English"])
        languageMenu.target = self
        languageMenu.action = #selector(changeLanguage)
        languageMenu.setAccessibilityLabel("Language / 언어")
        vc.view.addSubview(languageMenu)
        popover.contentViewController = vc
        popover.behavior = .transient
        applyLanguage()
        if CommandLine.arguments.contains("--smoke-test") {
            vc.view.appearance = NSAppearance(named: .aqua)
            vc.view.wantsLayer = true
            vc.view.layer?.backgroundColor = NSColor.white.cgColor
        }
    }
    @objc func toggle() {
        guard let button = status.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        search.window?.makeFirstResponder(search)
    }
    @objc func quitApp() { NSApp.terminate(nil) }
    @objc func changeLanguage() {
        AppLanguage.code = languageMenu.indexOfSelectedItem == 0 ? "ko" : "en"
        UserDefaults.standard.set(AppLanguage.code, forKey: "language")
        applyLanguage()
    }
    func applyLanguage() {
        languageMenu.selectItem(at: AppLanguage.code == "ko" ? 0 : 1)
        search.placeholderString = L("종목명 또는 코드 검색")
        displayLabel.stringValue = L("가격에 추가 표시")
        symbolCheckbox.title = L("종목 코드")
        totalCheckbox.title = L("평가총액 + 수익률로 표시")
        sharesLabel.stringValue = L("보유 수량 (주)")
        saveHoldingButton.title = L("저장")
        quitButton.title = L("종료")
        donateButton.title = L("♡ 개발자 후원하기")
        donateButton.toolTip = donationURL == nil ? L("후원 링크 준비 중") : L("브라우저에서 개발자 후원 페이지 열기")
        averageField.placeholderString = L("예: 250000")
        sharesField.placeholderString = L("예: 10")
        averageField.setAccessibilityLabel(L("평균 매수가, 종목 통화 기준"))
        sharesField.setAccessibilityLabel(L("보유 수량, 주"))
        updateHoldingLabels()
        holdingMessage.stringValue = holdingMessage.textColor == .systemRed
            ? L("평단·수량은 0보다 큰 숫자로 입력하세요 (소수 8자리까지)")
            : L("평단과 수량 입력 후 저장 · 수수료·세금 제외")
        table.reloadData()
        sourceLabel.stringValue = L("국내: 네이버 KRX 7초 · 해외: Yahoo 15초")
        note.stringValue = L("종목을 검색하고 선택하세요")
        status.button?.toolTip = L("주식 검색 · 클릭하여 종목 선택")
        renderStatus()
        updateQuoteLabels()
    }
    func updateHoldingLabels() {
        holdingTitle.stringValue = selected.map { "\(L("내 보유")) · \($0.displayName) (\($0.symbol))" } ?? L("종목을 먼저 선택하세요")
        averageLabel.stringValue = selected.map { isKoreanStock($0.symbol) ? L("평균 매수가 (원)") : L("평균 매수가 (종목 통화)") } ?? L("평균 매수가")
    }
    func updateQuoteLabels() {
        if let quote = lastQuote, let stock = selected {
            sourceLabel.stringValue = isKoreanStock(stock.symbol) ? "\(L("네이버 · KRX · 7초 갱신")) · \(L(quote.marketStatus))" : L("Yahoo · 15초 갱신 · 지연 가능")
            if search.stringValue.isEmpty { note.stringValue = "\(stock.displayName) · \(quote.formatted)\n\(L("시세 기준")) \(quoteDate(quote.time))" }
        }
        if quoteFailed { note.stringValue = L("조회 실패 · 종목 코드와 인터넷 연결을 확인하세요") }
    }
    var donationURL: URL? {
        guard let text = Bundle.main.object(forInfoDictionaryKey: "DonationURL") as? String,
              let url = URL(string: text), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
    @objc func openDonation() {
        guard let url = donationURL else { return }
        popover.performClose(nil)
        NSWorkspace.shared.open(url)
    }
    func loadHoldingFields() {
        let saved = selected.flatMap { holdings[$0.symbol] }
        updateHoldingLabels()
        averageField.stringValue = saved.map { NSDecimalNumber(decimal: $0.averageCost).stringValue } ?? ""
        sharesField.stringValue = saved.map { NSDecimalNumber(decimal: $0.shares).stringValue } ?? ""
        averageField.isEnabled = selected != nil
        sharesField.isEnabled = selected != nil
        saveHoldingButton.isEnabled = selected != nil
        totalCheckbox.isEnabled = selected != nil
        totalCheckbox.state = saved?.showTotal == true ? .on : .off
        holdingMessage.stringValue = L("평단과 수량 입력 후 저장 · 수수료·세금 제외")
        holdingMessage.textColor = .secondaryLabelColor
    }
    func storeHoldings() {
        if let data = try? JSONEncoder().encode(holdings) { UserDefaults.standard.set(data, forKey: "holdings") }
    }
    @discardableResult func saveHoldingValues(showTotal: Bool) -> Bool {
        guard let stock = selected else { return false }
        guard let average = Holding.positiveNumber(averageField.stringValue),
              let shares = Holding.positiveNumber(sharesField.stringValue),
              Holding(averageCost: average, shares: shares, showTotal: showTotal).isValid else {
            holdingMessage.stringValue = L("평단·수량은 0보다 큰 숫자로 입력하세요 (소수 8자리까지)")
            holdingMessage.textColor = .systemRed
            return false
        }
        holdings[stock.symbol] = Holding(averageCost: average, shares: shares, showTotal: showTotal)
        storeHoldings()
        holdingMessage.stringValue = L("저장됨 · 종목 통화 기준 · 수수료·세금 제외")
        holdingMessage.textColor = .secondaryLabelColor
        renderStatus()
        return true
    }
    @objc func saveHolding() { saveHoldingValues(showTotal: totalCheckbox.state == .on) }
    @objc func changeTotalMode() {
        if totalCheckbox.state == .on {
            if !saveHoldingValues(showTotal: true) { totalCheckbox.state = .off }
        } else if let stock = selected, var saved = holdings[stock.symbol] {
            saved.showTotal = false
            holdings[stock.symbol] = saved
            storeHoldings()
            renderStatus()
        }
    }
    @objc func changeDisplayMode() {
        showSymbol = symbolCheckbox.state == .on
        UserDefaults.standard.set(showSymbol, forKey: "showSymbol")
        renderStatus()
    }
    func renderStatus() {
        status.button?.image = nil
        guard let stock = selected else { status.button?.title = L("주식"); return }
        var price = lastQuote?.formatted ?? "—"
        if let holding = holdings[stock.symbol], holding.showTotal {
            if let quote = lastQuote, let result = holding.valuation(price: quote.price) {
                price = "\(holdingMoney(result.total, currency: quote.currency)) (\(holdingPercent(result.percent)))"
            } else { price = L("평가 —") }
        }
        let text = showSymbol ? "\(stock.symbol) \(price)" : price
        status.button?.title = text + (quoteFailed ? " ⚠" : "")
        if let quote = lastQuote {
            let time = quoteDate(quote.time)
            var tip = "\(stock.displayName) (\(stock.symbol)) · \(L("현재가")) \(quote.formatted)\n\(L(quote.source)) · \(L("시세 기준")) \(time)"
            if let holding = holdings[stock.symbol], let result = holding.valuation(price: quote.price) {
                tip += "\n\(L("평가금액")) \(holdingMoney(result.total, currency: quote.currency)) · \(L("손익")) \(holdingMoney(result.profit, currency: quote.currency)) (\(holdingPercent(result.percent)))\n\(L("수수료·세금 제외"))"
            }
            if quoteFailed { tip += L("\n⚠ 조회 실패 · 마지막 성공 시세") }
            status.button?.toolTip = tip
        }
    }
    @objc func woke() { refresh() }
    func scheduleRefresh() {
        timer?.invalidate()
        let interval: TimeInterval = selected.map { isKoreanStock($0.symbol) ? 7 : 15 } ?? 15
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 0.5
    }
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let stock = results[row]
        let label = NSTextField(labelWithString: "\(stock.displayName)  ·  \(stock.symbol)")
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        return label
    }
    func controlTextDidChange(_ obj: Notification) {
        searchTask?.cancel()
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        results = localSearch(query)
        if let symbol = directSymbol(query), !results.contains(where: { $0.symbol == symbol }) { results.append(Stock(symbol: symbol, name: "코드로 선택")) }
        table.reloadData()
        guard !query.isEmpty else { return }
        note.stringValue = L("검색 중…")
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                let json = try await request("/v1/finance/search", query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "quotesCount", value: "8"), URLQueryItem(name: "newsCount", value: "0")])
                try Task.checkCancellation()
                for item in json["quotes"] as? [[String: Any]] ?? [] {
                    guard let symbol = item["symbol"] as? String, directSymbol(symbol) != nil,
                          let type = item["quoteType"] as? String, ["EQUITY", "ETF", "INDEX"].contains(type),
                          !results.contains(where: { $0.symbol == symbol }) else { continue }
                    results.append(Stock(symbol: symbol, name: item["shortname"] as? String ?? item["longname"] as? String ?? symbol))
                }
                table.reloadData()
                note.stringValue = results.isEmpty ? L("검색 결과 없음 · 코스닥은 코드.KQ로 입력") : L("종목을 선택하면 상단에 현재가가 표시됩니다")
            } catch {
                if !Task.isCancelled { note.stringValue = L("온라인 검색 실패 · 종목 코드를 직접 입력할 수 있습니다") }
            }
        }
    }
    @objc func choose() {
        let row = table.selectedRow
        guard results.indices.contains(row) else { return }
        selected = results[row]
        UserDefaults.standard.set(try? JSONEncoder().encode(selected), forKey: "selectedStock")
        searchTask?.cancel()
        quoteTask?.cancel()
        quoteTask = nil
        lastQuote = nil
        quoteFailed = false
        loadHoldingFields()
        renderStatus()
        scheduleRefresh()
        status.button?.toolTip = L("시세 확인 중")
        popover.performClose(nil)
        refresh()
    }
    func refresh() {
        guard let stock = selected, quoteTask == nil else { return }
        quoteTask = Task {
            defer { if !Task.isCancelled { quoteTask = nil } }
            do {
                let quote = try await latestQuote(stock.symbol)
                try Task.checkCancellation()
                lastQuote = quote
                quoteFailed = false
                renderStatus()
                updateQuoteLabels()
            } catch {
                guard !Task.isCancelled else { return }
                quoteFailed = true
                renderStatus()
                status.button?.toolTip = L("조회 실패 · 표시된 가격은 마지막 성공 시세입니다")
                note.stringValue = L("조회 실패 · 종목 코드와 인터넷 연결을 확인하세요")
            }
        }
    }
}
if CommandLine.arguments.contains("--self-test") {
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
