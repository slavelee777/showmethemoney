const { app, BrowserWindow, Tray, Menu, nativeImage, ipcMain, screen, powerMonitor } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const { DEFAULTS, validateSettings, fetchQuote, priceText } = require('./core');
let settings = structuredClone(DEFAULTS), quotes = {}, tray, panel, widget, timer, refreshing = false, lastAttempt = null;
let settingsPath;
const smoke = process.argv.includes('--smoke-test');

function state() { return { settings, quotes, refreshing, lastAttempt, platform: process.platform }; }
function icon() {
  const size = 32, bytes = Buffer.alloc(size * size * 4);
  for (let x = 4; x < 28; x++) {
    const top = x < 10 ? 19 : x < 19 ? 12 : 5;
    for (let y = top; y < 27; y++) {
      const i = (y * size + x) * 4;
      bytes[i] = process.platform === 'darwin' ? 0 : 90;
      bytes[i + 1] = process.platform === 'darwin' ? 0 : 220;
      bytes[i + 2] = process.platform === 'darwin' ? 0 : 160;
      bytes[i + 3] = 255;
    }
  }
  const result = nativeImage.createFromBitmap(bytes, { width: size, height: size, scaleFactor: 2 });
  result.setTemplateImage(process.platform === 'darwin');
  return result;
}
function broadcast() {
  for (const win of [panel, widget]) if (win && !win.isDestroyed()) win.webContents.send('state', state());
  if (!tray) return;
  const q = quotes[settings.selected];
  const text = `${settings.selected} ${priceText(q)}${q?.error ? ' ⚠' : ''}`;
  if (process.platform === 'darwin') tray.setTitle(text);
  tray.setToolTip(`${text}\n${q?.error || '클릭하여 관심 종목 보기'}`);
}
async function refresh() {
  if (refreshing) return;
  refreshing = true; lastAttempt = Date.now(); broadcast();
  const symbols = [...settings.symbols];
  await Promise.all(symbols.map(async symbol => {
    try { quotes[symbol] = await fetchQuote(symbol); }
    catch (error) { quotes[symbol] = { ...quotes[symbol], symbol, error: error.message }; }
  }));
  refreshing = false; broadcast();
  // A settings change during a request must also fetch newly added symbols.
  if (settings.symbols.some(symbol => !symbols.includes(symbol))) void refresh();
}
function schedule() { clearInterval(timer); timer = setInterval(refresh, settings.interval * 1000); }
function makeWindow(options, file) {
  const win = new BrowserWindow({ show: false, backgroundColor: '#101613', ...options, webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true } });
  win.setMenu(null);
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', event => event.preventDefault());
  win.loadFile(path.join(__dirname, file));
  return win;
}
function showPanel() {
  if (!panel || panel.isDestroyed()) {
    panel = makeWindow({ width: 460, height: 690, minWidth: 400, minHeight: 560, title: 'Show Me The Money', autoHideMenuBar: true }, 'index.html');
    panel.on('close', event => { if (!app.isQuitting) { event.preventDefault(); panel.hide(); } });
  }
  panel.show(); panel.focus();
}
function syncWidget() {
  if (!settings.widget) { if (widget) widget.hide(); return; }
  if (!widget || widget.isDestroyed()) {
    const { x, y, width, height } = screen.getPrimaryDisplay().workArea;
    widget = makeWindow({ x: x + width - 300, y: y + height - 60, width: 288, height: 48, frame: false, resizable: false, alwaysOnTop: true, skipTaskbar: true }, 'widget.html');
    widget.once('ready-to-show', () => { if (settings.widget) widget.showInactive(); });
  } else widget.showInactive();
}
if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', showPanel);
  app.whenReady().then(() => {
    settingsPath = path.join(app.getPath('userData'), 'settings.json');
    try { settings = validateSettings(JSON.parse(fs.readFileSync(settingsPath, 'utf8'))); } catch { /* First launch or invalid settings: safe defaults. */ }
    if (process.platform === 'darwin') app.dock.hide();
    tray = new Tray(icon());
    tray.on('click', showPanel);
    tray.on('right-click', () => tray.popUpContextMenu(Menu.buildFromTemplate([
      { label: '관심 종목 열기', click: showPanel }, { label: '지금 새로고침', click: refresh },
      { type: 'separator' }, { label: '종료', click: () => app.quit() }
    ])));
    ipcMain.handle('get-state', () => state());
    ipcMain.handle('refresh', async () => { await refresh(); return state(); });
    ipcMain.handle('save-settings', async (_event, input) => {
      const next = validateSettings(input);
      fs.writeFileSync(settingsPath + '.tmp', JSON.stringify(next, null, 2));
      fs.renameSync(settingsPath + '.tmp', settingsPath);
      settings = next; schedule(); syncWidget(); broadcast(); void refresh(); return state();
    });
    ipcMain.on('open-panel', showPanel);
    ipcMain.on('quit', () => app.quit());
    app.on('activate', showPanel);
    powerMonitor.on('resume', refresh);
    schedule(); syncWidget(); showPanel(); void refresh();
    if (smoke) panel.webContents.once('did-finish-load', async () => {
      try {
        const title = await panel.webContents.executeJavaScript('document.title');
        if (title !== 'Show Me The Money') throw new Error('Unexpected title');
        console.log('SMOKE_OK: tray, window, renderer and preload initialized');
        app.quit();
      } catch (error) { console.error(error); app.exit(1); }
    });
  });
}
app.on('window-all-closed', () => {});
app.on('before-quit', () => { app.isQuitting = true; clearInterval(timer); });
