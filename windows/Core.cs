using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

static class Lang
{
    internal static string Code { get; set; } = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ko" ? "ko" : "en";
    internal static CultureInfo Culture => CultureInfo.GetCultureInfo(Code == "ko" ? "ko-KR" : "en-US");
    internal static string T(string ko, string en) => Code == "ko" ? ko : en;
}
record Stock(string Symbol, string Name)
{
    internal string DisplayName => Lang.Code == "en" ? Market.EnglishNames.GetValueOrDefault(Symbol, Name == "코드로 선택" ? "Use this symbol" : Name) : Name;
    public override string ToString() => $"{DisplayName} · {Symbol}";
}
record Holding(decimal AverageCost, decimal Shares, bool ShowTotal)
{
    internal bool Valid => AverageCost >= 0.00000001m && Shares >= 0.00000001m && decimal.Round(AverageCost, 8) == AverageCost && decimal.Round(Shares, 8) == Shares && AverageCost <= 999999999999m && Shares <= 999999999999m;
    internal (decimal Total, decimal Profit, decimal Percent) Value(decimal price)
    {
        if (!Valid || price <= 0 || price > 999999999999m) throw new InvalidDataException();
        return (price * Shares, (price - AverageCost) * Shares, (price - AverageCost) / AverageCost * 100);
    }
    internal static decimal? Number(string text)
    {
        var value = text.Trim().Replace(",", "");
        return Regex.IsMatch(value, @"^[0-9]{1,12}(\.[0-9]{1,8})?$") && decimal.TryParse(value, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var n) && n > 0 && n <= 999999999999m ? n : null;
    }
}
record Quote(decimal Price, string Currency, DateTimeOffset Time, bool Naver, bool Open, bool SessionKnown = false)
{
    internal string Source => (SessionKnown && !Open ? Lang.T("장 종료 · 60초 갱신 · ", "Closed · 60s · ") : "") + (Naver ? Lang.T("네이버 · KRX", "Naver · KRX") : Lang.T("Yahoo · 지연 가능", "Yahoo · May be delayed"));
    internal ExchangeRates? Exchange { get; init; }
    internal string DisplayCurrency => Lang.Code == "ko" ? "KRW" : "USD";
    internal string Money(decimal amount) {
        if (Currency == DisplayCurrency) return Format.Money(amount, DisplayCurrency);
        var converted = Exchange?.Convert(amount, Currency, DisplayCurrency);
        return converted is decimal value ? Format.Money(value, DisplayCurrency) : "—";
    }
    internal string ExchangeNote => Currency == DisplayCurrency ? "" : Exchange?.Convert(1, Currency, DisplayCurrency) is null
        ? Lang.T("환율 확인 불가 · 환산 금액 표시 대기", "Exchange rate unavailable · Converted value pending")
        : Lang.T("참고 환율 ", "Reference FX ") + Exchange.Date + " · Frankfurter" + (Exchange.Stale ? Lang.T(" · 갱신 실패, 이전 환율", " · Update failed, cached rate") : "");
    internal string SourceSummary(string symbol, int failures) {
        var first = (failures > 0 ? "⚠ " : "") + (Naver ? "Naver · KRX" : "Yahoo") + " · "
            + (Market.PollDelay(symbol, this, failures) / 1000) + Lang.T("초", "s") + " · " + Time.LocalDateTime.ToString("MM/dd HH:mm", Lang.Culture);
        return first + (ExchangeNote.Length == 0 ? "" : "\n" + ExchangeNote);
    }
    internal string Formatted => Money(Price);
}
static class Format
{
    internal static string Money(decimal n, string currency) => (currency == "KRW" ? "₩" : currency == "USD" ? "$" : currency + " ") + n.ToString(currency == "KRW" ? "N0" : "N2", Lang.Culture);
    internal static string Percent(decimal n) => (n > 0 ? "+" : "") + n.ToString("F2", CultureInfo.InvariantCulture) + "%";
    internal static string Ticker(Settings settings, Quote? quote, bool failed)
    {
        if (settings.Selected is not Stock stock) return Lang.T("주식 검색", "Search stocks");
        var text = quote?.Formatted ?? "—";
        if (settings.Holdings.TryGetValue(stock.Symbol, out var holding) && holding.ShowTotal)
        {
            if (quote is null) text = Lang.T("평가 —", "Value —");
            else { var value = holding.Value(quote.Price); text = $"{quote.Money(value.Total)} ({Percent(value.Percent)})"; }
        }
        return (settings.ShowSymbol ? stock.Symbol + " " : "") + text + (failed ? " ⚠" : "");
    }
    internal static string Detail(Settings settings, Quote? quote, bool failed)
    {
        if (settings.Selected is not Stock stock) return Lang.T("종목을 검색하고 선택하세요", "Search and select a stock");
        var text = stock.ToString();
        if (quote is not null)
        {
            text += $"\n{Lang.T("현재가", "Price")} {quote.Formatted} · {quote.Source}\n{Lang.T("시세 기준", "As of")} {quote.Time.LocalDateTime.ToString("G", Lang.Culture)}";
            if (quote.ExchangeNote.Length > 0) text += "\n" + quote.ExchangeNote;
            if (quote.Naver) text += " · " + (quote.Open ? Lang.T("장중", "Open") : Lang.T("장 마감/대기", "Closed/waiting"));
            if (settings.Holdings.TryGetValue(stock.Symbol, out var holding))
            {
                var value = holding.Value(quote.Price);
                text += $"\n{Lang.T("평가금액", "Value")} {quote.Money(value.Total)} · {Lang.T("손익", "P/L")} {quote.Money(value.Profit)} ({Percent(value.Percent)})\n{Lang.T("수수료·세금 제외", "Fees/taxes excluded")}";
            }
        }
        if (failed) text += "\n" + Lang.T("조회 실패 · 마지막 성공 시세", "Update failed · Last available quote");
        return text;
    }
}
sealed class Settings
{
    public Stock? Selected { get; set; }
    public bool ShowSymbol { get; set; } = true;
    public string Language { get; set; } = Lang.Code;
    public Dictionary<string, Holding> Holdings { get; set; } = new();
    internal Settings Copy() => new() { Selected = Selected, ShowSymbol = ShowSymbol, Language = Language, Holdings = new(Holdings) };
}
static class SettingsStore
{
    internal static Settings Load(string directory)
    {
        try
        {
            var path = Path.Combine(directory, "settings.json");
            Settings settings;
            if (File.Exists(path)) settings = JsonSerializer.Deserialize<Settings>(File.ReadAllText(path)) ?? new();
            else settings = new() { Selected = JsonSerializer.Deserialize<Stock>(File.ReadAllText(Path.Combine(directory, "selected.json"))) };
            if (settings.Selected is Stock s && Market.Symbol(s.Symbol) != s.Symbol) settings.Selected = null;
            if (settings.Language is not ("ko" or "en")) settings.Language = Lang.Code;
            settings.Holdings = (settings.Holdings ?? new()).Where(p => p.Value is not null && p.Value.Valid && Market.Symbol(p.Key) == p.Key).ToDictionary(p => p.Key, p => p.Value);
            return settings;
        }
        catch { return new(); }
    }
    internal static void Save(string directory, Settings settings)
    {
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "settings.json");
        File.WriteAllText(path + ".tmp", JsonSerializer.Serialize(settings, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(path + ".tmp", path, true);
    }
}
static class Donation
{
    internal static Uri? Read(string directory)
    {
        try
        {
            using var json = JsonDocument.Parse(File.ReadAllText(Path.Combine(directory, "donation.json")));
            var text = json.RootElement.GetProperty("url").GetString();
            return Uri.TryCreate(text, UriKind.Absolute, out var url) && url.Scheme == "https" && url.Host.Length > 0 && url.UserInfo.Length == 0 ? url : null;
        }
        catch { return null; }
    }
}
static class Market
{
    internal static readonly Stock[] Catalog = [
        new("005930.KS", "삼성전자"), new("000660.KS", "SK하이닉스"), new("035420.KS", "네이버 NAVER"), new("035720.KS", "카카오"),
        new("005380.KS", "현대차"), new("373220.KS", "LG에너지솔루션"), new("086520.KQ", "에코프로"), new("247540.KQ", "에코프로비엠"),
        new("AAPL", "애플 Apple"), new("NVDA", "엔비디아 NVIDIA"), new("TSLA", "테슬라 Tesla"), new("MSFT", "마이크로소프트 Microsoft"),
        new("GOOGL", "알파벳 Google"), new("AMZN", "아마존 Amazon")
    ];
    internal static readonly Dictionary<string, string> EnglishNames = new() {
        ["005930.KS"]="Samsung Electronics", ["000660.KS"]="SK Hynix", ["035420.KS"]="NAVER", ["035720.KS"]="Kakao", ["005380.KS"]="Hyundai Motor",
        ["373220.KS"]="LG Energy Solution", ["086520.KQ"]="EcoPro", ["247540.KQ"]="EcoPro BM", ["AAPL"]="Apple", ["NVDA"]="NVIDIA",
        ["TSLA"]="Tesla", ["MSFT"]="Microsoft", ["GOOGL"]="Alphabet", ["AMZN"]="Amazon"
    };
    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(10) };
    static Market() => Http.DefaultRequestHeaders.UserAgent.ParseAdd("ShowMeTheMoney/1.0");
    internal static string? Symbol(string? query)
    {
        var q = (query ?? "").Trim().ToUpperInvariant();
        if (Regex.IsMatch(q, @"^[0-9]{6}$")) return Catalog.FirstOrDefault(s => s.Symbol.StartsWith(q + ".", StringComparison.Ordinal))?.Symbol;
        return Regex.IsMatch(q, @"^[A-Z0-9^][A-Z0-9.^=-]{0,19}$") ? q : null;
    }
    internal static bool Korean(string symbol) => Regex.IsMatch(symbol, @"^[0-9]{6}\.(KS|KQ)$");
    internal static int Interval(string? symbol) => symbol is not null && Korean(symbol) ? 7000 : 15000;
    internal static List<Stock> Local(string q) => Catalog.Where(s => s.Name.Contains(q, StringComparison.OrdinalIgnoreCase) || s.Symbol.Contains(q, StringComparison.OrdinalIgnoreCase) || EnglishNames.GetValueOrDefault(s.Symbol, "").Contains(q, StringComparison.OrdinalIgnoreCase)).ToList();
    internal static int PollDelay(string? symbol, Quote? quote, int failures)
    {
        if (failures > 0) return (int)Math.Min(300000, Math.Max(15000, Interval(symbol)) * Math.Pow(2, Math.Min(failures, 5)));
        return quote is { SessionKnown: true, Open: false } ? 60000 : Interval(symbol);
    }
    internal static Stock ParseIdentity(JsonElement root, string code)
    {
        if (root.GetProperty("itemCode").GetString() != code) throw new InvalidDataException();
        var exchange = root.GetProperty("stockExchangeType").GetProperty("code").GetString();
        if (exchange is not ("KS" or "KQ")) throw new InvalidDataException("Unsupported exchange");
        return new(code + "." + exchange, root.GetProperty("stockName").GetString() ?? code);
    }
    static async Task<JsonDocument> Get(string url, CancellationToken token)
    {
        using var message = new HttpRequestMessage(HttpMethod.Get, url);
        message.Headers.CacheControl = new() { NoCache = true };
        using var response = await Http.SendAsync(message, token);
        response.EnsureSuccessStatusCode();
        return JsonDocument.Parse(await response.Content.ReadAsStringAsync(token));
    }
    internal static Quote ParseYahoo(JsonElement root)
    {
        var meta = root.GetProperty("chart").GetProperty("result")[0].GetProperty("meta");
        var price = meta.GetProperty("regularMarketPrice").GetDecimal();
        ValidatePrice(price);
        return new(price, meta.TryGetProperty("currency", out var c) ? c.GetString() ?? "" : "", DateTimeOffset.FromUnixTimeSeconds(meta.GetProperty("regularMarketTime").GetInt64()), false, TradingOpen(meta), meta.TryGetProperty("currentTradingPeriod", out var period) && period.TryGetProperty("regular", out _));
    }
    static bool TradingOpen(JsonElement meta)
    {
        if (!meta.TryGetProperty("currentTradingPeriod", out var periods) || !periods.TryGetProperty("regular", out var regular)) return false;
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        return regular.GetProperty("start").GetInt64() <= now && now < regular.GetProperty("end").GetInt64();
    }
    internal static Quote ParseNaver(JsonElement root, string code)
    {
        var item = root.GetProperty("datas").EnumerateArray().First(x => x.GetProperty("itemCode").GetString() == code);
        var price = decimal.Parse(item.GetProperty("closePrice").GetString()!.Replace(",", ""), CultureInfo.InvariantCulture);
        ValidatePrice(price);
        var time = DateTimeOffset.Parse(item.GetProperty("localTradedAt").GetString()!, CultureInfo.InvariantCulture);
        return new(price, "KRW", time, true, item.GetProperty("marketStatus").GetString() == "OPEN", true);
    }
    static void ValidatePrice(decimal price) { if (price <= 0 || price > 999999999999m) throw new InvalidDataException("Invalid quote"); }
    internal static async Task<Quote> Latest(string symbol, CancellationToken token)
    {
        if (Korean(symbol))
        {
            using var json = await Get("https://polling.finance.naver.com/api/realtime/domestic/stock/" + symbol[..6], token);
            return ParseNaver(json.RootElement, symbol[..6]);
        }
        using var yahoo = await Get("https://query1.finance.yahoo.com/v8/finance/chart/" + Uri.EscapeDataString(symbol) + "?interval=1d&range=1d", token);
        return ParseYahoo(yahoo.RootElement);
    }
    internal static async Task<List<Stock>> Search(string query, CancellationToken token)
    {
        if (Regex.IsMatch(query.Trim(), @"^[0-9]{6}$"))
        {
            var code = query.Trim();
            using var identity = await Get("https://m.stock.naver.com/api/stock/" + code + "/basic", token);
            return [ParseIdentity(identity.RootElement, code)];
        }
        using var json = await Get("https://query1.finance.yahoo.com/v1/finance/search?q=" + Uri.EscapeDataString(query) + "&quotesCount=8&newsCount=0", token);
        var stocks = new List<Stock>();
        foreach (var item in json.RootElement.GetProperty("quotes").EnumerateArray())
        {
            if (!item.TryGetProperty("symbol", out var s) || !item.TryGetProperty("quoteType", out var t)) continue;
            var symbol = s.GetString();
            if (symbol is null || Symbol(symbol) is null || t.GetString() is not ("EQUITY" or "ETF" or "INDEX")) continue;
            stocks.Add(new(symbol, item.TryGetProperty("shortname", out var n) ? n.GetString() ?? symbol : symbol));
        }
        return stocks;
    }
}

