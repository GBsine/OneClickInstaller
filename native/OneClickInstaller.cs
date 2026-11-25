using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

[assembly: AssemblyTitle("OneClickInstaller")]
[assembly: AssemblyProduct("OneClickInstaller")]
[assembly: AssemblyCompany("GBsine")]
[assembly: AssemblyDescription("Установщик программ для Windows в один клик (winget)")]
[assembly: AssemblyCopyright("© 2026 GBsine")]
[assembly: AssemblyFileVersion("1.1.0.0")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyInformationalVersion("1.1.0")]

[DataContract]
class AppItem
{
    [DataMember(Name = "id")] public string Id { get; set; }
    [DataMember(Name = "name")] public string Name { get; set; }
    [DataMember(Name = "category")] public string Category { get; set; }
    [DataMember(Name = "desc")] public string Desc { get; set; }
    [DataMember(Name = "desc_en")] public string DescEn { get; set; }
}

[DataContract]
class Settings
{
    [DataMember(Name = "selected")] public List<string> Selected { get; set; }
    [DataMember(Name = "silent")] public bool Silent { get; set; }
    [DataMember(Name = "lang")] public string Lang { get; set; }
}

[DataContract]
class ExportDoc
{
    [DataMember(Name = "Sources")] public List<ExportSource> Sources { get; set; }
}

[DataContract]
class ExportSource
{
    [DataMember(Name = "Packages")] public List<ExportPackage> Packages { get; set; }
}

[DataContract]
class ExportPackage
{
    [DataMember(Name = "PackageIdentifier")] public string Id { get; set; }
}

class RunResult
{
    public int Code;
    public string Output;
}

static class Paths
{
    public static readonly string DataDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OneClickInstaller");
    public static readonly string Settings = Path.Combine(DataDir, "settings.json");
    public static readonly string Logs = Path.Combine(DataDir, "logs");
}

static class L
{
    public static string Lang = "ru";

    static readonly Dictionary<string, Dictionary<string, string>> S = new Dictionary<string, Dictionary<string, string>>();

    static readonly Dictionary<string, string> CatsEn = new Dictionary<string, string>
    {
        { "Браузеры", "Browsers" },
        { "Мессенджеры", "Messengers" },
        { "Медиа", "Media" },
        { "Утилиты", "Utilities" },
        { "Игры", "Games" },
        { "Разработка", "Development" },
        { "Компоненты", "Components" },
        { "Удалённый доступ", "Remote access" }
    };

    static L()
    {
        var ru = new Dictionary<string, string>
        {
            { "form.title", "OneClickInstaller — установка программ" },
            { "title", "Установка программ" },
            { "subtitle", "Отметьте нужное и нажмите «Установить» — всё поставится через winget." },
            { "search", "Поиск:" },
            { "category", "Категория:" },
            { "all", "Выбрать всё" },
            { "none", "Снять всё" },
            { "silent", "Тихая установка" },
            { "col.program", "Программа" },
            { "col.category", "Категория" },
            { "col.desc", "Описание" },
            { "col.status", "Статус" },
            { "cat.all", "Все категории" },
            { "btn.install", "Установить выбранное" },
            { "btn.stop", "Остановить" },
            { "status.selected", "Выбрано: {0} из {1}" },
            { "status.installing", "[{0}/{1}] Установка: {2}" },
            { "status.time", "Установка: {0}  ·  {1} с" },
            { "status.checking", "Проверяю уже установленные программы…" },
            { "status.warming", "Обновляю список пакетов winget — первый раз это до минуты…" },
            { "status.downloading", "Скачивание: {0}  ·  {1}" },
            { "status.sec", "{0} с" },
            { "status.stopping", "Останавливаю после текущей программы…" },
            { "status.done", "Готово. Установлено: {0}, уже было: {1}, ошибок: {2}" },
            { "status.stopped", "Остановлено. Установлено: {0}, ошибок: {1}" },
            { "state.installing", "Установка…" },
            { "state.ok", "Установлено" },
            { "state.already", "Уже установлено" },
            { "state.cancelled", "Отменено" },
            { "state.failed", "Ошибка" },
            { "state.stopped", "Остановлено" },
            { "msg.none.title", "Ничего не выбрано" },
            { "msg.none.text", "Отметьте хотя бы одну программу в списке." },
            { "msg.winget.title", "winget не найден" },
            { "msg.winget.text", "Не найден winget (App Installer).\r\nУстановите «App Installer» из Microsoft Store и запустите снова." },
            { "msg.confirm.title", "Подтверждение" },
            { "msg.confirm.text", "Будет установлено программ: {0}\r\n\r\n{1}\r\n\r\nПродолжить?" },
            { "msg.confirm.more", "… и ещё {0}" },
            { "msg.close.title", "Подтверждение" },
            { "msg.close.text", "Идёт установка. Прервать и закрыть?" },
            { "msg.done.title", "Установка завершена" },
            { "summary.installed", "Установлено: {0}" },
            { "summary.already", "Уже было: {0}" },
            { "summary.failed", "Ошибок: {0}" },
            { "summary.cancelled", "Отменено: {0}" },
            { "summary.hint", "Подробности — в файлах журнала (папка logs)." }
        };

        var en = new Dictionary<string, string>
        {
            { "form.title", "OneClickInstaller — app installer" },
            { "title", "Install programs" },
            { "subtitle", "Tick what you need and press Install — winget does the rest." },
            { "search", "Search:" },
            { "category", "Category:" },
            { "all", "Select all" },
            { "none", "Clear" },
            { "silent", "Silent install" },
            { "col.program", "Program" },
            { "col.category", "Category" },
            { "col.desc", "Description" },
            { "col.status", "Status" },
            { "cat.all", "All categories" },
            { "btn.install", "Install selected" },
            { "btn.stop", "Stop" },
            { "status.selected", "Selected: {0} of {1}" },
            { "status.installing", "[{0}/{1}] Installing: {2}" },
            { "status.time", "Installing: {0}  ·  {1}s" },
            { "status.checking", "Checking which programs are already installed…" },
            { "status.warming", "Refreshing the winget package list — the first time can take a minute…" },
            { "status.downloading", "Downloading: {0}  ·  {1}" },
            { "status.sec", "{0}s" },
            { "status.stopping", "Stopping after the current app…" },
            { "status.done", "Done. Installed: {0}, already installed: {1}, failed: {2}" },
            { "status.stopped", "Stopped. Installed: {0}, failed: {1}" },
            { "state.installing", "Installing…" },
            { "state.ok", "Installed" },
            { "state.already", "Already installed" },
            { "state.cancelled", "Cancelled" },
            { "state.failed", "Failed" },
            { "state.stopped", "Stopped" },
            { "msg.none.title", "Nothing selected" },
            { "msg.none.text", "Tick at least one program in the list." },
            { "msg.winget.title", "winget not found" },
            { "msg.winget.text", "winget (App Installer) was not found.\r\nInstall 'App Installer' from Microsoft Store and try again." },
            { "msg.confirm.title", "Confirm" },
            { "msg.confirm.text", "Apps to install: {0}\r\n\r\n{1}\r\n\r\nContinue?" },
            { "msg.confirm.more", "… and {0} more" },
            { "msg.close.title", "Confirm" },
            { "msg.close.text", "Installation is running. Abort and close?" },
            { "msg.done.title", "Installation finished" },
            { "summary.installed", "Installed: {0}" },
            { "summary.already", "Already installed: {0}" },
            { "summary.failed", "Failed: {0}" },
            { "summary.cancelled", "Cancelled: {0}" },
            { "summary.hint", "Details are in the log files (logs folder)." }
        };

        S["ru"] = ru;
        S["en"] = en;
    }

