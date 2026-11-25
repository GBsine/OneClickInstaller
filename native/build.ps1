# Собирает нативный OneClickInstaller.exe (C# WinForms, без PowerShell и самораспаковки).
# Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File native\build.ps1

$ErrorActionPreference = 'Stop'
$native = Split-Path -Parent $MyInvocation.MyCommand.Path
$root   = Split-Path -Parent $native
$out    = Join-Path $native 'OneClickInstaller.exe'

Add-Type -AssemblyName System.Drawing

# ---- 1. иконка приложения (256x256 PNG -> ICO) ----
$size = 256
$bmp = New-Object System.Drawing.Bitmap $size, $size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$blue = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(37, 99, 235))
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$r = 52; $x = 12; $y = 12; $w = 232; $h = 232; $d = $r * 2
$path.AddArc($x, $y, $d, $d, 180, 90)
$path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
$path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
$path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
$path.CloseFigure()
$g.FillPath($blue, $path)
$white = [System.Drawing.Brushes]::White
$pts = @(
    (New-Object System.Drawing.PointF 108, 42), (New-Object System.Drawing.PointF 148, 42),
    (New-Object System.Drawing.PointF 148, 116), (New-Object System.Drawing.PointF 186, 116),
    (New-Object System.Drawing.PointF 128, 190), (New-Object System.Drawing.PointF 70, 116),
    (New-Object System.Drawing.PointF 108, 116)
)
$g.FillPolygon($white, $pts)
$bar = New-Object System.Drawing.Drawing2D.GraphicsPath
$bx = 70; $by = 204; $bw = 116; $bh = 16; $bd = 16
$bar.AddArc($bx, $by, $bd, $bd, 180, 90)
$bar.AddArc($bx + $bw - $bd, $by, $bd, $bd, 270, 90)
$bar.AddArc($bx + $bw - $bd, $by + $bh - $bd, $bd, $bd, 0, 90)
$bar.AddArc($bx, $by + $bh - $bd, $bd, $bd, 90, 90)
$bar.CloseFigure()
$g.FillPath($white, $bar)
$g.Dispose()

$png = Join-Path $native 'app.png'
$bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
$pngBytes = [System.IO.File]::ReadAllBytes($png)
$fs = [System.IO.File]::Create((Join-Path $native 'app.ico'))
$bw = New-Object System.IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)
$bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0)
$bw.Write([uint16]1); $bw.Write([uint16]32)
$bw.Write([uint32]$pngBytes.Length); $bw.Write([uint32]22)
$bw.Write($pngBytes)
$bw.Close(); $fs.Close(); $bmp.Dispose()

# ---- 2. ресурсы: apps.json + иконки ----
$resources = @()
$resources += ('/resource:"{0}",apps.json' -f (Join-Path $root 'apps.json'))
foreach ($icon in Get-ChildItem (Join-Path $root 'icons') -Filter *.png) {
    $resources += ('/resource:"{0}",icons.{1}' -f $icon.FullName, $icon.Name)
}

# ---- 3. компиляция ----
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw "csc.exe not found: $csc" }

$cscArgs = @(
    '/nologo', '/target:winexe', '/platform:anycpu', '/optimize+',
    '/win32icon:app.ico',
    '/win32manifest:app.manifest',
    ('/out:"{0}"' -f $out),
    '/r:System.dll', '/r:System.Core.dll',
    '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll',
    '/r:System.Runtime.Serialization.dll'
) + $resources + @('OneClickInstaller.cs')

Push-Location $native
try {
    & $csc $cscArgs
    if ($LASTEXITCODE -ne 0) { throw "csc failed with $LASTEXITCODE" }
} finally {
    Pop-Location
}

"Built: $out ($((Get-Item $out).Length) bytes)"

$desktopExe = Join-Path ([Environment]::GetFolderPath('Desktop')) 'OneClickInstaller.exe'
Copy-Item $out $desktopExe -Force
"Copied: $desktopExe"
