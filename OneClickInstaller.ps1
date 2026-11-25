#requires -Version 5.1
<#
    OneClickInstaller
    Установка набора программ в один клик: WinForms + winget.

    Файлы рядом со скриптом:
      apps.json       — список программ (id, name, category, desc)
      settings.json   — сохраняется автоматически (выбор + режим)
      logs\           — журналы установки
#>
param(
    [switch]$SelfTest
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# ----------------------------- пути -----------------------------
$script:Root = Split-Path -Parent $PSCommandPath
if (-not $script:Root) { $script:Root = (Get-Location).Path }
$script:ScriptPath   = Join-Path $script:Root 'OneClickInstaller.ps1'
$script:AppsPath     = Join-Path $script:Root 'apps.json'
$script:SettingsPath = Join-Path $script:Root 'settings.json'
$script:LogsDir      = Join-Path $script:Root 'logs'
$script:IconsDir     = Join-Path $script:Root 'icons'
$script:LogPath      = Join-Path $script:LogsDir ('install-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

# ------------------------- права администратора -------------------------
# Многие установщики требуют прав администратора, поэтому запускаем себя заново с UAC.
if (-not $SelfTest) {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        try {
            $argList = @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Sta', '-WindowStyle', 'Hidden',
                '-File', ('"{0}"' -f $script:ScriptPath)
            )
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList `
                          -WorkingDirectory $script:Root -ErrorAction Stop
        } catch {
            [void][System.Windows.Forms.MessageBox]::Show(
                "Для установки нужны права администратора, но запуск с повышением отменён.`r`n`r`n$($_.Exception.Message)",
                'OneClickInstaller', 'OK', 'Warning')
        }
        exit
    }
}

# ---------------------------- данные -----------------------------
try {
    $raw = [System.IO.File]::ReadAllText($script:AppsPath, [System.Text.Encoding]::UTF8)
    $parsed = ConvertFrom-Json -InputObject $raw
    if ($parsed -is [System.Array]) { $script:Apps = $parsed } else { $script:Apps = @($parsed) }
} catch {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Не удалось прочитать apps.json:`r`n$($_.Exception.Message)`r`n`r`nФайл должен лежать рядом со скриптом.",
        'OneClickInstaller', 'OK', 'Error')
    exit 1
}
if ($script:Apps.Count -eq 0) {
    [void][System.Windows.Forms.MessageBox]::Show('Список программ пуст.', 'OneClickInstaller', 'OK', 'Warning')
    exit 1
}

$script:SelectedIds = @()
$script:Silent      = $true
$script:Lang        = 'ru'
if (Test-Path $script:SettingsPath) {
    try {
        $st = [System.IO.File]::ReadAllText($script:SettingsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($st.selected) { $script:SelectedIds = @($st.selected) }
        if ($null -ne $st.silent) { $script:Silent = [bool]$st.silent }
        if ($st.lang -eq 'en' -or $st.lang -eq 'ru') { $script:Lang = [string]$st.lang }
    } catch { }
}

function Get-AppDesc {
    param($App)
    if ($script:Lang -eq 'en' -and $App.desc_en) { return [string]$App.desc_en }
    return [string]$App.desc
}

if (-not (Test-Path $script:LogsDir)) {
    try { [void](New-Item -ItemType Directory -Force -Path $script:LogsDir) } catch { }
}

$script:Items        = @{}
$script:Suppress     = $false
$script:Installing   = $false
$script:StopRequested = $false
$script:SelectedCount = 0
$script:UiReady      = $false

foreach ($app in $script:Apps) {
    $it = [System.Windows.Forms.ListViewItem]::new([string]$app.name)
    [void]$it.SubItems.Add([string]$app.category)
    [void]$it.SubItems.Add((Get-AppDesc $app))
    [void]$it.SubItems.Add('')
    $it.Tag = [string]$app.id
    $it.ToolTipText = '{0}  ·  {1}' -f $app.id, (Get-AppDesc $app)
    $script:Suppress = $true
    $it.Checked = ($script:SelectedIds -contains [string]$app.id)
    $script:Suppress = $false
    $script:Items[[string]$app.id] = $it
}

# ---------------------------- функции -----------------------------
$script:Strings = @{
    ru = @{
        'form.title'        = 'OneClickInstaller — установка программ'
        'title'             = 'Установка программ'
        'subtitle'          = 'Отметьте нужное и нажмите «Установить» — всё поставится через winget.'
        'search'            = 'Поиск:'
        'category'          = 'Категория:'
        'all'               = 'Выбрать всё'
        'none'              = 'Снять всё'
        'silent'            = 'Тихая установка'
        'col.program'       = 'Программа'
        'col.category'      = 'Категория'
        'col.desc'          = 'Описание'
        'col.status'        = 'Статус'
        'cat.all'           = 'Все категории'
        'btn.install'       = 'Установить выбранное'
        'btn.stop'          = 'Остановить'
        'status.selected'   = 'Выбрано: {0} из {1}'
        'status.installing' = '[{0}/{1}] Установка: {2}'
        'status.time'       = 'Установка: {0}  ·  {1} с'
        'status.checking'   = 'Проверяю уже установленные программы…'
        'status.warming'    = 'Обновляю список пакетов winget — первый раз это до минуты…'
        'status.downloading'= 'Скачивание: {0}  ·  {1}'
        'status.sec'        = '{0} с'
        'status.stopping'   = 'Останавливаю после текущей программы…'
        'status.done'       = 'Готово. Установлено: {0}, уже было: {1}, ошибок: {2}'
        'status.stopped'    = 'Остановлено. Установлено: {0}, ошибок: {1}'
        'state.installing'  = 'Установка…'
        'state.ok'          = 'Установлено'
        'state.already'     = 'Уже установлено'
        'state.cancelled'   = 'Отменено'
        'state.failed'      = 'Ошибка'
        'state.stopped'     = 'Остановлено'
        'msg.none.title'    = 'Ничего не выбрано'
        'msg.none.text'     = 'Отметьте хотя бы одну программу в списке.'
        'msg.winget.title'  = 'winget не найден'
        'msg.winget.text'   = "Не найден winget (App Installer).`r`nУстановите «App Installer» из Microsoft Store и запустите снова."
        'msg.confirm.title' = 'Подтверждение'
        'msg.confirm.text'  = "Будет установлено программ: {0}`r`n`r`n{1}`r`n`r`nПродолжить?"
        'msg.confirm.more'  = '… и ещё {0}'
        'msg.close.title'   = 'Подтверждение'
        'msg.close.text'    = 'Идёт установка. Прервать и закрыть?'
        'msg.done.title'    = 'Установка завершена'
        'summary.installed' = 'Установлено: {0}'
        'summary.already'   = 'Уже было: {0}'
        'summary.failed'    = 'Ошибок: {0}'
        'summary.cancelled' = 'Отменено: {0}'
        'summary.hint'      = 'Подробности — в файлах журнала (папка logs).'
        'lang.ru'           = 'Русский'
        'lang.en'           = 'English'
    }
    en = @{
        'form.title'        = 'OneClickInstaller — app installer'
        'title'             = 'Install programs'
        'subtitle'          = 'Tick what you need and press Install — winget does the rest.'
        'search'            = 'Search:'
        'category'          = 'Category:'
        'all'               = 'Select all'
        'none'              = 'Clear'
        'silent'            = 'Silent install'
        'col.program'       = 'Program'
        'col.category'      = 'Category'
        'col.desc'          = 'Description'
        'col.status'        = 'Status'
        'cat.all'           = 'All categories'
        'btn.install'       = 'Install selected'
        'btn.stop'          = 'Stop'
        'status.selected'   = 'Selected: {0} of {1}'
        'status.installing' = '[{0}/{1}] Installing: {2}'
        'status.time'       = 'Installing: {0}  ·  {1}s'
        'status.checking'   = 'Checking which programs are already installed…'
        'status.warming'    = 'Refreshing the winget package list — the first time can take a minute…'
        'status.downloading'= 'Downloading: {0}  ·  {1}'
        'status.sec'        = '{0}s'
        'status.stopping'   = 'Stopping after the current app…'
        'status.done'       = 'Done. Installed: {0}, already installed: {1}, failed: {2}'
        'status.stopped'    = 'Stopped. Installed: {0}, failed: {1}'
        'state.installing'  = 'Installing…'
        'state.ok'          = 'Installed'
        'state.already'     = 'Already installed'
        'state.cancelled'   = 'Cancelled'
        'state.failed'      = 'Failed'
        'state.stopped'     = 'Stopped'
        'msg.none.title'    = 'Nothing selected'
        'msg.none.text'     = 'Tick at least one program in the list.'
        'msg.winget.title'  = 'winget not found'
        'msg.winget.text'   = "winget (App Installer) was not found.`r`nInstall 'App Installer' from Microsoft Store and try again."
        'msg.confirm.title' = 'Confirm'
        'msg.confirm.text'  = "Apps to install: {0}`r`n`r`n{1}`r`n`r`nContinue?"
        'msg.confirm.more'  = '… and {0} more'
        'msg.close.title'   = 'Confirm'
        'msg.close.text'    = 'Installation is running. Abort and close?'
        'msg.done.title'    = 'Installation finished'
        'summary.installed' = 'Installed: {0}'
        'summary.already'   = 'Already installed: {0}'
        'summary.failed'    = 'Failed: {0}'
        'summary.cancelled' = 'Cancelled: {0}'
        'summary.hint'      = 'Details are in the log files (logs folder).'
        'lang.ru'           = 'Русский'
        'lang.en'           = 'English'
    }
}

$script:CatsEn = @{
    'Браузеры'         = 'Browsers'
    'Мессенджеры'      = 'Messengers'
    'Медиа'            = 'Media'
    'Утилиты'          = 'Utilities'
    'Игры'             = 'Games'
    'Разработка'       = 'Development'
    'Компоненты'       = 'Components'
    'Удалённый доступ' = 'Remote access'
}

function T {
    param([string]$Key)
    $table = $script:Strings[$script:Lang]
    if ($table -and $table.ContainsKey($Key)) { return $table[$Key] }
    return $script:Strings['ru'][$Key]
}

function T-Category {
    param([string]$Category)
    if ($script:Lang -eq 'en' -and $script:CatsEn.ContainsKey($Category)) { return $script:CatsEn[$Category] }
    return $Category
}

function Add-LogLine {
    param([string]$Text)
    if ($null -eq $Text) { return }
    $clean = $Text -replace '\x1B\[[0-9;?]*[A-Za-z]', ''
    $clean = $clean -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
    $clean = $clean.TrimEnd()
    if ([string]::IsNullOrWhiteSpace($clean)) { return }
    if ($clean.Length -gt 400) { $clean = $clean.Substring(0, 400) + '…' }
    try {
        [System.IO.File]::AppendAllText($script:LogPath, $clean + "`r`n", [System.Text.Encoding]::UTF8)
    } catch { }
}

function Set-Status {
    param([string]$Text)
    if ($script:UiReady) { $script:lblStatus.Text = $Text; $script:lblStatus.Refresh() }
}

function Set-CountText {
    $n = @($script:Items.Values | Where-Object { $_.Checked }).Count
    $script:SelectedCount = $n
    if (-not $script:Installing) {
        Set-Status ((T 'status.selected') -f $n, $script:Apps.Count)
    }
}

function Save-Settings {
    try {
        $ids = @($script:Apps | Where-Object { $script:Items[[string]$_.id].Checked } | ForEach-Object { [string]$_.id })
        $obj = [pscustomobject]@{ selected = $ids; silent = [bool]$script:chkSilent.Checked; lang = $script:Lang }
        $json = $obj | ConvertTo-Json -Depth 3
        [System.IO.File]::WriteAllText($script:SettingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

function Get-WingetPath {
    $cmd = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $candidate) { return $candidate }
    return $null
}

function Get-InstalledIds {
    param([string]$WingetPath)

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $tmp = Join-Path $env:TEMP ('oci-export-{0}.json' -f [Guid]::NewGuid().ToString('N'))

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = $WingetPath
    $psi.Arguments              = 'export -o "{0}" --accept-source-agreements --disable-interactivity' -f $tmp
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

    $p = [System.Diagnostics.Process]::new()
    $p.StartInfo = $psi
    try { [void]$p.Start() } catch { return $set }

    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $started = Get-Date
    $warned  = $false

    while (-not $p.HasExited) {
        if ($script:StopRequested) { try { $p.Kill() } catch { }; break }
        if (-not $warned -and ((Get-Date) - $started).TotalSeconds -ge 5) {
            $warned = $true
            Set-Status (T 'status.warming')
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }

    try { [void]$p.WaitForExit(8000) } catch { }
    try { [void]$outTask.GetAwaiter().GetResult(); [void]$errTask.GetAwaiter().GetResult() } catch { }
    try { $p.Dispose() } catch { }

    if (Test-Path -LiteralPath $tmp) {
        try {
            $raw = [System.IO.File]::ReadAllText($tmp, [System.Text.Encoding]::UTF8)
            $json = ConvertFrom-Json -InputObject $raw
            foreach ($src in @($json.Sources)) {
                foreach ($pkg in @($src.Packages)) {
                    $pid2 = [string]$pkg.PackageIdentifier
                    if ($pid2) { [void]$set.Add($pid2) }
                }
            }
        } catch { }
        try { Remove-Item -LiteralPath $tmp -Force } catch { }
    }

    return $set
}

function Get-ResultKind {
    param([int]$Code, [string]$Output)
    if ($Code -eq 0 -or $Code -eq 3010) { return 'ok' }
    if ($Code -eq -1978335189) { return 'already' }
    if ($Output -match '(?i)already installed|уже установлен|no applicable update|не применимо') { return 'already' }
    if ($Code -eq 1602 -or $Output -match '(?i)\bcancell?ed\b|отменено пользователем') { return 'cancelled' }
    return 'fail'
}

function Invoke-Winget {
    param(
        [string]$WingetPath,
        [string]$PackageId,
        [string]$DisplayName
    )

    $pkgArgs = @(
        'install', '--id', $PackageId, '-e',
        '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity'
    )
    if ($script:chkSilent.Checked) { $pkgArgs += '--silent' }

    $quoted = foreach ($a in $pkgArgs) {
        if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a }
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = $WingetPath
    $psi.Arguments              = ($quoted -join ' ')
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

    $p = [System.Diagnostics.Process]::new()
    $p.StartInfo = $psi
    try {
        [void]$p.Start()
    } catch {
        return [pscustomobject]@{ Code = -1; Output = $_.Exception.Message }
    }

    $outLines = New-Object 'System.Collections.Generic.List[string]'
    $errLines = New-Object 'System.Collections.Generic.List[string]'
    $readOut = $null; $readErr = $null
    try { $readOut = $p.StandardOutput.ReadLineAsync() } catch { }
    try { $readErr = $p.StandardError.ReadLineAsync() } catch { }

    $started = Get-Date
    $lastSec = -1
    $stage   = ''
    $pct     = ''

    while ($true) {
        if ($readOut -and $readOut.IsCompleted) {
            $line = $null
            try { $line = $readOut.Result } catch { }
            if ($null -eq $line) {
                $readOut = $null
            } else {
                [void]$outLines.Add($line)
                if ($line -match '(?i)download') { $stage = 'download' }
                elseif ($line -match '(?i)install|starting|extract|verify') { if ($stage -ne 'download') { $stage = 'install' } }
                if ($line -match '(\d{1,3})\s*%') { $pct = $matches[1] + '%' }
                try { $readOut = $p.StandardOutput.ReadLineAsync() } catch { $readOut = $null }
            }
        }
        if ($readErr -and $readErr.IsCompleted) {
            $eline = $null
            try { $eline = $readErr.Result } catch { }
            if ($null -eq $eline) {
                $readErr = $null
            } else {
                [void]$errLines.Add($eline)
                try { $readErr = $p.StandardError.ReadLineAsync() } catch { $readErr = $null }
            }
        }

        $finished = $p.HasExited -and -not $readOut -and -not $readErr
        if ($finished) { break }

        if ($script:StopRequested) {
            try { $p.Kill() } catch { }
            break
        }

        $sec = [int]((Get-Date) - $started).TotalSeconds
        if ($sec -ne $lastSec) {
            $lastSec = $sec
            if ($stage -eq 'download') {
                $suffix = if ($pct) { $pct } else { (T 'status.sec') -f $sec }
                Set-Status ((T 'status.downloading') -f $DisplayName, $suffix)
            } elseif ($stage -eq 'install') {
                Set-Status ((T 'status.time') -f $DisplayName, $sec)
            } else {
                Set-Status ((T 'status.time') -f $DisplayName, $sec)
            }
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 60
    }

    try { [void]$p.WaitForExit(5000) } catch { }
    $code = -1
    try { $code = $p.ExitCode } catch { }
    try { $p.Dispose() } catch { }

    $stdout = ($outLines -join "`r`n")
    $stderr = ($errLines -join "`r`n")
    return [pscustomobject]@{ Code = $code; Output = (($stdout + "`r`n" + $stderr).Trim()) }
}

function Start-Install {
    if ($script:Installing) { return }

    $targets = @($script:Apps | Where-Object { $script:Items[[string]$_.id].Checked })
    if ($targets.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show((T 'msg.none.text'), (T 'msg.none.title'), 'OK', 'Information')
        return
    }

    $winget = Get-WingetPath
    if (-not $winget) {
        [void][System.Windows.Forms.MessageBox]::Show((T 'msg.winget.text'), (T 'msg.winget.title'), 'OK', 'Error')
        return
    }

    $preview = ($targets | Select-Object -First 8 | ForEach-Object { '• ' + $_.name }) -join "`r`n"
    if ($targets.Count -gt 8) { $preview += "`r`n• " + ((T 'msg.confirm.more') -f ($targets.Count - 8)) }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        ((T 'msg.confirm.text') -f $targets.Count, $preview),
        (T 'msg.confirm.title'), 'YesNo', 'Question')
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    Save-Settings

    $script:Installing    = $true
    $script:StopRequested = $false
    $ok = 0; $already = 0; $fail = 0; $cancelled = 0

    $script:btnInstall.Enabled = $false
    $script:btnAll.Enabled     = $false
    $script:btnNone.Enabled    = $false
    $script:btnStop.Enabled    = $true
    $script:cmbCat.Enabled     = $false
    $script:txtSearch.Enabled  = $false
    $script:chkSilent.Enabled  = $false
    if ($script:cmbLang) { $script:cmbLang.Enabled = $false }
    $script:progress.Maximum   = [Math]::Max(1, $targets.Count)
    $script:progress.Value     = 0
    $script:progress.Visible   = $true

    Add-LogLine ''
    Add-LogLine ('==== Начало установки: {0} программ ====' -f $targets.Count)
    Add-LogLine ('Режим: {0}' -f $(if ($script:chkSilent.Checked) { 'тихий' } else { 'с диалогами установщиков' }))

    Set-Status (T 'status.checking')
    Add-LogLine 'Проверяю уже установленные программы…'
    $installed = $null
    try { $installed = Get-InstalledIds -WingetPath $winget } catch { $installed = $null }
    if ($installed) { Add-LogLine ('winget знает про установленные пакеты: {0}' -f $installed.Count) }

    $index = 0
    foreach ($app in $targets) {
        if ($script:StopRequested) { break }
        $index++
        $item = $script:Items[[string]$app.id]

        if ($installed -and $installed.Contains([string]$app.id)) {
            $already++
            $script:StatusKeys[[string]$app.id] = 'already'
            $item.SubItems[3].Text = (T 'state.already')
            $item.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
            Add-LogLine ('--- {0} ({1}) уже установлено, пропускаю' -f $app.name, $app.id)
            $script:progress.Value = [Math]::Min($index, $script:progress.Maximum)
            continue
        }

        $script:StatusKeys[[string]$app.id] = 'installing'
        $item.SubItems[3].Text = (T 'state.installing')
        $item.ForeColor = [System.Drawing.Color]::FromArgb(37, 99, 235)

        $visibleIndex = $script:lv.Items.IndexOf($item)
        if ($visibleIndex -ge 0) { $script:lv.EnsureVisible($visibleIndex) }

        Set-Status ((T 'status.installing') -f $index, $targets.Count, $app.name)
        Add-LogLine ''
        Add-LogLine ('==> [{0}/{1}] {2} ({3})' -f $index, $targets.Count, $app.name, $app.id)

        $started = Get-Date
        $result  = Invoke-Winget -WingetPath $winget -PackageId ([string]$app.id) -DisplayName ([string]$app.name)
        $elapsed = [int]((Get-Date) - $started).TotalSeconds

        if ($script:StopRequested) {
            $script:StatusKeys[[string]$app.id] = 'stopped'
            $item.SubItems[3].Text = (T 'state.stopped')
            $item.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
            $cancelled++
            break
        }

        $kind = Get-ResultKind -Code ([int]$result.Code) -Output ([string]$result.Output)
        $script:StatusKeys[[string]$app.id] = $kind
        switch ($kind) {
            'ok'        { $ok++;        $item.SubItems[3].Text = (T 'state.ok');        $item.ForeColor = [System.Drawing.Color]::FromArgb(22, 163, 74) }
            'already'   { $already++;   $item.SubItems[3].Text = (T 'state.already');   $item.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139) }
            'cancelled' { $cancelled++; $item.SubItems[3].Text = (T 'state.cancelled'); $item.ForeColor = [System.Drawing.Color]::FromArgb(202, 138, 4) }
            default     { $fail++;      $item.SubItems[3].Text = (T 'state.failed');    $item.ForeColor = [System.Drawing.Color]::FromArgb(220, 38, 38) }
        }

        Add-LogLine ('<== {0}: {1}, код {2}, {3} с' -f $app.id, $kind, $result.Code, $elapsed)
        if ($result.Output) {
            foreach ($line in ($result.Output -split "`r?`n")) {
                if ($line -match '[█▒░]') { continue }
                if ($line.Trim() -match '^[-\\|/]$') { continue }
                Add-LogLine ('    ' + $line)
            }
        }
        Add-LogLine ('    Итог: установлено={0}, уже было={1}, ошибок={2}, отменено={3}' -f $ok, $already, $fail, $cancelled)

        $script:progress.Value = [Math]::Min($index, $script:progress.Maximum)
        [System.Windows.Forms.Application]::DoEvents()
    }

    $script:Installing = $false
    $script:progress.Visible   = $false
    $script:btnInstall.Enabled = $true
    $script:btnAll.Enabled     = $true
    $script:btnNone.Enabled    = $true
    $script:btnStop.Enabled    = $false
    $script:cmbCat.Enabled     = $true
    $script:txtSearch.Enabled  = $true
    $script:chkSilent.Enabled  = $true
    if ($script:cmbLang) { $script:cmbLang.Enabled = $true }

    Add-LogLine ''
    Add-LogLine ('==== Готово: установлено {0}, уже было {1}, ошибок {2}, отменено {3} ====' -f $ok, $already, $fail, $cancelled)

    if ($script:StopRequested) {
        Set-Status ((T 'status.stopped') -f $ok, $fail)
    } else {
        Set-Status ((T 'status.done') -f $ok, $already, $fail)
    }

    $summary = ((T 'summary.installed') -f $ok) + "`r`n" +
               ((T 'summary.already') -f $already) + "`r`n" +
               ((T 'summary.failed') -f $fail)
    if ($cancelled -gt 0) { $summary += "`r`n" + ((T 'summary.cancelled') -f $cancelled) }
    if ($fail -gt 0)      { $summary += "`r`n`r`n" + (T 'summary.hint') }
    $icon = if ($fail -gt 0) { 'Warning' } else { 'Information' }
    [void][System.Windows.Forms.MessageBox]::Show($summary, (T 'msg.done.title'), 'OK', $icon)
}

# ----------------------------- иконки -----------------------------
function New-RoundedRectPath {
    param([single]$X, [single]$Y, [single]$W, [single]$H, [single]$R)
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $R * 2
    $p.AddArc($X, $Y, $d, $d, 180, 90)
    $p.AddArc(($X + $W - $d), $Y, $d, $d, 270, 90)
    $p.AddArc(($X + $W - $d), ($Y + $H - $d), $d, $d, 0, 90)
    $p.AddArc($X, ($Y + $H - $d), $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-LetterIcon {
    param([string]$Name)
    $bmp = New-Object System.Drawing.Bitmap 64, 64
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $palette = @(
        [System.Drawing.Color]::FromArgb(37, 99, 235),
        [System.Drawing.Color]::FromArgb(13, 148, 136),
        [System.Drawing.Color]::FromArgb(217, 119, 6),
        [System.Drawing.Color]::FromArgb(147, 51, 234),
        [System.Drawing.Color]::FromArgb(220, 38, 38),
        [System.Drawing.Color]::FromArgb(5, 150, 105),
        [System.Drawing.Color]::FromArgb(71, 85, 105)
    )
    $sum = 0
    foreach ($ch in $Name.ToCharArray()) { $sum += [int]$ch }
    $color = $palette[$sum % $palette.Count]

    $brush = New-Object System.Drawing.SolidBrush $color
    $path = New-RoundedRectPath -X 2 -Y 2 -W 60 -H 60 -R 14
    $g.FillPath($brush, $path)
    $path.Dispose()
    $brush.Dispose()

    $initials = ''
    foreach ($w in ($Name -split '\s+')) {
        if ($w) { $initials += $w.Substring(0, 1).ToUpper() }
        if ($initials.Length -ge 2) { break }
    }
    if (-not $initials) { $initials = '?' }

    $font = New-Object System.Drawing.Font('Segoe UI Semibold', 26, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'
    $sf.LineAlignment = 'Center'
    $rect = [System.Drawing.RectangleF]::new([single]0, [single]0, [single]64, [single]64)
    $g.DrawString($initials, $font, [System.Drawing.Brushes]::White, $rect, $sf)
    $font.Dispose()
    $sf.Dispose()
    $g.Dispose()
    return $bmp
}

function Get-AppIconIndex {
    param([string]$Id, [string]$Name)
    if ($script:IconCache.ContainsKey($Id)) { return $script:IconCache[$Id] }

    $src = $null
    $path = Join-Path $script:IconsDir ($Id + '.png')
    if (Test-Path -LiteralPath $path) {
        try { $src = [System.Drawing.Image]::FromFile($path) } catch { $src = $null }
    }
    if (-not $src) { $src = New-LetterIcon -Name $Name }

    $bmp = New-Object System.Drawing.Bitmap 24, 24
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($src, 0, 0, 24, 24)
    $g.Dispose()
    $src.Dispose()

    $script:iconList.Images.Add($bmp)
    $idx = $script:iconList.Images.Count - 1
    $script:IconCache[$Id] = $idx
    return $idx
}

# ----------------------------- интерфейс -----------------------------
$script:IsSelfTest = [bool]$SelfTest

$accent    = [System.Drawing.Color]::FromArgb(37, 99, 235)
$accentDim = [System.Drawing.Color]::FromArgb(29, 78, 216)
$textMain  = [System.Drawing.Color]::FromArgb(15, 23, 42)
$textMuted = [System.Drawing.Color]::FromArgb(100, 116, 139)
$border    = [System.Drawing.Color]::FromArgb(203, 213, 225)
$panelBg   = [System.Drawing.Color]::FromArgb(248, 250, 252)

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'OneClickInstaller — установка программ'
$form.ClientSize      = [System.Drawing.Size]::new(1080, 740)
$form.MinimumSize     = [System.Drawing.Size]::new(1024, 640)
$form.StartPosition   = 'CenterScreen'
$form.BackColor       = [System.Drawing.Color]::White
$form.Font            = [System.Drawing.Font]::new('Segoe UI', 9)
$form.AutoScaleMode   = 'Font'

$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock        = 'Fill'
$root.ColumnCount = 1
$root.RowCount    = 3
$root.Margin      = [System.Windows.Forms.Padding]::new(0)
$root.Padding     = [System.Windows.Forms.Padding]::new(0)
[void]$root.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, [single]100))
[void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, [single]112))
[void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent, [single]100))
[void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, [single]80))

# --- шапка ---
$topLayout = New-Object System.Windows.Forms.TableLayoutPanel
$topLayout.Dock        = 'Fill'
$topLayout.ColumnCount = 1
$topLayout.RowCount    = 2
$topLayout.Margin      = [System.Windows.Forms.Padding]::new(0)
[void]$topLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, [single]68))
[void]$topLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, [single]44))

$titlePanel = New-Object System.Windows.Forms.Panel
$titlePanel.Dock   = 'Fill'
$titlePanel.Margin = [System.Windows.Forms.Padding]::new(0)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = 'Установка программ'
$lblTitle.Font      = [System.Drawing.Font]::new('Segoe UI Semibold', 16)
$lblTitle.ForeColor = $textMain
$lblTitle.AutoSize  = $true
$lblTitle.Location  = [System.Drawing.Point]::new(22, 10)
[void]$titlePanel.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text      = 'Отметьте нужное и нажмите «Установить» — всё поставится через winget.'
$lblSub.Font      = [System.Drawing.Font]::new('Segoe UI', 9.5)
$lblSub.ForeColor = $textMuted
$lblSub.AutoSize  = $true
$lblSub.Location  = [System.Drawing.Point]::new(24, 44)
[void]$titlePanel.Controls.Add($lblSub)

$toolLayout = New-Object System.Windows.Forms.TableLayoutPanel
$toolLayout.Dock        = 'Fill'
$toolLayout.ColumnCount = 2
$toolLayout.RowCount    = 1
$toolLayout.Margin      = [System.Windows.Forms.Padding]::new(0)
[void]$toolLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, [single]100))
[void]$toolLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, [single]340))

$leftFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$leftFlow.Dock           = 'Fill'
$leftFlow.FlowDirection  = 'LeftToRight'
$leftFlow.WrapContents   = $false
$leftFlow.Padding        = [System.Windows.Forms.Padding]::new(20, 5, 0, 0)
$leftFlow.Margin         = [System.Windows.Forms.Padding]::new(0)

$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text      = 'Поиск:'
$lblSearch.AutoSize  = $true
$lblSearch.ForeColor = $textMuted
$lblSearch.Margin    = [System.Windows.Forms.Padding]::new(0, 9, 6, 0)
[void]$leftFlow.Controls.Add($lblSearch)

$script:txtSearch = New-Object System.Windows.Forms.TextBox
$script:txtSearch.Width       = 180
$script:txtSearch.Font        = [System.Drawing.Font]::new('Segoe UI', 9.5)
$script:txtSearch.BorderStyle = 'FixedSingle'
$script:txtSearch.Margin      = [System.Windows.Forms.Padding]::new(0, 4, 10, 0)
[void]$leftFlow.Controls.Add($script:txtSearch)

$lblCat = New-Object System.Windows.Forms.Label
$lblCat.Text      = 'Категория:'
$lblCat.AutoSize  = $true
$lblCat.ForeColor = $textMuted
$lblCat.Margin    = [System.Windows.Forms.Padding]::new(0, 9, 6, 0)
[void]$leftFlow.Controls.Add($lblCat)

$script:cmbCat = New-Object System.Windows.Forms.ComboBox
$script:cmbCat.Width             = 150
$script:cmbCat.DropDownStyle     = 'DropDownList'
$script:cmbCat.FlatStyle         = 'Flat'
$script:cmbCat.Font              = [System.Drawing.Font]::new('Segoe UI', 9.5)
$script:cmbCat.Margin            = [System.Windows.Forms.Padding]::new(0, 4, 10, 0)
[void]$leftFlow.Controls.Add($script:cmbCat)

$script:btnAll = New-Object System.Windows.Forms.Button
$script:btnAll.Text      = 'Выбрать всё'
$script:btnAll.Size      = [System.Drawing.Size]::new(104, 28)
$script:btnAll.FlatStyle = 'Flat'
$script:btnAll.BackColor = [System.Drawing.Color]::White
$script:btnAll.ForeColor = $textMain
$script:btnAll.FlatAppearance.BorderColor = $border
$script:btnAll.Cursor    = 'Hand'
$script:btnAll.Margin    = [System.Windows.Forms.Padding]::new(0, 4, 8, 0)
[void]$leftFlow.Controls.Add($script:btnAll)

$script:btnNone = New-Object System.Windows.Forms.Button
$script:btnNone.Text      = 'Снять всё'
$script:btnNone.Size      = [System.Drawing.Size]::new(96, 28)
$script:btnNone.FlatStyle = 'Flat'
$script:btnNone.BackColor = [System.Drawing.Color]::White
$script:btnNone.ForeColor = $textMain
$script:btnNone.FlatAppearance.BorderColor = $border
$script:btnNone.Cursor    = 'Hand'
$script:btnNone.Margin    = [System.Windows.Forms.Padding]::new(0, 4, 0, 0)
[void]$leftFlow.Controls.Add($script:btnNone)

$rightFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$rightFlow.Dock          = 'Fill'
$rightFlow.FlowDirection = 'RightToLeft'
$rightFlow.WrapContents  = $false
$rightFlow.Padding       = [System.Windows.Forms.Padding]::new(0, 7, 20, 0)
$rightFlow.Margin        = [System.Windows.Forms.Padding]::new(0)

$script:chkSilent = New-Object System.Windows.Forms.CheckBox
$script:chkSilent.Text     = 'Тихая установка'
$script:chkSilent.AutoSize = $true
$script:chkSilent.Checked  = [bool]$script:Silent
$script:chkSilent.ForeColor = $textMain
$script:chkSilent.Margin   = [System.Windows.Forms.Padding]::new(0, 4, 0, 0)
[void]$rightFlow.Controls.Add($script:chkSilent)

$script:cmbLang = New-Object System.Windows.Forms.ComboBox
$script:cmbLang.Width         = 120
$script:cmbLang.DropDownStyle = 'DropDownList'
$script:cmbLang.FlatStyle     = 'Flat'
$script:cmbLang.Font          = [System.Drawing.Font]::new('Segoe UI', 9.5)
$script:cmbLang.Margin        = [System.Windows.Forms.Padding]::new(14, 4, 0, 0)
[void]$script:cmbLang.Items.Add('Русский')
[void]$script:cmbLang.Items.Add('English')
[void]$rightFlow.Controls.Add($script:cmbLang)

[void]$toolLayout.Controls.Add($leftFlow, 0, 0)
[void]$toolLayout.Controls.Add($rightFlow, 1, 0)
[void]$topLayout.Controls.Add($titlePanel, 0, 0)
[void]$topLayout.Controls.Add($toolLayout, 0, 1)

# --- список ---
$script:IconCache = @{}
$script:iconList = New-Object System.Windows.Forms.ImageList
$script:iconList.ImageSize  = [System.Drawing.Size]::new(24, 24)
$script:iconList.ColorDepth = [System.Windows.Forms.ColorDepth]::Depth32Bit
foreach ($app in $script:Apps) {
    $script:Items[[string]$app.id].ImageIndex = Get-AppIconIndex -Id ([string]$app.id) -Name ([string]$app.name)
}

$script:lv = New-Object System.Windows.Forms.ListView
$script:lv.Dock          = 'Fill'
$script:lv.View          = 'Details'
$script:lv.CheckBoxes    = $true
$script:lv.FullRowSelect = $true
$script:lv.HideSelection = $false
$script:lv.MultiSelect   = $false
$script:lv.BorderStyle   = 'FixedSingle'
$script:lv.HeaderStyle   = 'Nonclickable'
$script:lv.Font          = [System.Drawing.Font]::new('Segoe UI', 9.5)
$script:lv.Margin        = [System.Windows.Forms.Padding]::new(20, 2, 20, 0)
$script:lv.ShowItemToolTips = $true
$script:lv.SmallImageList   = $script:iconList
[void]$script:lv.Columns.Add('Программа', 250)
[void]$script:lv.Columns.Add('Категория', 145)
$colDesc = $script:lv.Columns.Add('Описание', 400)
[void]$script:lv.Columns.Add('Статус', 135)

# --- низ: статус и кнопки ---
$panelBottom = New-Object System.Windows.Forms.Panel
$panelBottom.Dock      = 'Fill'
$panelBottom.BackColor = $panelBg
$panelBottom.Margin    = [System.Windows.Forms.Padding]::new(0)

$bottomLayout = New-Object System.Windows.Forms.TableLayoutPanel
$bottomLayout.Dock        = 'Fill'
$bottomLayout.ColumnCount = 2
$bottomLayout.RowCount    = 1
$bottomLayout.Padding     = [System.Windows.Forms.Padding]::new(20, 0, 0, 0)
[void]$bottomLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, [single]100))
[void]$bottomLayout.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Absolute, [single]730))

$statusPanel = New-Object System.Windows.Forms.TableLayoutPanel
$statusPanel.Dock        = 'Fill'
$statusPanel.ColumnCount = 1
$statusPanel.RowCount    = 2
$statusPanel.Margin      = [System.Windows.Forms.Padding]::new(0, 0, 10, 0)
[void]$statusPanel.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, [single]26))
[void]$statusPanel.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, [single]26))

$script:lblStatus = New-Object System.Windows.Forms.Label
$script:lblStatus.Dock         = 'Fill'
$script:lblStatus.TextAlign    = 'MiddleLeft'
$script:lblStatus.AutoEllipsis = $true
$script:lblStatus.ForeColor    = $textMain
$script:lblStatus.Font         = [System.Drawing.Font]::new('Segoe UI', 9.5)
[void]$statusPanel.Controls.Add($script:lblStatus, 0, 0)

$script:progress = New-Object System.Windows.Forms.ProgressBar
$script:progress.Dock    = 'Fill'
$script:progress.Style   = 'Continuous'
$script:progress.Margin  = [System.Windows.Forms.Padding]::new(0, 4, 0, 10)
$script:progress.Visible = $false
[void]$statusPanel.Controls.Add($script:progress, 0, 1)

$flowBtns = New-Object System.Windows.Forms.FlowLayoutPanel
$flowBtns.Dock          = 'Fill'
$flowBtns.FlowDirection = 'RightToLeft'
$flowBtns.WrapContents  = $false
$flowBtns.Padding       = [System.Windows.Forms.Padding]::new(0, 20, 16, 0)
$flowBtns.Margin        = [System.Windows.Forms.Padding]::new(0)

function New-SecondaryButton {
    param([string]$Text, [int]$Width)
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $Text
    $b.Size      = [System.Drawing.Size]::new($Width, 36)
    $b.FlatStyle = 'Flat'
    $b.BackColor = [System.Drawing.Color]::White
    $b.ForeColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
    $b.FlatAppearance.BorderSize  = 1
    $b.FlatAppearance.BorderColor = $border
    $b.Cursor    = 'Hand'
    $b.Font      = [System.Drawing.Font]::new('Segoe UI', 9)
    $b.Margin    = [System.Windows.Forms.Padding]::new(8, 0, 0, 0)
    return $b
}

$script:btnInstall = New-Object System.Windows.Forms.Button
$script:btnInstall.Text      = 'Установить выбранное'
$script:btnInstall.Size      = [System.Drawing.Size]::new(200, 36)
$script:btnInstall.FlatStyle = 'Flat'
$script:btnInstall.BackColor = $accent
$script:btnInstall.ForeColor = [System.Drawing.Color]::White
$script:btnInstall.FlatAppearance.BorderSize = 0
$script:btnInstall.FlatAppearance.MouseOverBackColor = $accentDim
$script:btnInstall.Font      = [System.Drawing.Font]::new('Segoe UI Semibold', 9.5)
$script:btnInstall.Cursor    = 'Hand'
$script:btnInstall.Margin    = [System.Windows.Forms.Padding]::new(0)
[void]$flowBtns.Controls.Add($script:btnInstall)

$script:btnStop = New-SecondaryButton -Text 'Остановить' -Width 110
$script:btnStop.Enabled = $false
[void]$flowBtns.Controls.Add($script:btnStop)

[void]$bottomLayout.Controls.Add($statusPanel, 0, 0)
[void]$bottomLayout.Controls.Add($flowBtns, 1, 0)
[void]$panelBottom.Controls.Add($bottomLayout)

[void]$root.Controls.Add($topLayout, 0, 0)
[void]$root.Controls.Add($script:lv, 0, 1)
[void]$root.Controls.Add($panelBottom, 0, 2)
[void]$form.Controls.Add($root)

# ----------------------------- логика интерфейса -----------------------------
function Update-Filter {
    $q   = $script:txtSearch.Text.Trim()
    $cat = ''
    if ($script:cmbCat.SelectedIndex -gt 0 -and $script:cmbCat.SelectedIndex -lt $script:CatValues.Count) {
        $cat = [string]$script:CatValues[$script:cmbCat.SelectedIndex]
    }

    $script:Suppress = $true
    $script:lv.BeginUpdate()
    try {
        $script:lv.Items.Clear()
        foreach ($app in $script:Apps) {
            $okCat = ($cat -eq '' -or [string]$app.category -eq $cat)
            $okQ   = $true
            if ($q -ne '') {
                $hay = @(
                    [string]$app.name,
                    [string]$app.desc,
                    [string]$app.desc_en,
                    [string]$app.category,
                    (T-Category ([string]$app.category)),
                    [string]$app.id
                ) -join "`n"
                $okQ = ($hay -like "*$q*")
            }
            if ($okCat -and $okQ) { [void]$script:lv.Items.Add($script:Items[[string]$app.id]) }
        }
    } finally {
        $script:lv.EndUpdate()
        $script:Suppress = $false
    }
    Set-CountText
}