    public static string T(string key)
    {
        Dictionary<string, string> table;
        if (S.TryGetValue(Lang, out table) && table.ContainsKey(key)) return table[key];
        return S["ru"].ContainsKey(key) ? S["ru"][key] : key;
    }

    public static string Cat(string category)
    {
        if (Lang == "en" && category != null && CatsEn.ContainsKey(category)) return CatsEn[category];
        return category;
    }
}

static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        bool selfTest = args.Any(a => string.Equals(a, "--selftest", StringComparison.OrdinalIgnoreCase));
        string testInstallId = "";
        foreach (var a in args)
        {
            if (a.StartsWith("--testinstall=", StringComparison.OrdinalIgnoreCase))
                testInstallId = a.Substring("--testinstall=".Length);
        }
        string shot = "";
        foreach (var a in args)
        {
            if (a.StartsWith("--shot=", StringComparison.OrdinalIgnoreCase))
                shot = a.Substring("--shot=".Length);
        }

        if (!selfTest && testInstallId.Length == 0 && !IsAdmin())
        {
            try
            {
                var psi = new ProcessStartInfo(Application.ExecutablePath);
                psi.UseShellExecute = true;
                psi.Verb = "runas";
                psi.WorkingDirectory = Path.GetDirectoryName(Application.ExecutablePath);
                Process.Start(psi);
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "Для установки нужны права администратора, но запуск с повышением отменён.\r\n\r\n" + ex.Message,
                    "OneClickInstaller", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            return;
        }

        try
        {
            Directory.CreateDirectory(Paths.DataDir);
        }
        catch { }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new MainForm(selfTest, shot, testInstallId));
    }

    static bool IsAdmin()
    {
        try
        {
            var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch { return false; }
    }
}

class MainForm : Form
{
    const int ColProgram = 250;
    const int ColCategory = 145;
    const int ColStatus = 135;

    readonly List<AppItem> apps = new List<AppItem>();
    readonly Dictionary<string, ListViewItem> items = new Dictionary<string, ListViewItem>();
    readonly Dictionary<string, string> statusKeys = new Dictionary<string, string>();
    readonly List<string> allCats = new List<string>();
    List<string> catValues = new List<string>();

    ImageList iconList;
    ListView lv;
    TextBox txtSearch;
    ComboBox cmbCat;
    ComboBox cmbLang;
    CheckBox chkSilent;
    Button btnAll, btnNone, btnInstall, btnStop;
    Label lblTitle, lblSub, lblSearch, lblCat, lblStatus;
    Panel header;
    ProgressBar progress;
    Timer countTimer;
    ColumnHeader colDesc;

    bool installing;
    bool stopRequested;
    bool rebuilding;
    bool langLock;
    bool countDirty = true;
    bool autoYes;
    int selectedCount = -1;

    readonly string logPath;
    readonly bool selfTest;
    readonly string shotPath;

