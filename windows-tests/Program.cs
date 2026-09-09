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
var kr = Market.ParseNaver(naver.RootElement, "005930");
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
Check(Format.Ticker(settings, kr with { Price = 270000 }, false) == "₩2,700,000 (+8.00%)", "total display");
Check(Format.Ticker(settings, null, true) == "Value — ⚠", "missing quote not zero");
Check(Format.Ticker(settings, kr, true).EndsWith(" ⚠"), "failure indicator");
settings.Holdings["005930.KS"] = holding with { ShowTotal = false };
Check(Format.Ticker(settings, kr, false) == "₩271,000", "price-only mode");
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
