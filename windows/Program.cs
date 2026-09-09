using System.Diagnostics;
using static Lang;

sealed class SearchForm : Form
{
    readonly TextBox search = new() { Dock = DockStyle.Fill };
    readonly ListBox list = new() { Dock = DockStyle.Fill, IntegralHeight = false, BorderStyle = BorderStyle.None };
    readonly Label quoteLabel = new() { Dock = DockStyle.Fill, AutoEllipsis = true };
    readonly Label holdingTitle = new() { Dock = DockStyle.Fill, AutoEllipsis = true };
    readonly Label averageLabel = new() { AutoSize = true };
    readonly Label sharesLabel = new() { AutoSize = true };
    readonly TextBox average = new() { Dock = DockStyle.Fill };
    readonly TextBox shares = new() { Dock = DockStyle.Fill };
    readonly CheckBox symbol = new() { Dock = DockStyle.Fill };
    readonly CheckBox total = new() { Dock = DockStyle.Fill };
    readonly Button save = new() { Dock = DockStyle.Fill };
    readonly Label message = new() { Dock = DockStyle.Fill, AutoEllipsis = true };
    readonly Label sourceLabel = new() { Dock = DockStyle.Fill, AutoEllipsis = true, ForeColor = SystemColors.GrayText };
    readonly Button donate = new() { Dock = DockStyle.Fill, FlatStyle = FlatStyle.Flat };
    readonly ComboBox language = new() { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList };
    readonly Button quit = new() { Dock = DockStyle.Fill };
    readonly ToolTip tips = new();
    readonly Func<Settings> state;
    readonly Func<Settings, bool> commit;
    readonly Func<Stock, bool> choose;
    readonly Uri? donation;
    CancellationTokenSource? pending;
    bool binding;
    Quote? lastQuote;
    bool failed;

