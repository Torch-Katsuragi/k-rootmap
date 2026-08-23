#!/usr/bin/env pwsh
<#
.SYNOPSIS
  指定したウィンドウだけをPNGにキャプチャする（デスクトップ全体は撮らない）。

.DESCRIPTION
  Windows版の地図が実際に描けているかを確認するための道具。

  Flutter側の手段は使えない:
    flutter screenshot --type=device … "Screenshot not supported for Windows."（Android/iOS専用）
    flutter screenshot --type=skia   … Flutterのレイヤツリーだけ。**地図が写らない**
    RepaintBoundary / takeScreenshot … 同上
  Windows版の地図は WebView2 のネイティブサーフェスで、Flutterのラスタライズ外で
  合成されている。地図を見るにはOSレベルのウィンドウキャプチャしかない。

  取得方法は2つ:
    Print  … PrintWindow(PW_RENDERFULLCONTENT)。**前面でなくても撮れる**。
             ただしハードウェア合成の子サーフェス（WebView2等）が
             空白で返ることがある
    Screen … ウィンドウ矩形を画面からBitBltで切り出す。合成後の絵なので
             WebView2も写るが、**画面に見えている必要がある**（他ウィンドウに
             隠れているとその部分が写ってしまう）

  既定は Auto: Print を試し、中身がほぼ単色なら Screen に落とす。

.PARAMETER ProcessName
  対象プロセス名（拡張子なし）。既定 k_maps。

.PARAMETER TitleLike
  ウィンドウタイトルの部分一致。ProcessName で複数見つかるときに絞る。

.PARAMETER Out
  出力PNGパス。既定 .temp/window_capture.png

.PARAMETER Mode
  Auto / Print / Screen

.EXAMPLE
  pwsh tool/capture_window.ps1
  pwsh tool/capture_window.ps1 -Out .temp/map.png -Mode Screen
#>
[CmdletBinding()]
param(
  [string]$ProcessName = 'k_maps',
  [string]$TitleLike,
  [string]$Out,
  [ValidateSet('Auto', 'Print', 'Screen')]
  [string]$Mode = 'Auto'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Out) { $Out = Join-Path $repoRoot '.temp/window_capture.png' }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Out) | Out-Null

Add-Type -AssemblyName System.Drawing

# P/Invoke だけをC#で定義する。
# ビットマップ操作までC#に入れると System.Drawing.Common の型転送
# （.NET 10 では System.Private.Windows.GdiPlus へ転送される）で
# 参照アセンブリの解決に失敗するため、描画処理はPowerShell側で行う。
if (-not ('Win32Win' -as [type])) {
  Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class Win32Win {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT value, int size);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }
}
'@
}

# 物理ピクセルで矩形を取るためDPI認識にする（高DPIで座標がズレるのを防ぐ）
[void][Win32Win]::SetProcessDPIAware()

$procs = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 })
if ($TitleLike) {
  $procs = @($procs | Where-Object { $_.MainWindowTitle -like "*$TitleLike*" })
}
if ($procs.Count -eq 0) {
  Write-Error "ウィンドウが見つからない (ProcessName=$ProcessName TitleLike=$TitleLike)"
  exit 1
}
$proc = $procs[0]
$hwnd = $proc.MainWindowHandle

if ([Win32Win]::IsIconic($hwnd)) {
  Write-Error "ウィンドウが最小化されている。復元してから撮ること（PID=$($proc.Id)）"
  exit 1
}

# DWMWA_EXTENDED_FRAME_BOUNDS = 9。影を含まない実際の枠を取る。
$rect = New-Object Win32Win+RECT
$hr = [Win32Win]::DwmGetWindowAttribute(
  $hwnd, 9, [ref]$rect, [System.Runtime.InteropServices.Marshal]::SizeOf($rect))
if ($hr -ne 0) { Write-Error "DwmGetWindowAttribute failed (hr=$hr)"; exit 1 }

$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
if ($width -le 0 -or $height -le 0) { Write-Error "ウィンドウ矩形が不正 ${width}x${height}"; exit 1 }

Write-Host "target: PID=$($proc.Id) title='$($proc.MainWindowTitle)' ${width}x${height}"

# 中身がほぼ単色か（PrintWindowが空を返したかの判定用）。
# 端を避けて格子状にサンプリングし、異なる色の数を数える。
function Get-SampleColorCount {
  param([System.Drawing.Bitmap]$Bitmap)
  $seen = [System.Collections.Generic.HashSet[int]]::new()
  $stepX = [Math]::Max(1, [int]($Bitmap.Width / 40))
  $stepY = [Math]::Max(1, [int]($Bitmap.Height / 40))
  for ($y = $stepY; $y -lt $Bitmap.Height - $stepY; $y += $stepY) {
    for ($x = $stepX; $x -lt $Bitmap.Width - $stepX; $x += $stepX) {
      [void]$seen.Add($Bitmap.GetPixel($x, $y).ToArgb())
    }
  }
  return $seen.Count
}

function Get-PrintWindowBitmap {
  $bmp = New-Object System.Drawing.Bitmap($width, $height)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    $hdc = $g.GetHdc()
    try {
      # PW_RENDERFULLCONTENT = 2（Windows 8.1+）。DWM合成の内容も描かせる。
      [void][Win32Win]::PrintWindow($hwnd, $hdc, 2)
    }
    finally { $g.ReleaseHdc($hdc) }
  }
  finally { $g.Dispose() }
  return $bmp
}

function Get-ScreenBitmap {
  $bmp = New-Object System.Drawing.Bitmap($width, $height)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size($width, $height)))
  }
  finally { $g.Dispose() }
  return $bmp
}

$bmp = $null
$used = $Mode

if ($Mode -eq 'Screen') {
  $bmp = Get-ScreenBitmap
}
else {
  $bmp = Get-PrintWindowBitmap
  $colors = Get-SampleColorCount -Bitmap $bmp
  $used = 'Print'
  if ($Mode -eq 'Auto' -and $colors -le 2) {
    Write-Host "PrintWindow の結果がほぼ単色（色数=$colors）。Screen に切り替える" -ForegroundColor Yellow
    $bmp.Dispose()
    $bmp = Get-ScreenBitmap
    $used = 'Screen'
  }
  else {
    Write-Host "PrintWindow OK（サンプル色数=$colors）"
  }
}

$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

$size = [math]::Round((Get-Item $Out).Length / 1KB)
Write-Host "saved: $Out (${size}KB, mode=$used)"