record ExchangeRates(Dictionary<string, decimal> Rates, string Date, bool Stale = false)
{
    internal decimal? Convert(decimal amount, string currency, string target) {
        var minor = currency is "GBp" or "GBX";
        var source = minor ? "GBP" : currency.ToUpperInvariant();
        if (minor) amount /= 100;
        if (source == target) return amount;
        if (!Rates.TryGetValue(source, out var from) || !Rates.TryGetValue(target, out var to) || from <= 0 || to <= 0) return null;
        try { return amount / from * to; } catch (OverflowException) { return null; }
    }
    internal static ExchangeRates Parse(JsonElement root) {
        if (root.GetProperty("base").GetString() != "USD") throw new InvalidDataException();
        var date = root.GetProperty("date").GetString() ?? "";
        if (!DateOnly.TryParseExact(date, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out _)) throw new InvalidDataException();
        var rates = new Dictionary<string, decimal> { ["USD"] = 1 };
        foreach (var item in root.GetProperty("rates").EnumerateObject()) {
            var rate = item.Value.GetDecimal();
            if (rate <= 0 || rate >= 1000000000) throw new InvalidDataException();
            rates[item.Name] = rate;
        }
        if (!rates.ContainsKey("KRW")) throw new InvalidDataException();
        return new(rates, date);
    }
}
static class ExchangeStore
{
    internal static string FilePath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ShowMeTheMoney", "exchange-rates.json");
    internal static ExchangeRates? Load(string? path = null) {
        try { using var json = JsonDocument.Parse(File.ReadAllText(path ?? FilePath)); return ExchangeRates.Parse(json.RootElement) with { Stale = true }; }
        catch { return null; }
    }
    internal static void Save(ExchangeRates rates, string? path = null) {
        path ??= FilePath;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path + ".tmp", JsonSerializer.Serialize(new { @base = "USD", date = rates.Date, rates = rates.Rates }));
        File.Move(path + ".tmp", path, true);
    }
}
static class ExchangeCache
{
    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(10) };
    static readonly SemaphoreSlim Gate = new(1, 1);
    static ExchangeRates? cached = ExchangeStore.Load();
    static DateTimeOffset nextFetch;
    internal static async Task<ExchangeRates?> Latest(CancellationToken token) {
        await Gate.WaitAsync(token);
        try {
            if (DateTimeOffset.UtcNow < nextFetch) return cached;
            try {
                using var response = await Http.GetAsync("https://api.frankfurter.dev/v1/latest?base=USD", token);
                response.EnsureSuccessStatusCode();
                using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(token));
                cached = ExchangeRates.Parse(json.RootElement);
                try { ExchangeStore.Save(cached); } catch { /* Disk cache is optional; retain the valid in-memory result. */ }
                nextFetch = DateTimeOffset.UtcNow.AddHours(1);
            } catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
            catch { if (cached is not null) cached = cached with { Stale = true }; nextFetch = DateTimeOffset.UtcNow.AddMinutes(5); }
            return cached;
        } finally { Gate.Release(); }
    }
}