    static readonly Color Accent = Color.FromArgb(37, 99, 235);
    static readonly Color AccentDim = Color.FromArgb(29, 78, 216);
    static readonly Color TextMain = Color.FromArgb(15, 23, 42);
    static readonly Color TextMuted = Color.FromArgb(100, 116, 139);
    static readonly Color Border = Color.FromArgb(203, 213, 225);
    static readonly Color PanelBg = Color.FromArgb(248, 250, 252);

    public MainForm(bool selfTest, string shotPath, string testInstallId)
    {
        this.selfTest = selfTest;
        this.shotPath = shotPath;
        autoYes = !string.IsNullOrEmpty(testInstallId);

        logPath = Path.Combine(Paths.Logs, string.Format("install-{0}.log", DateTime.Now.ToString("yyyyMMdd-HHmmss")));
        try { Directory.CreateDirectory(Paths.Logs); } catch { }

        LoadData();
        LoadSettings();
        BuildUi();
        ApplyLanguage();
        UpdateFilter();

        countTimer = new Timer { Interval = 200 };
        countTimer.Tick += (s, e) =>
        {
            if (installing) return;
            int n = CountSelected();
            if (n != selectedCount || countDirty)
            {
                selectedCount = n;
                countDirty = false;
                SetStatus(string.Format(L.T("status.selected"), n, apps.Count));
            }
        };
        countTimer.Start();

        Log("OneClickInstaller · " + DateTime.Now.ToString("dd.MM.yyyy HH:mm"));
        Log("Скрипт: " + Application.ExecutablePath);
        Log("Журнал: " + logPath);
        Log("Выберите программы и нажмите «Установить выбранное».");

        if (autoYes)
        {
            foreach (var kv in items) kv.Value.Checked = false;
            var target = apps.FirstOrDefault(a => string.Equals(a.Id, testInstallId, StringComparison.OrdinalIgnoreCase));
            if (target != null) items[target.Id].Checked = true;
            Shown += (s, e) => BeginInvoke(new Action(StartInstall));
        }

        if (selfTest)
        {
            var t = new Timer { Interval = 900 };
            t.Tick += (s, e) =>
            {
                t.Stop();
                if (!string.IsNullOrEmpty(shotPath)) SaveShot(shotPath);
                Close();
            };
            t.Start();
        }
    }

    void SaveShot(string path)
    {
        try
        {
            using (var bmp = new Bitmap(Width, Height))
            {
                DrawToBitmap(bmp, new Rectangle(0, 0, Width, Height));
                bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
            }
        }
        catch { }
    }

    // ------------------------------ данные ------------------------------

    void LoadData()
    {
        var asm = typeof(MainForm).Assembly;
        var ser = new DataContractJsonSerializer(typeof(List<AppItem>));
        using (var s = asm.GetManifestResourceStream("apps.json"))
        {
            if (s == null) throw new InvalidOperationException("apps.json is not embedded.");
            apps.AddRange((List<AppItem>)ser.ReadObject(s));
        }

        foreach (var a in apps)
        {
            if (!string.IsNullOrEmpty(a.Category) && !allCats.Contains(a.Category)) allCats.Add(a.Category);
        }
        allCats.Sort(StringComparer.CurrentCulture);
    }

    void LoadSettings()
    {
        try
        {
            if (!File.Exists(Paths.Settings)) { return; }
            var ser = new DataContractJsonSerializer(typeof(Settings));
            using (var fs = File.OpenRead(Paths.Settings))
            {
                var st = (Settings)ser.ReadObject(fs);
                if (st != null)
                {
                    selectedIds = st.Selected ?? new List<string>();
                    silentSetting = st.Silent;
                    if (st.Lang == "en" || st.Lang == "ru") L.Lang = st.Lang;
                }
            }
        }
        catch { }
    }

    List<string> selectedIds = new List<string>();
    bool silentSetting = true;

    void SaveSettings()
    {
        try
        {
            var st = new Settings
            {
                Selected = apps.Where(a => items.ContainsKey(a.Id) && items[a.Id].Checked).Select(a => a.Id).ToList(),
                Silent = chkSilent.Checked,
                Lang = L.Lang
            };
            var ser = new DataContractJsonSerializer(typeof(Settings));
            Directory.CreateDirectory(Paths.DataDir);
            using (var fs = File.Create(Paths.Settings))
            {
                ser.WriteObject(fs, st);
            }
        }
        catch { }
    }

    // ------------------------------ интерфейс ------------------------------

