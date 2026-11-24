# Builds OneClickInstaller.exe (single file with script, apps.json and icons inside).
# Run: powershell -ExecutionPolicy Bypass -File build\build.ps1

$ErrorActionPreference = 'Stop'
$build = Split-Path -Parent $MyInvocation.MyCommand.Path
$root  = Split-Path -Parent $build

Add-Type -AssemblyName System.Drawing

# ---- 1. app icon (256x256 PNG -> ICO) ----
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

$png = Join-Path $build 'app.png'
$bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
$pngBytes = [System.IO.File]::ReadAllBytes($png)
$fs = [System.IO.File]::Create((Join-Path $build 'app.ico'))
$bw = New-Object System.IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)
$bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0)
$bw.Write([uint16]1); $bw.Write([uint16]32)
$bw.Write([uint32]$pngBytes.Length); $bw.Write([uint32]22)
$bw.Write($pngBytes)
$bw.Close(); $fs.Close(); $bmp.Dispose()

# ---- 2. payload (script + apps.json + icons) ----
$payload = Join-Path $build 'payload'
if (Test-Path $payload) { Remove-Item $payload -Recurse -Force }
New-Item -ItemType Directory -Force -Path $payload | Out-Null
Copy-Item (Join-Path $root 'OneClickInstaller.ps1') $payload
Copy-Item (Join-Path $root 'apps.json') $payload
Copy-Item (Join-Path $root 'icons') $payload -Recurse
Compress-Archive -Path (Join-Path $payload '*') -DestinationPath (Join-Path $build 'payload.zip') -Force

# ---- 3. compile ----
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw "csc.exe not found: $csc" }

Push-Location $build
try {
    & $csc /nologo /target:winexe /platform:anycpu /optimize+ `
        /win32icon:app.ico /out:OneClickInstaller.exe `
        /resource:payload.zip,payload.zip `
        /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll `
        /r:System.Windows.Forms.dll /r:System.Drawing.dll Launcher.cs
    if ($LASTEXITCODE -ne 0) { throw "csc failed with $LASTEXITCODE" }
} finally {
    Pop-Location
}

$exe = Join-Path $build 'OneClickInstaller.exe'
"Built: $exe ($((Get-Item $exe).Length) bytes)"

$desktopExe = Join-Path ([Environment]::GetFolderPath('Desktop')) 'OneClickInstaller.exe'
Copy-Item $exe $desktopExe -Force
"Copied: $desktopExe"
