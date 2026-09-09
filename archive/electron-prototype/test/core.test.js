const { test } = require('node:test');
const assert = require('node:assert/strict');
const { DEFAULTS, normalizeSymbol, validateSettings, parseQuote, fetchQuote, priceText } = require('../src/core');
test('Korean codes default to KOSPI; explicit KOSDAQ and US symbols are retained', () => {
  assert.equal(normalizeSymbol('005930'), '005930.KS');
  assert.equal(normalizeSymbol('086520.kq'), '086520.KQ');
  assert.equal(normalizeSymbol(' aapl '), 'AAPL');
  assert.throws(() => normalizeSymbol('<script>'));
  assert.throws(() => normalizeSymbol(''));
});
test('settings reject invalid selections, empty lists and aggressive polling', () => {
  assert.deepEqual(validateSettings(DEFAULTS), DEFAULTS);
  assert.throws(() => validateSettings({ ...DEFAULTS, symbols: [] }));
  assert.throws(() => validateSettings({ ...DEFAULTS, selected: 'MSFT' }));
  assert.throws(() => validateSettings({ ...DEFAULTS, interval: 1 }));
});
const payload = { chart: { result: [{ meta: { regularMarketPrice: 110, chartPreviousClose: 100, regularMarketTime: 1700000000, currency: 'USD' } }] } };
test('quotes use provider time and previous close; missing prices never become zero', () => {
  const quote = parseQuote('AAPL', payload);
  assert.equal(quote.change, 10); assert.equal(quote.marketTime, 1700000000000); assert.equal(priceText(quote), '$110');
  assert.throws(() => parseQuote('BAD', { chart: { result: null } }));
  assert.equal(priceText({}), '—');
  const missingClose = structuredClone(payload); delete missingClose.chart.result[0].meta.chartPreviousClose;
  assert.equal(parseQuote('AAPL', missingClose).change, null);
});
test('HTTP failures and throttling are surfaced instead of fabricated prices', async () => {
  await assert.rejects(fetchQuote('AAPL', async () => ({ ok: false, status: 429 })), /조회 제한/);
  const result = await fetchQuote('AAPL', async url => { assert.match(url, /chart\/AAPL/); return { ok: true, json: async () => payload }; });
  assert.equal(result.price, 110);
});
