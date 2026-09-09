function render(state) {
  const q = state.quotes[state.settings.selected];
  const value = Number.isFinite(q?.price) ? q.price.toLocaleString('ko-KR', { maximumFractionDigits: q.currency === 'KRW' ? 0 : 2 }) : '—';
  const currency = q?.currency === 'KRW' ? '₩' : q?.currency === 'USD' ? '$' : q?.currency || '';
  const ticker = document.getElementById('ticker');
  ticker.textContent = `${state.settings.selected}  ${currency}${value}${q?.error ? ' ⚠' : ''}`;
  ticker.title = q?.error || (q?.marketTime ? `시세 기준 ${new Date(q.marketTime).toLocaleString('ko-KR')} · 클릭하여 열기` : '시세 수신 대기');
}
document.getElementById('ticker').onclick = () => window.stocks.open();
window.stocks.subscribe(render);
window.stocks.getState().then(render);
