const DEFAULTS = { symbols: ['005930.KS', 'AAPL', 'NVDA'], selected: '005930.KS', interval: 60, widget: true };

function normalizeSymbol(input) {
  const symbol = String(input || '').trim().toUpperCase();
  if (/^\d{6}$/.test(symbol)) return `${symbol}.KS`;
  if (!/^[A-Z0-9^][A-Z0-9.^=-]{0,19}$/.test(symbol)) throw new Error('종목 코드를 확인하세요. 예: AAPL, 005930.KS, 035720.KS');
  return symbol;
}

function validateSettings(input) {
  if (!Array.isArray(input.symbols) || input.symbols.length < 1 || input.symbols.length > 12) throw new Error('관심 종목은 1~12개까지 등록할 수 있습니다.');
  const symbols = [...new Set(input.symbols.map(normalizeSymbol))];
  const selected = normalizeSymbol(input.selected);
  if (!symbols.includes(selected)) throw new Error('대표 종목은 관심 목록에 있어야 합니다.');
  if (![30, 60, 120, 300].includes(input.interval)) throw new Error('갱신 주기를 확인하세요.');
  return { symbols, selected, interval: input.interval, widget: Boolean(input.widget) };
}

function parseQuote(symbol, payload) {
  const meta = payload?.chart?.result?.[0]?.meta;
  if (payload?.chart?.error || !meta || !Number.isFinite(meta.regularMarketPrice) || !Number.isFinite(meta.regularMarketTime)) throw new Error('시세를 찾지 못했습니다. 종목 코드를 확인하세요.');
  const previous = meta.chartPreviousClose ?? meta.previousClose;
  const change = Number.isFinite(previous) && previous > 0 ? (meta.regularMarketPrice - previous) / previous * 100 : null;
  return { symbol, name: meta.shortName || meta.longName || symbol, price: meta.regularMarketPrice, currency: meta.currency || '', change, marketTime: meta.regularMarketTime * 1000, fetchedAt: Date.now(), error: null };
}

async function fetchQuote(symbol, fetcher = fetch) {
  const response = await fetcher(`https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(normalizeSymbol(symbol))}?interval=1d&range=1d`, {
    headers: { 'User-Agent': 'ShowMeTheMoney/1.0', Accept: 'application/json' }, signal: AbortSignal.timeout(12000)
  });
  if (!response.ok) throw new Error(response.status === 429 ? '조회 제한입니다. 잠시 후 다시 시도합니다.' : `시세 서버 오류 (${response.status})`);
  return parseQuote(symbol, await response.json());
}

function priceText(quote) {
  if (!quote || !Number.isFinite(quote.price)) return '—';
  return `${quote.currency === 'KRW' ? '₩' : quote.currency === 'USD' ? '$' : quote.currency + ' '}${quote.price.toLocaleString('ko-KR', { maximumFractionDigits: quote.currency === 'KRW' ? 0 : 2 })}`;
}

module.exports = { DEFAULTS, normalizeSymbol, validateSettings, parseQuote, fetchQuote, priceText };