$script:AllCats   = @($script:Apps | ForEach-Object { [string]$_.category } | Where-Object { $_ } | Sort-Object -Unique)
$script:CatValues = @()
$script:StatusKeys = @{}

function Fill-Categories {
    $prev = ''
    if ($script:cmbCat.SelectedIndex -gt 0 -and $script:cmbCat.SelectedIndex -lt $script:CatValues.Count) {
        $prev = [string]$script:CatValues[$script:cmbCat.SelectedIndex]
    }

    $script:CatValues = @('')
    $script:cmbCat.BeginUpdate()
    try {
        $script:cmbCat.Items.Clear()
        [void]$script:cmbCat.Items.Add((T 'cat.all'))
        foreach ($c in $script:AllCats) {
            $script:CatValues += $c
            [void]$script:cmbCat.Items.Add((T-Category $c))
        }
        $idx = 0
        if ($prev) {
            $i = [array]::IndexOf($script:CatValues, $prev)
            if ($i -gt 0) { $idx = $i }
        }
        $script:cmbCat.SelectedIndex = $idx
    } finally {
        $script:cmbCat.EndUpdate()
    }
}

$script:txtSearch.Add_TextChanged({ Update-Filter })
$script:cmbCat.Add_SelectedIndexChanged({ Update-Filter })