    public SearchForm(Func<Settings> state, Func<Settings, bool> commit, Func<Stock, bool> choose, Action exit)
    {
        this.state = state; this.commit = commit; this.choose = choose;
        donation = Donation.Read(AppContext.BaseDirectory);
        AutoScaleMode = AutoScaleMode.Dpi;
        Font = new Font("Segoe UI", 10);
        ClientSize = new Size(420, 610);
        FormBorderStyle = FormBorderStyle.FixedToolWindow;
        ShowInTaskbar = false; TopMost = true;
        var root = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(12), ColumnCount = 1, RowCount = 10 };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        foreach (var height in new float[] { 34, -1, 44, 28, 24, 66, 28, 34, 34, 36 })
            root.RowStyles.Add(new RowStyle(height < 0 ? SizeType.Percent : SizeType.Absolute, height < 0 ? 100 : height));
        root.Controls.Add(search, 0, 0); root.Controls.Add(list, 0, 1); root.Controls.Add(quoteLabel, 0, 2);
        root.Controls.Add(symbol, 0, 3); root.Controls.Add(holdingTitle, 0, 4);
        var inputs = new TableLayoutPanel { Dock = DockStyle.Fill, Margin = Padding.Empty, ColumnCount = 3, RowCount = 2 };
        inputs.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 52)); inputs.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 28)); inputs.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 20));
        inputs.RowStyles.Add(new RowStyle(SizeType.Absolute, 24)); inputs.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        inputs.Controls.Add(averageLabel, 0, 0); inputs.Controls.Add(sharesLabel, 1, 0);
        inputs.Controls.Add(average, 0, 1); inputs.Controls.Add(shares, 1, 1); inputs.Controls.Add(save, 2, 1);
        root.Controls.Add(inputs, 0, 5); root.Controls.Add(total, 0, 6); root.Controls.Add(message, 0, 7); root.Controls.Add(sourceLabel, 0, 8);
        var footer = new TableLayoutPanel { Dock = DockStyle.Fill, Margin = Padding.Empty, ColumnCount = 3, RowCount = 1 };
        foreach (float percent in new[] { 48f, 32f, 20f }) footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, percent));
        footer.Controls.Add(donate, 0, 0); footer.Controls.Add(language, 1, 0); footer.Controls.Add(quit, 2, 0);
        root.Controls.Add(footer, 0, 9); Controls.Add(root);
        language.Items.AddRange(["한국어", "English"]);
        donate.Enabled = donation is not null;
        donate.Click += (_, _) => {
            if (donation is null) return;
            try { Process.Start(new ProcessStartInfo(donation.AbsoluteUri) { UseShellExecute = true }); }
            catch { Error(T("브라우저를 열 수 없습니다", "Could not open your browser")); }
        };
        quit.Click += (_, _) => exit();
        search.TextChanged += async (_, _) => await Search();
        list.MouseClick += (_, e) => { if (list.IndexFromPoint(e.Location) >= 0) SelectStock(); };
        list.KeyDown += (_, e) => { if (e.KeyCode == Keys.Enter) SelectStock(); };
        search.KeyDown += (_, e) => {
            if (e.KeyCode == Keys.Down && list.Items.Count > 0) { list.Focus(); list.SelectedIndex = 0; e.Handled = true; }
            if (e.KeyCode == Keys.Enter && list.Items.Count > 0) { list.SelectedIndex = 0; SelectStock(); e.SuppressKeyPress = true; }
        };
        save.Click += (_, _) => SaveHolding(total.Checked);
        foreach (var field in new[] { average, shares }) field.KeyDown += (_, e) => { if (e.KeyCode == Keys.Enter) { SaveHolding(total.Checked); e.SuppressKeyPress = true; } };
        symbol.CheckedChanged += (_, _) => { if (binding) return; var next = state().Copy(); next.ShowSymbol = symbol.Checked; if (!commit(next)) SetChecked(symbol, state().ShowSymbol); };
        total.CheckedChanged += (_, _) => {
            if (binding) return;
            if (total.Checked) { if (!SaveHolding(true)) SetChecked(total, false); }
            else if (state().Selected is Stock stock && state().Holdings.TryGetValue(stock.Symbol, out var holding)) {
                var next = state().Copy(); next.Holdings[stock.Symbol] = holding with { ShowTotal = false };
                if (!commit(next)) SetChecked(total, true);
            }
        };
        language.SelectedIndexChanged += (_, _) => {
            if (binding) return;
            var next = state().Copy(); next.Language = language.SelectedIndex == 0 ? "ko" : "en";
            if (!commit(next)) ApplyLanguage();
        };
        Deactivate += (_, _) => DismissIfInactive();
        language.DropDownClosed += (_, _) => DismissIfInactive();
        KeyPreview = true;
        KeyDown += (_, e) => { if (e.KeyCode == Keys.Escape) { Hide(); e.Handled = true; } };
        FormClosing += (_, e) => { if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); } };
        VisibleChanged += (_, _) => { if (!Visible) pending?.Cancel(); };
        Fill(Market.Local("")); LoadHolding(); ApplyLanguage();
    }
    void DismissIfInactive()
    {
        if (!IsHandleCreated || IsDisposed) return;
        BeginInvoke(new Action(() => {
            if (!IsDisposed && Visible && !language.DroppedDown && ActiveForm != this) Hide();
        }));
    }
    void SetChecked(CheckBox checkbox, bool value) { binding = true; checkbox.Checked = value; binding = false; }
    public void Error(string text) { message.ForeColor = Color.Firebrick; message.Text = text; }
    bool SaveHolding(bool showTotal)
    {
        if (state().Selected is not Stock stock) return false;
        var a = Holding.Number(average.Text); var s = Holding.Number(shares.Text);
        if (a is null || s is null) { Error(T("평단·수량은 0보다 큰 숫자로 입력하세요 (소수 8자리까지)", "Enter positive cost and shares (up to 8 decimals)")); return false; }
        var next = state().Copy(); next.Holdings[stock.Symbol] = new(a.Value, s.Value, showTotal);
        if (!commit(next)) return false;
        message.ForeColor = SystemColors.GrayText;
        message.Text = T("저장됨 · 종목 통화 기준 · 수수료·세금 제외", "Saved · Stock currency · Fees/taxes excluded");
        return true;
    }
    public void LoadHolding()
    {
        var settings = state();
        Holding? holding = settings.Selected is Stock stock ? settings.Holdings.GetValueOrDefault(stock.Symbol) : null;
        average.Text = holding?.AverageCost.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "";
        shares.Text = holding?.Shares.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "";
        average.Enabled = shares.Enabled = save.Enabled = total.Enabled = settings.Selected is not null;
        SetChecked(total, holding?.ShowTotal == true);
        message.Text = T("평단과 수량 입력 후 저장 · 수수료·세금 제외", "Save cost and shares · Fees/taxes excluded");
        message.ForeColor = SystemColors.GrayText;
        UpdateHoldingLabels();
    }
    void UpdateHoldingLabels()
    {
        var selected = state().Selected;
        holdingTitle.Text = selected is null ? T("종목을 먼저 선택하세요", "Select a stock first") : T("내 보유 · ", "My holding · ") + selected;
        averageLabel.Text = selected is not null && Market.Korean(selected.Symbol) ? T("평균 매수가 (원)", "Average cost (KRW)") : T("평단 (종목 통화)", "Cost (stock currency)");
    }
    public void ApplyLanguage()
    {
        binding = true;
        Text = T("주식 검색", "Stock search"); search.PlaceholderText = T("종목명 또는 코드 검색", "Search name or symbol");
        symbol.Text = T("종목 코드 표시", "Show symbol"); symbol.Checked = state().ShowSymbol;
        total.Text = T("평가총액 + 수익률로 표시", "Show holding value + return");
        sharesLabel.Text = T("보유 수량 (주)", "Shares"); save.Text = T("저장", "Save"); quit.Text = T("종료", "Quit");
        average.PlaceholderText = T("예: 250000", "e.g. 250000"); shares.PlaceholderText = T("예: 10", "e.g. 10");
        average.AccessibleName = T("평균 매수가, 종목 통화 기준", "Average cost in stock currency"); shares.AccessibleName = T("보유 수량", "Number of shares");
        donate.Text = T("♡ 개발자 후원하기", "♡ Buy me a coffee");
        tips.SetToolTip(donate, donation is null ? T("후원 링크 준비 중", "Support link coming soon") : donation.AbsoluteUri);
        language.SelectedIndex = Code == "ko" ? 0 : 1;
        UpdateHoldingLabels();
        if (message.ForeColor != Color.Firebrick) message.Text = T("평단과 수량 입력 후 저장 · 수수료·세금 제외", "Save cost and shares · Fees/taxes excluded");
        else message.Text = T("입력값이나 설정 저장 상태를 확인하세요", "Check your inputs or settings storage");
        var items = list.Items.Cast<Stock>().ToArray(); Fill(items);
        UpdateQuote(lastQuote, failed);
        binding = false;
    }
    public void UpdateQuote(Quote? quote, bool failed)
    {
        lastQuote = quote; this.failed = failed;
        var settings = state();
        quoteLabel.Text = settings.Selected is null ? T("종목을 검색하고 선택하세요", "Search and select a stock") : Format.Ticker(settings, quote, failed);
        tips.SetToolTip(quoteLabel, Format.Detail(settings, quote, failed));
        if (quote is not null) averageLabel.Text = T("평단 (입력: ", "Cost (input: ") + quote.Currency + ")";
        sourceLabel.Text = quote is null ? T("국내: 네이버 KRX 7초 · 해외: Yahoo 15초", "KRX: Naver 7s · Other: Yahoo 15s") : quote.Source + "\n" + T("시세 기준 ", "As of ") + quote.Time.LocalDateTime.ToString("G", Culture);
        if (quote is not null && quote.ExchangeNote.Length > 0) sourceLabel.Text = quote.ExchangeNote;
        if (failed) sourceLabel.Text = T("조회 실패 · 마지막 성공 시세", "Update failed · Last available quote") + (quote is null ? "" : "\n" + quote.Time.LocalDateTime.ToString("G", Culture));
    }
    void Fill(IEnumerable<Stock> stocks) { list.BeginUpdate(); list.Items.Clear(); foreach (var stock in stocks) list.Items.Add(stock); list.ClearSelected(); list.EndUpdate(); }
    void SelectStock() { if (list.SelectedItem is Stock stock && choose(stock)) { pending?.Cancel(); Hide(); } }
    async Task Search()
    {
        pending?.Cancel(); var source = new CancellationTokenSource(); pending = source; var token = source.Token;
        var q = search.Text.Trim(); var stocks = Market.Local(q);
        if (Market.Symbol(q) is string sym && !stocks.Any(s => s.Symbol == sym)) stocks.Add(new(sym, "코드로 선택"));
        Fill(stocks);
        try
        {
            if (q.Length == 0) { UpdateQuote(lastQuote, failed); return; }
            quoteLabel.Text = T("검색 중…", "Searching…");
            await Task.Delay(350, token);
            var remote = await Market.Search(q, token); token.ThrowIfCancellationRequested();
            foreach (var stock in remote) if (!stocks.Any(s => s.Symbol == stock.Symbol)) stocks.Add(stock);
            Fill(stocks);
            quoteLabel.Text = stocks.Count == 0 ? T("검색 결과 없음 · 코드로 입력해보세요", "No results · Try a symbol") : T("종목을 선택하세요", "Select a stock");
        }
        catch { if (!token.IsCancellationRequested && !IsDisposed) quoteLabel.Text = T("온라인 검색 실패 · 코드로 직접 선택할 수 있습니다", "Search unavailable · Enter a symbol directly"); }
        finally { if (pending == source) pending = null; source.Dispose(); }
    }
    public void Open()
    {
        var area = Screen.FromPoint(Cursor.Position).WorkingArea;
        StartPosition = FormStartPosition.Manual;
        Location = new Point(Math.Max(area.Left, area.Right - Width - 12), Math.Max(area.Top, area.Bottom - Height - 50));
        Show(); Activate(); search.Focus(); search.SelectAll();
    }
    protected override void Dispose(bool disposing) { if (disposing) { pending?.Cancel(); tips.Dispose(); } base.Dispose(disposing); }
}

