using System.Text.Json;

int count = 0;
void Check(bool result, string name) { if (!result) throw new Exception("FAIL: " + name); count++; }
void Reject(Action action, string name) { try { action(); } catch { count++; return; } throw new Exception("FAIL: " + name); }
Check(Market.Symbol("005930") == "005930.KS", "KOSPI normalization");
Check(Market.Symbol("086520.kq") == "086520.KQ", "KOSDAQ normalization");
Check(Market.Symbol("<script>") is null, "invalid symbol");
Check(Market.Local("Samsung").Any(s => s.Symbol == "005930.KS") && Market.Local("삼성").Any(s => s.Symbol == "005930.KS"), "bilingual name search");
Check(Market.Interval("005930.KS") == 7000 && Market.Interval("AAPL") == 15000, "provider polling intervals");
using var naver = JsonDocument.Parse("""{"datas":[{"itemCode":"005930","closePrice":"271,000","localTradedAt":"2026-09-09T13:44:06.932264+09:00","marketStatus":"OPEN"}]}""");
var kr = Market.ParseNaver(naver.RootElement, "005930") with { Exchange = new(new() { ["USD"]=1, ["KRW"]=1000, ["EUR"]=0.8m, ["GBP"]=0.5m }, "2026-09-09") };
Check(kr.Price == 271000 && kr.Currency == "KRW" && kr.Naver && kr.Open, "Naver price and source");
Check(kr.Time.ToUnixTimeSeconds() == 1788929046, "provider timestamp (not fetch time)");
Reject(() => Market.ParseNaver(naver.RootElement, "000660"), "reject mismatched symbol");
using var invalid = JsonDocument.Parse("""{"datas":[{"itemCode":"005930","closePrice":"0","localTradedAt":"bad","marketStatus":"OPEN"}]}""");
Reject(() => Market.ParseNaver(invalid.RootElement, "005930"), "invalid quote");
using var yahoo = JsonDocument.Parse("""{"chart":{"result":[{"meta":{"regularMarketPrice":123.45,"currency":"USD","regularMarketTime":1700000000}}]}}""");
var us = Market.ParseYahoo(yahoo.RootElement);
Check(us.Price == 123.45m && !us.Naver && us.Time.ToUnixTimeSeconds() == 1700000000, "Yahoo quote");
var holding = new Holding(250000, 10, true);
Check(holding.Value(270000) == (2700000m, 200000m, 8m), "positive return");
Check(holding.Value(225000) == (2250000m, -250000m, -10m), "negative return");
Check(new Holding(100.25m, 0.5m, true).Value(110.25m).Total == 55.125m, "fractional shares");
Check(Holding.Number("250,000") == 250000 && Holding.Number("0.5") == 0.5m, "numeric input");
Check(Holding.Number("0") is null && Holding.Number("-1") is null && Holding.Number("NaN") is null && Holding.Number("1.123456789") is null, "invalid position inputs");
Reject(() => new Holding(0, 10, true).Value(100), "zero cost rejected");
var settings = new Settings { Selected = Market.Catalog[0], ShowSymbol = false, Holdings = new() { ["005930.KS"] = holding } };
Lang.Code = "en";
Check(Format.Ticker(settings, kr with { Price = 270000 }, false) == "$2,700.00 (+8.00%)", "total display");
Check(Format.Ticker(settings, null, true) == "Value — ⚠", "missing quote not zero");
Check(Format.Ticker(settings, kr, true).EndsWith(" ⚠"), "failure indicator");
settings.Holdings["005930.KS"] = holding with { ShowTotal = false };
Check(Format.Ticker(settings, kr, false) == "$271.00", "price-only mode");
settings.ShowSymbol = true;
Check(Format.Ticker(settings, kr, false).StartsWith("005930.KS "), "symbol option");
settings.Selected = new Stock("AAPL", "애플 Apple");
Check(Format.Ticker(settings, us, false) == "AAPL $123.45", "positions remain per symbol");
Check(Format.Detail(settings, us, false).Contains("Apple") && !Format.Detail(settings, us, false).Contains("삼성"), "English display");
Lang.Code = "ko";
Check(Format.Detail(settings, us, false).Contains("현재가"), "Korean display");
var directory = Path.Combine(Path.GetTempPath(), "showmethemoney-tests-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(directory);
try
{
    File.WriteAllText(Path.Combine(directory, "selected.json"), JsonSerializer.Serialize(new Stock("005930.KS", "삼성전자")));
    Check(SettingsStore.Load(directory).Selected?.Symbol == "005930.KS", "migration from original Windows version");
    settings.Language = "en";
    SettingsStore.Save(directory, settings);
    var loaded = SettingsStore.Load(directory);
    Check(loaded.Selected?.Symbol == "AAPL" && loaded.Language == "en" && loaded.ShowSymbol, "settings persistence");
    Check(loaded.Holdings["005930.KS"].Shares == 10 && !loaded.Holdings["005930.KS"].ShowTotal, "position persistence");
    var copy = loaded.Copy(); copy.Holdings.Clear();
    Check(loaded.Holdings.Count == 1, "draft does not mutate saved positions");
    Check(Donation.Read(directory) is null, "missing donation link");
    File.WriteAllText(Path.Combine(directory, "donation.json"), """{"url":"javascript:alert(1)"}""");
    Check(Donation.Read(directory) is null, "non-HTTPS donation rejected");
    File.WriteAllText(Path.Combine(directory, "donation.json"), """{"url":"https://buymeacoffee.com/example"}""");
    Check(Donation.Read(directory)?.Host == "buymeacoffee.com", "valid donation link");
    File.WriteAllText(Path.Combine(directory, "settings.json"), "broken");
    Check(SettingsStore.Load(directory).Selected is null, "corrupt settings recover");
}
finally { Directory.Delete(directory, true); }
if (args.Contains("--live"))
{
    var quote = await Market.Latest("005930.KS", CancellationToken.None);
    Check(quote.Naver && quote.Price > 0, "actual Naver request");
    Console.WriteLine($"LIVE: price={quote.Price} quoteTime={quote.Time:O} ageSeconds={(DateTimeOffset.UtcNow - quote.Time).TotalSeconds:F0}");
}
Console.WriteLine($"PASS: {count} Windows core checks (quotes, positions, localization, migration, persistence, donation)");
Check(Market.Symbol("086520") == "086520.KQ", "bare known KOSDAQ code");
Check(Market.Symbol("123456") is null, "unknown bare code must resolve exchange");
using var identity = JsonDocument.Parse("""{"itemCode":"123456","stockName":"Example","stockExchangeType":{"code":"KQ"}}""");
Check(Market.ParseIdentity(identity.RootElement,"123456").Symbol == "123456.KQ", "provider resolves unknown KOSDAQ code");
Reject(() => Market.ParseIdentity(identity.RootElement,"000000"), "reject mismatched identity");
Check(Market.PollDelay("005930.KS", kr, 0) == 7000, "open market polling");
Check(Market.PollDelay("005930.KS", kr with { Open=false }, 0) == 60000, "closed market polling");
Check(Market.PollDelay("AAPL", us, 0) == 15000, "unknown session retains normal polling");
Check(Market.PollDelay("AAPL", us, 1) == 30000 && Market.PollDelay("AAPL", us, 2) == 60000 && Market.PollDelay("AAPL", us, 100) == 300000, "bounded retry backoff");
Check(Market.PollDelay("AAPL", us, 0) == 15000, "successful request resets delay");
using var zeroYahoo = JsonDocument.Parse("""{"chart":{"result":[{"meta":{"regularMarketPrice":0,"regularMarketTime":1700000000}}]}}""");
Reject(() => Market.ParseYahoo(zeroYahoo.RootElement), "zero Yahoo price rejected");
Console.WriteLine($"PASS: {count} total Windows core checks");

var fx = kr.Exchange!;
Check(fx.Convert(100, "USD", "KRW") == 100000, "USD to KRW");
Check(fx.Convert(100000, "KRW", "USD") == 100, "KRW to USD");
Check(fx.Convert(80, "EUR", "KRW") == 100000, "cross currency conversion");
Check(fx.Convert(100, "GBp", "USD") == 2, "pence normalized before FX");
Lang.Code = "ko";
Check((us with { Exchange = fx }).Formatted == "₩123,450", "Korean language converts US stock");
Check(us.Formatted == "—" && us.ExchangeNote.Contains("환율"), "missing FX never relabels raw price");
Check(kr.Formatted == "₩271,000", "native currency unchanged");
Lang.Code = "en";
Check(kr.Formatted == "$271.00", "English converts Korean stock");
Check((kr with { Exchange = fx with { Stale = true } }).ExchangeNote.Contains("cached"), "cached rate warning");
Check(fx.Convert(1,"UNKNOWN","USD") is null, "unsupported currency");
using var fxJson = JsonDocument.Parse("""{"base":"USD","date":"2026-09-09","rates":{"KRW":1000,"EUR":0.8}}""");
Check(ExchangeRates.Parse(fxJson.RootElement).Convert(80,"EUR","USD")==100, "FX response parsed");
using var badFx = JsonDocument.Parse("""{"base":"USD","date":"2026-09-09","rates":{"KRW":0}}""");
Reject(()=>ExchangeRates.Parse(badFx.RootElement),"zero FX rejected");
Console.WriteLine($"PASS: {count} total checks including FX");
var fxPath = Path.Combine(Path.GetTempPath(), "smtm-fx-" + Guid.NewGuid().ToString("N"), "rates.json");
try {
    ExchangeStore.Save(fx, fxPath);
    var restoredFx = ExchangeStore.Load(fxPath);
    Check(restoredFx is { Stale: true } && restoredFx.Date == fx.Date && restoredFx.Convert(100,"USD","KRW") == 100000, "FX survives restart and is marked cached");
    File.WriteAllText(fxPath, "broken");
    Check(ExchangeStore.Load(fxPath) is null, "corrupt persisted FX ignored");
    File.WriteAllText(fxPath, """{"base":"USD","date":"2026-09-09","rates":{"KRW":0}}""");
    Check(ExchangeStore.Load(fxPath) is null, "invalid persisted rates rejected");
} finally { if (Directory.Exists(Path.GetDirectoryName(fxPath))) Directory.Delete(Path.GetDirectoryName(fxPath)!,true); }
Lang.Code="en";
var summary = kr.SourceSummary("005930.KS",0);
Check(summary.Contains("Naver") && summary.Contains("7s") && summary.Contains("Reference FX") && summary.Contains("\n"), "quote and FX both visible");
Check(kr.SourceSummary("005930.KS",2).Contains("60s") && kr.SourceSummary("005930.KS",2).Contains("Reference FX"), "quote failure retains FX and shows retry interval");
Check((kr with { Open=false }).SourceSummary("005930.KS",0).Contains("60s"), "closed interval displayed");
Console.WriteLine($"PASS: {count} total checks including persistent FX and source summary");