$script:txtSearch.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $script:txtSearch.Clear() }
})

$script:btnAll.Add_Click({
    if ($script:Installing) { return }
    $script:Suppress = $true
    try { foreach ($it in $script:lv.Items) { $it.Checked = $true } }
    finally { $script:Suppress = $false }
    Set-CountText
})

$script:btnNone.Add_Click({
    if ($script:Installing) { return }
    $script:Suppress = $true
    try { foreach ($it in $script:lv.Items) { $it.Checked = $false } }
    finally { $script:Suppress = $false }
    Set-CountText
})

$script:lv.Add_DoubleClick({
    if ($script:Installing) { return }
    if ($script:lv.SelectedItems.Count -eq 0) { return }
    $it = $script:lv.SelectedItems[0]
    $it.Checked = -not $it.Checked
    Set-CountText
})

$script:lv.Add_Resize({
    $w = $script:lv.ClientSize.Width - 250 - 145 - 135 - 4
    if ($w -lt 160) { $w = 160 }
    $colDesc.Width = $w
})

$script:btnInstall.Add_Click({ Start-Install })
$script:btnStop.Add_Click({
    if (-not $script:Installing) { return }
    $script:StopRequested = $true
    Set-Status (T 'status.stopping')
    Add-LogLine '!! Запрошена остановка пользователем'
})

