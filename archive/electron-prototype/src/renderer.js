let current;
const $ = id => document.getElementById(id);
function price(q) { return Number.isFinite(q?.price) ? `${q.currency === 'KRW' ? '₩' : q.currency === 'USD' ? '$' : (q.currency || '') + ' '}${q.price.toLocaleString('ko-KR', { maximumFractionDigits: q.currency === 'KRW' ? 0 : 2 })}` : '—'; }
function change(q) { return Number.isFinite(q?.change) ? `${q.change > 0 ? '+' : ''}${q.change.toFixed(2)}% 전일 대비` : '등락률 없음'; }
function tone(q) { return q?.change > 0 ? 'up' : q?.change < 0 ? 'down' : 'neutral'; }
function render(state) {
  current = state;
  const q = state.quotes[state.settings.selected];
  $('selected-symbol').textContent = state.settings.selected;
  $('selected-price').textContent = price(q);
  $('selected-change').textContent = q?.error ? '⚠ ' + q.error : change(q);
  $('selected-change').className = q?.error ? 'neutral' : tone(q);
  $('quote-time').textContent = q?.marketTime ? `시세 기준 ${new Date(q.marketTime).toLocaleString('ko-KR')}${q.error ? ' · 마지막 성공 시세' : ''}` : '시세 수신 대기';
  $('refresh').disabled = state.refreshing;
  $('refresh').textContent = state.refreshing ? '갱신 중…' : '↻ 새로고침';
  $('interval').value = state.settings.interval;
  $('widget').checked = state.settings.widget;
  $('quotes').replaceChildren(...state.settings.symbols.map(symbol => {
    const quote = state.quotes[symbol];
    const row = document.createElement('div'); row.className = 'quote';
    const button = document.createElement('button'); button.className = 'quote-main' + (symbol === state.settings.selected ? ' active' : '');
    button.title = '메뉴 막대의 대표 종목으로 선택'; button.setAttribute('aria-pressed', String(symbol === state.settings.selected));
    const left = document.createElement('span');
    const title = document.createElement('span'); title.className = 'symbol'; title.textContent = symbol;
    const name = document.createElement('span'); name.className = 'name'; name.textContent = quote?.name || '시세 수신 대기';
    left.append(title, name);
    const right = document.createElement('span'); right.className = 'numbers'; right.textContent = price(quote);
    const delta = document.createElement('span'); delta.className = `change ${tone(quote)}`; delta.textContent = quote?.error ? '⚠ 조회 실패' : change(quote); delta.title = quote?.error || '';
    right.append(delta); button.append(left, right); button.onclick = () => save({ selected: symbol });
    const remove = document.createElement('button'); remove.className = 'remove'; remove.textContent = '×'; remove.setAttribute('aria-label', `${symbol} 삭제`); remove.disabled = state.settings.symbols.length === 1;
    remove.onclick = () => { const symbols = current.settings.symbols.filter(s => s !== symbol); save({ symbols, selected: current.settings.selected === symbol ? symbols[0] : current.settings.selected }); };
    row.append(button, remove); return row;
  }));
}
async function save(patch) {
  $('error').textContent = '';
  try { render(await window.stocks.saveSettings({ ...current.settings, ...patch })); return true; }
  catch (error) { $('error').textContent = error.message.replace(/^Error invoking remote method '[^']+': Error: /, ''); render(current); return false; }
}
$('add-form').onsubmit = async event => { event.preventDefault(); if (!current) return; if (await save({ symbols: [...current.settings.symbols, $('symbol').value] })) $('symbol').value = ''; };
$('interval').onchange = event => save({ interval: Number(event.target.value) });
$('widget').onchange = event => save({ widget: event.target.checked });
$('refresh').onclick = () => window.stocks.refresh().catch(error => { $('error').textContent = error.message; });
$('quit').onclick = () => window.stocks.quit();
window.stocks.subscribe(render);
window.stocks.getState().then(render).catch(error => { $('error').textContent = error.message; });