sealed class StockApp : ApplicationContext
{
    readonly NotifyIcon tray;
    readonly Form ticker = new() { FormBorderStyle = FormBorderStyle.None, ShowInTaskbar = false, TopMost = true, BackColor = Color.FromArgb(30, 34, 31), ClientSize = new Size(250, 34), AutoScaleMode = AutoScaleMode.Dpi };
    readonly Label price = new() { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter, ForeColor = Color.White, Cursor = Cursors.Hand, Font = new Font("Segoe UI", 10), AutoEllipsis = true };
    readonly ToolTip tooltip = new();
    readonly System.Windows.Forms.Timer timer = new();
    readonly SearchForm search;
    readonly Icon appIcon;
    readonly string directory;
    Settings settings;
    Quote? quote;
    bool failed, exiting;
    int failures;
    CancellationTokenSource? request;
    public StockApp(string? testDirectory = null)
    {
        directory = testDirectory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ShowMeTheMoney");
        settings = SettingsStore.Load(directory); Code = settings.Language;
        appIcon = File.Exists(Path.Combine(AppContext.BaseDirectory, "AppIcon.ico")) ? new Icon(Path.Combine(AppContext.BaseDirectory, "AppIcon.ico")) : (Icon)SystemIcons.Information.Clone();
        tray = new NotifyIcon { Icon = appIcon, Visible = true };
        search = new SearchForm(() => settings, Commit, Select, () => ExitThread());
        ticker.Controls.Add(price); ticker.Icon = appIcon; search.Icon = appIcon;
        price.Click += (_, _) => search.Open();
        tray.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) search.Open(); };
        timer.Tick += async (_, _) => await Refresh();
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += DisplayChanged;
        Microsoft.Win32.SystemEvents.PowerModeChanged += PowerChanged;
        ticker.DpiChanged += (_, _) => Render();
        SetMenu(); Render();
        timer.Interval = Market.Interval(settings.Selected?.Symbol); timer.Start();
        _ = search.Handle;
        search.BeginInvoke(new Action(() => {
            if (settings.Selected is not null) { ticker.Show(); _ = Refresh(); } else search.Open();
        }));
        if (testDirectory is not null)
        {
            var smoke = new System.Windows.Forms.Timer { Interval = 1500 };
            smoke.Tick += (_, _) => {
                smoke.Stop(); smoke.Dispose();
                Directory.CreateDirectory(directory);
                File.WriteAllText(Path.Combine(directory, "result.txt"), search.IsHandleCreated && tray.Visible ? "SMOKE_OK: WinForms search window and tray initialized" : "SMOKE_FAILED");
                ExitThread();
            };
            smoke.Start();
        }
    }
    void DisplayChanged(object? sender, EventArgs e) {
        if (!exiting && search.IsHandleCreated) search.BeginInvoke(new Action(() => { if (!exiting) Render(); }));
    }
    void PowerChanged(object sender, Microsoft.Win32.PowerModeChangedEventArgs e) {
        if (e.Mode == Microsoft.Win32.PowerModes.Resume && !exiting && search.IsHandleCreated)
            search.BeginInvoke(new Action(() => { if (!exiting) _ = Refresh(); }));
    }
    bool Commit(Settings next)
    {
        try { SettingsStore.Save(directory, next); }
        catch { search.Error(T("설정을 저장하지 못했습니다. 폴더 권한을 확인하세요", "Could not save settings. Check folder permissions.")); return false; }
        var languageChanged = settings.Language != next.Language;
        settings = next; Code = settings.Language;
        if (languageChanged) { search.ApplyLanguage(); SetMenu(); }
        Render(); return true;
    }
    bool Select(Stock stock)
    {
        var next = settings.Copy(); next.Selected = stock;
        // Save before replacing the live state, then cancel any previous-symbol request.
        try { SettingsStore.Save(directory, next); }
        catch { search.Error(T("설정 저장 실패", "Could not save settings")); return false; }
        request?.Cancel(); request = null; settings = next; quote = null; failed = false; failures = 0;
        search.LoadHolding(); Render(); ticker.Show();
        timer.Interval = Market.Interval(stock.Symbol);
        _ = Refresh(); return true;
    }
    void SetMenu()
    {
        var old = tray.ContextMenuStrip; var menu = new ContextMenuStrip();
        menu.Items.Add(T("주식 검색", "Search stocks"), null, (_, _) => search.Open());
        menu.Items.Add(T("종료", "Quit"), null, (_, _) => ExitThread());
        tray.ContextMenuStrip = menu; old?.Dispose();
    }
    void Render()
    {
        price.Text = Format.Ticker(settings, quote, failed);
        var detail = Format.Detail(settings, quote, failed);
        tray.Text = detail.Length > 127 ? detail[..127] : detail;
        tooltip.SetToolTip(price, detail);
        search.UpdateQuote(quote, failed);
        var area = Screen.FromControl(ticker).WorkingArea;
        ticker.Width = Math.Min(Math.Max(1, area.Width - 8), Math.Max(160, TextRenderer.MeasureText(price.Text, price.Font).Width + 28));
        ticker.Location = new Point(Math.Max(area.Left, area.Right - ticker.Width - 4), Math.Max(area.Top, area.Bottom - ticker.Height - 4));
    }
    async Task Refresh()
    {
        if (exiting || settings.Selected is not Stock stock || request is not null) return;
        timer.Stop();
        var source = new CancellationTokenSource(); request = source;
        try
        {
            var result = await Market.Latest(stock.Symbol, source.Token);
            result = result with { Exchange = await ExchangeCache.Latest(source.Token) };
            source.Token.ThrowIfCancellationRequested();
            if (exiting) return;
            quote = result; failed = false; failures = 0; Render();
        }
        catch { if (!source.IsCancellationRequested && !exiting) { failed = true; failures = Math.Min(failures + 1, 5); Render(); } }
        finally {
            if (request == source) {
                request = null;
                if (!exiting) { timer.Interval = Market.PollDelay(stock.Symbol, quote, failures); timer.Start(); }
            }
            source.Dispose();
        }
    }
    protected override void ExitThreadCore()
    {
        exiting = true;
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged -= DisplayChanged;
        Microsoft.Win32.SystemEvents.PowerModeChanged -= PowerChanged;
        timer.Stop(); timer.Dispose(); request?.Cancel();
        tray.Visible = false; tray.ContextMenuStrip?.Dispose(); tray.Dispose();
        search.Dispose(); ticker.Dispose(); tooltip.Dispose(); appIcon.Dispose();
        base.ExitThreadCore();
    }
}
static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        using var mutex = new Mutex(true, "Local\\ShowMeTheMoney.Native", out var first);
        if (!first) return;
        ApplicationConfiguration.Initialize();
        Application.Run(new StockApp(args.Contains("--smoke-test") ? Path.Combine(Path.GetTempPath(), "ShowMeTheMoney-smoke") : null));
    }
}