$script:form = $form
$form.Add_FormClosing({
    param($s, $e)
    if ($script:Installing) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            (T 'msg.close.text'), (T 'msg.close.title'), 'YesNo', 'Warning')
        if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { $e.Cancel = $true; return }
        $script:StopRequested = $true
    }
    if (-not $script:IsSelfTest) { Save-Settings }
})

# ----------------------------- язык -----------------------------
$script:LangLock = $false

function Apply-Language {
    $form.Text                = (T 'form.title')
    $lblTitle.Text            = (T 'title')
    $lblSub.Text              = (T 'subtitle')
    $lblSearch.Text           = (T 'search')
    $lblCat.Text              = (T 'category')
    $script:btnAll.Text       = (T 'all')
    $script:btnNone.Text      = (T 'none')
    $script:chkSilent.Text    = (T 'silent')
    $script:btnInstall.Text   = (T 'btn.install')
    $script:btnStop.Text      = (T 'btn.stop')
    $script:lv.Columns[0].Text = (T 'col.program')
    $script:lv.Columns[1].Text = (T 'col.category')
    $script:lv.Columns[2].Text = (T 'col.desc')
    $script:lv.Columns[3].Text = (T 'col.status')

    foreach ($app in $script:Apps) {
        $it = $script:Items[[string]$app.id]
        if (-not $it) { continue }
        $it.SubItems[1].Text = (T-Category ([string]$app.category))
        $it.SubItems[2].Text = (Get-AppDesc $app)
        $it.ToolTipText      = '{0}  ·  {1}' -f $app.id, (Get-AppDesc $app)
        $id = [string]$app.id
        if ($script:StatusKeys.ContainsKey($id)) {
            $suffix = [string]$script:StatusKeys[$id]
            if ($suffix -eq 'fail') { $suffix = 'failed' }
            $key = 'state.' + $suffix
            $table = $script:Strings[$script:Lang]
            if ($table.ContainsKey($key)) { $it.SubItems[3].Text = $table[$key] }
        }
    }

    $script:LangLock = $true
    try {
        $script:cmbLang.SelectedIndex = if ($script:Lang -eq 'en') { 1 } else { 0 }
        Fill-Categories
    } finally {
        $script:LangLock = $false
    }
    Set-CountText
}