    void BuildUi()
    {
        Text = L.T("form.title");
        ClientSize = new Size(1080, 700);
        MinimumSize = new Size(1024, 620);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.White;
        Font = new Font("Segoe UI", 9f);
        AutoScaleMode = AutoScaleMode.Font;

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 3,
            Margin = new Padding(0),
            Padding = new Padding(0)
        };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 112f));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 84f));

        // ---------- шапка ----------
        header = new Panel { Dock = DockStyle.Fill, Margin = new Padding(0) };

        lblTitle = new Label
        {
            Text = L.T("title"),
            Font = new Font("Segoe UI Semibold", 16f),
            ForeColor = TextMain,
            AutoSize = true,
            Location = new Point(22, 10)
        };
        header.Controls.Add(lblTitle);

        lblSub = new Label
        {
            Text = L.T("subtitle"),
            Font = new Font("Segoe UI", 9.5f),
            ForeColor = TextMuted,
            AutoSize = true,
            Location = new Point(24, 44)
        };
        header.Controls.Add(lblSub);

        lblSearch = new Label
        {
            Text = L.T("search"),
            AutoSize = true,
            ForeColor = TextMuted,
            Location = new Point(22, 74)
        };
        header.Controls.Add(lblSearch);

        txtSearch = new TextBox
        {
            Width = 180,
            Font = new Font("Segoe UI", 9.5f),
            BorderStyle = BorderStyle.FixedSingle,
            Location = new Point(78, 70)
        };
        txtSearch.TextChanged += (s, e) => UpdateFilter();
        txtSearch.KeyDown += (s, e) =>
        {
            if (e.KeyCode == Keys.Escape) txtSearch.Clear();
        };
        header.Controls.Add(txtSearch);

        lblCat = new Label
        {
            Text = L.T("category"),
            AutoSize = true,
            ForeColor = TextMuted,
            Location = new Point(272, 74)
        };
        header.Controls.Add(lblCat);

        cmbCat = new ComboBox
        {
            Width = 150,
            DropDownStyle = ComboBoxStyle.DropDownList,
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 9.5f),
            Location = new Point(350, 70)
        };
        cmbCat.SelectedIndexChanged += (s, e) => { if (!rebuilding) UpdateFilter(); };
        header.Controls.Add(cmbCat);

        btnAll = MakeSecondaryButton(L.T("all"), 104);
        btnAll.Location = new Point(514, 68);
        btnAll.Click += (s, e) => SetAllChecked(true);
        header.Controls.Add(btnAll);

        btnNone = MakeSecondaryButton(L.T("none"), 96);
        btnNone.Location = new Point(626, 68);
        btnNone.Click += (s, e) => SetAllChecked(false);
        header.Controls.Add(btnNone);

        chkSilent = new CheckBox
        {
            Text = L.T("silent"),
            AutoSize = true,
            Checked = silentSetting,
            ForeColor = TextMain
        };
        header.Controls.Add(chkSilent);

        cmbLang = new ComboBox
        {
            Width = 120,
            DropDownStyle = ComboBoxStyle.DropDownList,
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 9.5f)
        };
        cmbLang.Items.Add("Русский");
        cmbLang.Items.Add("English");
        cmbLang.SelectedIndexChanged += (s, e) =>
        {
            if (langLock) return;
            string target = cmbLang.SelectedIndex == 1 ? "en" : "ru";
            if (target == L.Lang) return;
            L.Lang = target;
            ApplyLanguage();
        };
        header.Controls.Add(cmbLang);

        EventHandler placeRight = (s, e) =>
        {
            chkSilent.Location = new Point(header.ClientSize.Width - chkSilent.Width - 24, 74);
            cmbLang.Location = new Point(chkSilent.Left - cmbLang.Width - 16, 69);
        };
        header.Resize += placeRight;
        placeRight(null, EventArgs.Empty);

        // ---------- список ----------
        var listHost = new Panel { Dock = DockStyle.Fill, Padding = new Padding(20, 0, 20, 0), Margin = new Padding(0) };

        iconList = new ImageList { ImageSize = new Size(24, 24), ColorDepth = ColorDepth.Depth32Bit };

        lv = new ListView
        {
            Dock = DockStyle.Fill,
            View = View.Details,
            CheckBoxes = true,
            FullRowSelect = true,
            HideSelection = false,
            MultiSelect = false,
            BorderStyle = BorderStyle.FixedSingle,
            HeaderStyle = ColumnHeaderStyle.Nonclickable,
            Font = new Font("Segoe UI", 9.5f),
            ShowItemToolTips = true,
            SmallImageList = iconList
        };
        lv.Columns.Add(L.T("col.program"), ColProgram);
        lv.Columns.Add(L.T("col.category"), ColCategory);
        colDesc = lv.Columns.Add(L.T("col.desc"), 400);
        lv.Columns.Add(L.T("col.status"), ColStatus);
        lv.DoubleClick += (s, e) =>
        {
            if (installing || lv.SelectedItems.Count == 0) return;
            lv.SelectedItems[0].Checked = !lv.SelectedItems[0].Checked;
            countDirty = true;
        };
        lv.Resize += (s, e) =>
        {
            int w = lv.ClientSize.Width - ColProgram - ColCategory - ColStatus - 4;
            if (w < 160) w = 160;
            colDesc.Width = w;
        };
        lv.ItemChecked += (s, e) => { countDirty = true; };
        listHost.Controls.Add(lv);

        // создаём строки и иконки
        var asm = typeof(MainForm).Assembly;
        for (int i = 0; i < apps.Count; i++)
        {
            var app = apps[i];
            Image icon = null;
            using (var s = asm.GetManifestResourceStream("icons." + app.Id + ".png"))
            {
                if (s != null)
                {
                    using (var src = Image.FromStream(s)) icon = ScaleImage(src, 24, 24);
                }
            }
            if (icon == null) icon = LetterIcon(app.Name);
            iconList.Images.Add(icon);

            var it = new ListViewItem(new string[] { app.Name, L.Cat(app.Category), GetDesc(app), "" })
            {
                ImageIndex = i,
                Tag = app.Id,
                ToolTipText = app.Id + "  ·  " + GetDesc(app)
            };
            it.Checked = selectedIds.Contains(app.Id);
            items[app.Id] = it;
        }

        // ---------- низ ----------
        var bottom = new Panel { Dock = DockStyle.Fill, BackColor = PanelBg, Margin = new Padding(0) };
        var bl = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1, Padding = new Padding(20, 0, 0, 0) };
        bl.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        bl.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 340f));

        var statusPanel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 2, Margin = new Padding(0, 0, 10, 0) };
        statusPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 30f));
        statusPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 26f));

        lblStatus = new Label
        {
            Dock = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleLeft,
            AutoEllipsis = true,
            ForeColor = TextMain,
            Font = new Font("Segoe UI", 9.5f)
        };
        statusPanel.Controls.Add(lblStatus, 0, 0);

        progress = new ProgressBar { Dock = DockStyle.Fill, Style = ProgressBarStyle.Continuous, Visible = false, Margin = new Padding(0, 4, 0, 10) };
        statusPanel.Controls.Add(progress, 0, 1);

        var flowBtns = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft,
            WrapContents = false,
            Padding = new Padding(0, 22, 16, 0),
            Margin = new Padding(0)
        };

        btnInstall = new Button
        {
            Text = L.T("btn.install"),
            Size = new Size(200, 36),
            FlatStyle = FlatStyle.Flat,
            BackColor = Accent,
            ForeColor = Color.White,
            Font = new Font("Segoe UI Semibold", 9.5f),
            Cursor = Cursors.Hand,
            Margin = new Padding(0)
        };
        btnInstall.FlatAppearance.BorderSize = 0;
        btnInstall.FlatAppearance.MouseOverBackColor = AccentDim;
        btnInstall.Click += (s, e) => StartInstall();
        flowBtns.Controls.Add(btnInstall);

        btnStop = MakeSecondaryButton(L.T("btn.stop"), 110);
        btnStop.Enabled = false;
        btnStop.Margin = new Padding(8, 0, 0, 0);
        btnStop.Click += (s, e) =>
        {
            if (!installing) return;
            stopRequested = true;
            SetStatus(L.T("status.stopping"));
            Log("!! Запрошена остановка пользователем");
        };
        flowBtns.Controls.Add(btnStop);

        bl.Controls.Add(statusPanel, 0, 0);
        bl.Controls.Add(flowBtns, 1, 0);
        bottom.Controls.Add(bl);

        root.Controls.Add(header, 0, 0);
        root.Controls.Add(listHost, 0, 1);
        root.Controls.Add(bottom, 0, 2);
        Controls.Add(root);

        FormClosing += (s, e) =>
        {
            if (installing)
            {
                var r = MessageBox.Show(L.T("msg.close.text"), L.T("msg.close.title"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                if (r != DialogResult.Yes) { e.Cancel = true; return; }
                stopRequested = true;
            }
            if (!selfTest) SaveSettings();
        };
    }

    Button MakeSecondaryButton(string text, int width)
    {
        var b = new Button
        {
            Text = text,
            Size = new Size(width, 28),
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.White,
            ForeColor = TextMain,
            Cursor = Cursors.Hand,
            Font = new Font("Segoe UI", 9f)
        };
        b.FlatAppearance.BorderColor = Border;
        return b;
    }

    static Image ScaleImage(Image src, int w, int h)
    {
        var bmp = new Bitmap(w, h);
        using (var g = Graphics.FromImage(bmp))
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.SmoothingMode = SmoothingMode.HighQuality;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.DrawImage(src, 0, 0, w, h);
        }
        return bmp;
    }

    static Image LetterIcon(string name)
    {
        var colors = new Color[]
        {
            Color.FromArgb(37, 99, 235), Color.FromArgb(16, 185, 129),
            Color.FromArgb(245, 158, 11), Color.FromArgb(239, 68, 68),
            Color.FromArgb(139, 92, 246), Color.FromArgb(14, 165, 233)
        };
        int sum = 0;
        foreach (char c in name ?? "") sum += c;

        var bmp = new Bitmap(64, 64);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var path = RoundedRect(2, 2, 60, 60, 14))
            using (var brush = new SolidBrush(colors[sum % colors.Length]))
            {
                g.FillPath(brush, path);
            }

            string initials = "";
            foreach (var w in (name ?? "?").Split(' '))
            {
                if (w.Length > 0) initials += char.ToUpperInvariant(w[0]);
                if (initials.Length >= 2) break;
            }
            if (initials.Length == 0) initials = "?";

            using (var font = new Font("Segoe UI", 26f, FontStyle.Bold, GraphicsUnit.Pixel))
            using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                g.DrawString(initials, font, Brushes.White, new RectangleF(0, 0, 64, 64), sf);
            }
        }
        return ScaleImage(bmp, 24, 24);
    }

    static GraphicsPath RoundedRect(float x, float y, float w, float h, float r)
    {
        var path = new GraphicsPath();
        float d = r * 2;
        path.AddArc(x, y, d, d, 180, 90);
        path.AddArc(x + w - d, y, d, d, 270, 90);
        path.AddArc(x + w - d, y + h - d, d, d, 0, 90);
        path.AddArc(x, y + h - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    // ------------------------------ язык ------------------------------

    void ApplyLanguage()
    {
        Text = L.T("form.title");
        lblTitle.Text = L.T("title");
        lblSub.Text = L.T("subtitle");
        lblSearch.Text = L.T("search");
        lblCat.Text = L.T("category");
        btnAll.Text = L.T("all");
        btnNone.Text = L.T("none");
        chkSilent.Text = L.T("silent");
        btnInstall.Text = L.T("btn.install");
        btnStop.Text = L.T("btn.stop");
        lv.Columns[0].Text = L.T("col.program");
        lv.Columns[1].Text = L.T("col.category");
        lv.Columns[2].Text = L.T("col.desc");
        lv.Columns[3].Text = L.T("col.status");

        foreach (var app in apps)
        {
            ListViewItem it;
            if (!items.TryGetValue(app.Id, out it)) continue;
            it.SubItems[1].Text = L.Cat(app.Category);
            it.SubItems[2].Text = GetDesc(app);
            it.ToolTipText = app.Id + "  ·  " + GetDesc(app);

            string key;
            if (statusKeys.TryGetValue(app.Id, out key))
            {
                if (key == "fail") key = "failed";
                it.SubItems[3].Text = L.T("state." + key);
            }
        }

        langLock = true;
        try
        {
            cmbLang.SelectedIndex = L.Lang == "en" ? 1 : 0;
            FillCategories();
        }
        finally { langLock = false; }

        UpdateFilter();
    }

    void FillCategories()
    {
        string prev = "";
        if (cmbCat.SelectedIndex > 0 && cmbCat.SelectedIndex < catValues.Count)
            prev = catValues[cmbCat.SelectedIndex];

        rebuilding = true;
        cmbCat.BeginUpdate();
        try
        {
            catValues = new List<string>();
            catValues.Add("");
            cmbCat.Items.Clear();
            cmbCat.Items.Add(L.T("cat.all"));
            foreach (var c in allCats)
            {
                catValues.Add(c);
                cmbCat.Items.Add(L.Cat(c));
            }
            int idx = 0;
            if (prev.Length > 0)
            {
                int i = catValues.IndexOf(prev);
                if (i > 0) idx = i;
            }
            cmbCat.SelectedIndex = idx;
        }
        finally
        {
            cmbCat.EndUpdate();
            rebuilding = false;
        }
    }

    string GetDesc(AppItem app)
    {
        if (L.Lang == "en" && !string.IsNullOrEmpty(app.DescEn)) return app.DescEn;
        return app.Desc;
    }

    // ------------------------------ фильтр ------------------------------

    void UpdateFilter()
    {
        string q = txtSearch.Text.Trim();
        string cat = "";
        if (cmbCat.SelectedIndex > 0 && cmbCat.SelectedIndex < catValues.Count)
            cat = catValues[cmbCat.SelectedIndex];

        lv.BeginUpdate();
        try
        {
            lv.Items.Clear();
            foreach (var app in apps)
            {
                bool okCat = cat.Length == 0 || app.Category == cat;
                bool okQ = true;
                if (q.Length > 0)
                {
                    string hay = string.Join("\n", new string[] {
                        app.Name, app.Desc, app.DescEn, app.Category, L.Cat(app.Category), app.Id
                    });
                    okQ = hay.IndexOf(q, StringComparison.CurrentCultureIgnoreCase) >= 0;
                }
                if (okCat && okQ) lv.Items.Add(items[app.Id]);
            }
        }
        finally { lv.EndUpdate(); }

        countDirty = true;
    }

    void SetAllChecked(bool value)
    {
        if (installing) return;
        foreach (ListViewItem it in lv.Items) it.Checked = value;
        countDirty = true;
    }

    int CountSelected()
    {
        int n = 0;
        foreach (var app in apps)
        {
            ListViewItem it;
            if (items.TryGetValue(app.Id, out it) && it.Checked) n++;
        }
        return n;
    }

    void SetStatus(string text)
    {
        lblStatus.Text = text;
        lblStatus.Refresh();
    }

    // ------------------------------ журнал ------------------------------

    void Log(string line)
    {
        try
        {
            string clean = (line ?? "").Trim();
            if (clean.Length == 0) return;
            if (clean.Length > 400) clean = clean.Substring(0, 400) + "…";
            File.AppendAllText(logPath, clean + "\r\n", new UTF8Encoding(false));
        }
        catch { }
    }

    // ------------------------------ установка ------------------------------

    static string FindWinget()
    {
        string alias = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            @"Microsoft\WindowsApps\winget.exe");
        if (File.Exists(alias)) return alias;

        string path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var dir in path.Split(';'))
        {
            if (dir.Trim().Length == 0) continue;
            try
            {
                string candidate = Path.Combine(dir.Trim(), "winget.exe");
                if (File.Exists(candidate)) return candidate;
            }
            catch { }
        }
        return null;
    }

    void SetItemState(ListViewItem it, string id, string kind)
    {
        statusKeys[id] = kind;
        string key = kind == "fail" ? "failed" : kind;
        it.SubItems[3].Text = L.T("state." + key);

        switch (kind)
        {
            case "ok": it.ForeColor = Color.FromArgb(22, 163, 74); break;
            case "already": it.ForeColor = Color.FromArgb(100, 116, 139); break;
            case "cancelled": it.ForeColor = Color.FromArgb(202, 138, 4); break;
            case "stopped": it.ForeColor = Color.FromArgb(120, 120, 120); break;
            case "installing": it.ForeColor = Accent; break;
            default: it.ForeColor = Color.FromArgb(220, 38, 38); break;
        }
    }

    void StartInstall()
    {
        if (installing) return;

        var targets = apps.Where(a => items[a.Id].Checked).ToList();
        if (targets.Count == 0)
        {
            MessageBox.Show(L.T("msg.none.text"), L.T("msg.none.title"), MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        string winget = FindWinget();
        if (winget == null)
        {
            MessageBox.Show(L.T("msg.winget.text"), L.T("msg.winget.title"), MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        string preview = string.Join("\r\n", targets.Take(8).Select(a => "• " + a.Name).ToArray());
        if (targets.Count > 8) preview += "\r\n• " + string.Format(L.T("msg.confirm.more"), targets.Count - 8);
        if (!autoYes)
        {
            var answer = MessageBox.Show(string.Format(L.T("msg.confirm.text"), targets.Count, preview),
                L.T("msg.confirm.title"), MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (answer != DialogResult.Yes) return;
        }

        SaveSettings();

        installing = true;
        stopRequested = false;
        int ok = 0, already = 0, fail = 0, cancelled = 0;

        btnInstall.Enabled = false;
        btnAll.Enabled = false;
        btnNone.Enabled = false;
        btnStop.Enabled = true;
        cmbCat.Enabled = false;
        txtSearch.Enabled = false;
        chkSilent.Enabled = false;
        cmbLang.Enabled = false;
        progress.Maximum = Math.Max(1, targets.Count);
        progress.Value = 0;
        progress.Visible = true;

        Log("");
        Log(string.Format("==== Начало установки: {0} программ ====", targets.Count));
        Log(string.Format("Режим: {0}", chkSilent.Checked ? "тихий" : "с диалогами установщиков"));

        SetStatus(L.T("status.checking"));
        Log("Проверяю уже установленные программы…");
        HashSet<string> installed = GetInstalledIds(winget, targets);
        if (installed != null) Log(string.Format("winget знает про установленные пакеты: {0}", installed.Count));

        int index = 0;
        foreach (var app in targets)
        {
            if (stopRequested) break;
            index++;
            var it = items[app.Id];

            if (installed != null && installed.Contains(app.Id))
            {
                already++;
                SetItemState(it, app.Id, "already");
                Log(string.Format("--- {0} ({1}) уже установлено, пропускаю", app.Name, app.Id));
                progress.Value = Math.Min(index, progress.Maximum);
                continue;
            }

            SetItemState(it, app.Id, "installing");
            int visibleIndex = lv.Items.IndexOf(it);
            if (visibleIndex >= 0) lv.EnsureVisible(visibleIndex);

            SetStatus(string.Format(L.T("status.installing"), index, targets.Count, app.Name));
            Log("");
            Log(string.Format("==> [{0}/{1}] {2} ({3})", index, targets.Count, app.Name, app.Id));

            var started = DateTime.UtcNow;
            var result = RunWinget(winget, BuildArgs(app.Id), app.Name);
            int elapsed = (int)(DateTime.UtcNow - started).TotalSeconds;

            if (stopRequested)
            {
                SetItemState(it, app.Id, "stopped");
                cancelled++;
                break;
            }

            string kind = ResultKind(result.Code, result.Output);
            SetItemState(it, app.Id, kind);
            switch (kind)
            {
                case "ok": ok++; break;
                case "already": already++; break;
                case "cancelled": cancelled++; break;
                default: fail++; break;
            }

            Log(string.Format("<== {0}: {1}, код {2}, {3} с", app.Id, kind, result.Code, elapsed));
            if (!string.IsNullOrEmpty(result.Output))
            {
                foreach (var line in result.Output.Split(new string[] { "\r\n", "\n" }, StringSplitOptions.None))
                {
                    if (Regex.IsMatch(line, "[█▒░]")) continue;
                    string trimmed = line.Trim();
                    if (trimmed == "-" || trimmed == "\\" || trimmed == "|" || trimmed == "/") continue;
                    Log("    " + line);
                }
            }
            Log(string.Format("    Итог: установлено={0}, уже было={1}, ошибок={2}, отменено={3}", ok, already, fail, cancelled));

            progress.Value = Math.Min(index, progress.Maximum);
            Application.DoEvents();
        }

        installing = false;
        progress.Visible = false;
        btnInstall.Enabled = true;
        btnAll.Enabled = true;
        btnNone.Enabled = true;
        btnStop.Enabled = false;
        cmbCat.Enabled = true;
        txtSearch.Enabled = true;
        chkSilent.Enabled = true;
        cmbLang.Enabled = true;

        Log("");
        Log(string.Format("==== Готово: установлено {0}, уже было {1}, ошибок {2}, отменено {3} ====", ok, already, fail, cancelled));

        if (stopRequested) SetStatus(string.Format(L.T("status.stopped"), ok, fail));
        else SetStatus(string.Format(L.T("status.done"), ok, already, fail));

        string summary = string.Format(L.T("summary.installed"), ok) + "\r\n" +
                         string.Format(L.T("summary.already"), already) + "\r\n" +
                         string.Format(L.T("summary.failed"), fail);
        if (cancelled > 0) summary += "\r\n" + string.Format(L.T("summary.cancelled"), cancelled);
        if (fail > 0) summary += "\r\n\r\n" + L.T("summary.hint");

        if (autoYes)
        {
            Log("Тестовый прогон: " + summary.Replace("\r\n", " | "));
            Close();
            return;
        }

        MessageBox.Show(summary, L.T("msg.done.title"), MessageBoxButtons.OK,
            fail > 0 ? MessageBoxIcon.Warning : MessageBoxIcon.Information);
    }

    string BuildArgs(string id)
    {
        string args = "install --id " + id + " -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity";
        if (chkSilent.Checked) args += " --silent";
        return args;
    }

    static string ResultKind(int code, string output)
    {
        if (code == 0 || code == 3010) return "ok";
        if (code == -1978335189) return "already";
        string o = output ?? "";
        if (Regex.IsMatch(o, "already installed|уже установлен|no applicable update|не применимо", RegexOptions.IgnoreCase)) return "already";
        if (code == 1602 || Regex.IsMatch(o, @"\bcancell?ed\b|отменено пользователем", RegexOptions.IgnoreCase)) return "cancelled";
        return "fail";
    }

    RunResult RunWinget(string winget, string args, string displayName)
    {
        return RunProcess(winget, args, (sec, stage, pct) =>
        {
            if (stage == "download")
            {
                string suffix = pct.Length > 0 ? pct : string.Format(L.T("status.sec"), sec);
                SetStatus(string.Format(L.T("status.downloading"), displayName, suffix));
            }
            else
            {
                SetStatus(string.Format(L.T("status.time"), displayName, sec));
            }
        });
    }

    HashSet<string> GetInstalledIds(string winget, List<AppItem> targets)
    {
        string tmp = Path.Combine(Path.GetTempPath(), "oci-export-" + Guid.NewGuid().ToString("N") + ".json");
        var result = RunProcess(winget,
            "export -o \"" + tmp + "\" --accept-source-agreements --disable-interactivity",
            (sec, stage, pct) => { if (sec >= 5) SetStatus(L.T("status.warming")); });

        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            if (File.Exists(tmp))
            {
                var ser = new DataContractJsonSerializer(typeof(ExportDoc));
                using (var fs = File.OpenRead(tmp))
                {
                    var doc = (ExportDoc)ser.ReadObject(fs);
                    if (doc != null && doc.Sources != null)
                    {
                        foreach (var src in doc.Sources)
                        {
                            if (src == null || src.Packages == null) continue;
                            foreach (var p in src.Packages)
                            {
                                if (p != null && !string.IsNullOrEmpty(p.Id)) set.Add(p.Id);
                            }
                        }
                    }
                }
            }
        }
        catch { }
        try { File.Delete(tmp); } catch { }

        if (result.Code != 0 && set.Count == 0) return null;
        return set;
    }

    RunResult RunProcess(string fileName, string arguments, Action<int, string, string> onTick)
    {
        var psi = new ProcessStartInfo(fileName, arguments)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        var p = new Process { StartInfo = psi };
        var lines = new List<string>();

        try { p.Start(); }
        catch (Exception ex) { return new RunResult { Code = -1, Output = ex.Message }; }

        Task<string> readOut = null, readErr = null;
        try { readOut = p.StandardOutput.ReadLineAsync(); } catch { }
        try { readErr = p.StandardError.ReadLineAsync(); } catch { }

        var started = DateTime.UtcNow;
        int lastSec = -1;
        string stage = "";
        string pct = "";

        try
        {
            while (true)
            {
                if (readOut != null && readOut.IsCompleted)
                {
                    string line = null;
                    try { line = readOut.Result; } catch { }
                    if (line == null) readOut = null;
                    else
                    {
                        lines.Add(line);
                        if (Regex.IsMatch(line, "download", RegexOptions.IgnoreCase)) stage = "download";
                        else if (Regex.IsMatch(line, "install|starting|extract|verify", RegexOptions.IgnoreCase) && stage != "download") stage = "install";
                        var m = Regex.Match(line, @"(\d{1,3})\s*%");
                        if (m.Success) pct = m.Groups[1].Value + "%";
                        try { readOut = p.StandardOutput.ReadLineAsync(); } catch { readOut = null; }
                    }
                }

                if (readErr != null && readErr.IsCompleted)
                {
                    string eline = null;
                    try { eline = readErr.Result; } catch { }
                    if (eline == null) readErr = null;
                    else
                    {
                        lines.Add(eline);
                        try { readErr = p.StandardError.ReadLineAsync(); } catch { readErr = null; }
                    }
                }

                if (p.HasExited && readOut == null && readErr == null) break;

                if (stopRequested)
                {
                    try { p.Kill(); } catch { }
                    break;
                }

                int sec = (int)(DateTime.UtcNow - started).TotalSeconds;
                if (sec != lastSec)
                {
                    lastSec = sec;
                    onTick(sec, stage, pct);
                }

                Application.DoEvents();
                System.Threading.Thread.Sleep(60);
            }
        }
        catch { }

        try { p.WaitForExit(5000); } catch { }

        int code = -1;
        try { code = p.ExitCode; } catch { }
        try { p.Dispose(); } catch { }

        return new RunResult { Code = code, Output = string.Join("\r\n", lines.ToArray()).Trim() };
    }
}