$script:cmbLang.Add_SelectedIndexChanged({
    if ($script:LangLock) { return }
    $newLang = if ($script:cmbLang.SelectedIndex -eq 1) { 'en' } else { 'ru' }
    if ($newLang -eq $script:Lang) { return }
    $script:Lang = $newLang
    Apply-Language
})

# обновление счётчика выбранного
$countTimer = New-Object System.Windows.Forms.Timer
$countTimer.Interval = 200
$countTimer.Add_Tick({
    if ($script:Installing) { return }
    $n = @($script:Items.Values | Where-Object { $_.Checked }).Count
    if ($n -ne $script:SelectedCount) {
        $script:SelectedCount = $n
        Set-Status ((T 'status.selected') -f $n, $script:Apps.Count)
    }
})

# ----------------------------- запуск -----------------------------
$script:UiReady = $true
Apply-Language
Update-Filter
$countTimer.Start()
Add-LogLine ('OneClickInstaller · {0}' -f (Get-Date -Format 'dd.MM.yyyy HH:mm'))
Add-LogLine ('Скрипт: ' + $script:ScriptPath)
Add-LogLine ('Журнал: ' + $script:LogPath)
Add-LogLine 'Выберите программы и нажмите «Установить выбранное».'

if ($SelfTest) {
    $script:uiSelfTestTimer = New-Object System.Windows.Forms.Timer
    $script:uiSelfTestTimer.Interval = 700
    $script:uiSelfTestTimer.Add_Tick({
        $script:uiSelfTestTimer.Stop()
        $script:form.Close()
    })
    $script:uiSelfTestTimer.Start()
    [void]$form.ShowDialog()
    $countTimer.Stop()
    Write-Output 'SELF-TEST OK'
    return
}

[void]$form.ShowDialog()
$countTimer.Stop()



