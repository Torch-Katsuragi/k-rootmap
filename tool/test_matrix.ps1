#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Windows と Android の両方でテストを回し、結果を一覧で出す。

.DESCRIPTION
  Windows版の復活作業では「Windowsを直したらAndroidが壊れた」が最大のリスクなので、
  片方だけ緑になっても意味がない。このスクリプトは両プラットフォームを1コマンドで
  通し、どの段で落ちたかを表で示す。

  段:
    analyze        静的解析（プラットフォーム非依存）
    unit           test/ 配下のユニットテスト（ホストVM）
    build:windows  Windowsのコンパイルゲート
    e2e:windows    integration_test/ を Windows デスクトップで実行
    build:android  Androidのコンパイルゲート（debug APK）
    e2e:android    integration_test/ を Android 実機/エミュで実行

.PARAMETER Only
  実行する段をカンマ区切りで指定する（例: -Only analyze,unit）

.PARAMETER SkipAndroid
  Android の段をすべて飛ばす

.PARAMETER SkipWindows
  Windows の段をすべて飛ばす

.PARAMETER Emulator
  Android実機が繋がっていないときに起動するエミュレータID
  （既定: flutter emulators の先頭）
  ※実機が繋がっていれば常に実機を優先する。エミュはフォールバック。

.EXAMPLE
  pwsh tool/test_matrix.ps1
  pwsh tool/test_matrix.ps1 -Only analyze,unit
  pwsh tool/test_matrix.ps1 -SkipAndroid
#>
[CmdletBinding()]
param(
  [string[]]$Only,
  [switch]$SkipAndroid,
  [switch]$SkipWindows,
  [string]$Emulator
)

$ErrorActionPreference = 'Continue'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$script:results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
  param([string]$Stage, [string]$Status, [double]$Seconds, [string]$Note = '')
  $script:results.Add([pscustomobject]@{
      Stage   = $Stage
      Status  = $Status
      Seconds = [math]::Round($Seconds, 1)
      Note    = $Note
    })
}

# pwsh -File 経由だと "-Only analyze,unit" が1要素の文字列として渡るため、
# ここでカンマ区切りを展開してから使う。
$wantedStages = @()
if ($Only) { $wantedStages = @($Only -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

function Test-Wanted {
  param([string]$Stage)
  if ($wantedStages.Count -eq 0) { return $true }
  return $wantedStages -contains $Stage
}

function Invoke-Stage {
  param(
    [string]$Stage,
    [scriptblock]$Body,
    [string]$LogName
  )
  if (-not (Test-Wanted $Stage)) {
    Add-Result $Stage 'SKIP' 0 '-Only で対象外'
    return
  }
  Write-Host ''
  Write-Host "=== $Stage ===" -ForegroundColor Cyan
  $logPath = Join-Path $logDir "$LogName.log"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $Body 2>&1 | Tee-Object -FilePath $logPath
  $code = $LASTEXITCODE
  $sw.Stop()
  if ($code -eq 0) {
    Add-Result $Stage 'PASS' $sw.Elapsed.TotalSeconds
  }
  else {
    Add-Result $Stage 'FAIL' $sw.Elapsed.TotalSeconds "exit=$code / $logPath"
  }
}

# integration_test/ を1ファイルずつ実行する。
#
# `flutter test integration_test -d <device>` とディレクトリ指定で回すと、
# 2本目以降が "The log reader stopped unexpectedly, or never started." で
# 起動に失敗する（1本ずつなら通る）。原因はFlutter側のデスクトップ実行の
# 後始末にあるとみられるため、ここではファイル単位で起動し直す。
function Invoke-IntegrationTests {
  param(
    [Parameter(Mandatory)][string]$DeviceId
  )
  # support/ はヘルパ置き場なのでテスト対象から外す
  $files = Get-ChildItem -Path (Join-Path $repoRoot 'integration_test') -Filter '*_test.dart' -File |
    Sort-Object Name
  if ($files.Count -eq 0) {
    Write-Host 'integration_test/ にテストが無い'
    $global:LASTEXITCODE = 0
    return
  }

  $anyFailed = $false
  foreach ($f in $files) {
    $rel = 'integration_test/' + $f.Name
    Write-Host ''
    Write-Host "--- $rel ($DeviceId) ---" -ForegroundColor DarkCyan
    flutter test $rel -d $DeviceId
    if ($LASTEXITCODE -ne 0) {
      $anyFailed = $true
      Write-Host "FAILED: $rel" -ForegroundColor Red
    }
  }
  $global:LASTEXITCODE = if ($anyFailed) { 1 } else { 0 }
}

# ログ置き場。AGENTS.md の規約により .temp/ （gitignore済み）に出す。
$logDir = Join-Path $repoRoot '.temp/test_matrix'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# --- プラットフォーム非依存 ---------------------------------------------------

Invoke-Stage 'analyze' { flutter analyze } 'analyze'
Invoke-Stage 'unit' { flutter test } 'unit'

# --- Windows -----------------------------------------------------------------

if ($SkipWindows) {
  foreach ($s in 'build:windows', 'e2e:windows') { Add-Result $s 'SKIP' 0 '-SkipWindows' }
}
else {
  Invoke-Stage 'build:windows' { flutter build windows --debug } 'build_windows'
  Invoke-Stage 'e2e:windows' { Invoke-IntegrationTests -DeviceId 'windows' } 'e2e_windows'
}

# --- Android -----------------------------------------------------------------

# 接続中のAndroid端末を返す。**実機を優先する**。
#
# エミュはCPU/GPUが実機と別物で、性能の数字も描画の挙動もあてにならない。
# 実機が繋がっているならそちらを使う（2026-08-21 方針）。実機が無いときだけエミュに落とす。
function Get-AndroidDeviceId {
  $physical = @()
  $emulators = @()
  foreach ($line in (& adb devices 2>$null)) {
    # "<serial><TAB>device" の行だけを拾う（offline/unauthorized は除く）
    if ($line -match '^(\S+)\s+device$') {
      $serial = $Matches[1]
      if ($serial -like 'emulator-*') { $emulators += $serial }
      else { $physical += $serial }
    }
  }
  if ($physical.Count -gt 0) { return $physical[0] }
  if ($emulators.Count -gt 0) { return $emulators[0] }
  return $null
}

function Start-AndroidEmulator {
  param([string]$Id)
  if (-not $Id) {
    $line = (& flutter emulators 2>$null | Select-String -Pattern '^\S+\s+•.*•\s+android\s*$' | Select-Object -First 1)
    if (-not $line) { return $null }
    $Id = ($line.ToString() -split '\s*•\s*')[0].Trim()
  }
  Write-Host "エミュレータを起動: $Id" -ForegroundColor Yellow
  Start-Process -FilePath 'flutter' -ArgumentList 'emulators', '--launch', $Id -WindowStyle Hidden | Out-Null

  # 起動完了待ち（最大180秒）
  $deadline = (Get-Date).AddSeconds(180)
  while ((Get-Date) -lt $deadline) {
    $serial = Get-AndroidDeviceId
    if ($serial) {
      $booted = (& adb -s $serial shell getprop sys.boot_completed 2>$null | Out-String).Trim()
      if ($booted -eq '1') { return $serial }
    }
    Start-Sleep -Seconds 5
  }
  return $null
}

# Android端末の空き容量を確認する。
#
# debug APK は 230MB 超あり、テストはファイルごとに入れ直す。エミュを使い回していると
# `INSTALL_FAILED_INSUFFICIENT_STORAGE` で落ちるが、エラーだけ見ても原因が分かりにくい
# （device not found として現れることもある）。先に見て、足りなければはっきり言う。
function Test-AndroidStorage {
  param([Parameter(Mandatory)][string]$Serial)

  # Androidは残量が partition の1割を切ると新規インストールを拒む。
  # APK 1本ぶんの余裕も要るので、しきい値は多めに取る。
  $requiredMb = 1500

  & adb -s $Serial shell pm trim-caches 4096M 2>$null | Out-Null

  # df -m の並び: Filesystem / Size / Used / Avail / Use% / Mounted
  $df = (& adb -s $Serial shell df -m /data 2>$null | Select-Object -Last 1)
  if (-not $df) { return $true }  # 判定できないときは素通しする
  $cols = @($df.Trim() -split '\s+')
  if ($cols.Count -lt 4 -or $cols[3] -notmatch '^\d+') { return $true }
  $availMb = [int]($cols[3] -replace '\D', '')

  Write-Host "Android /data 空き: ${availMb}MB" -ForegroundColor DarkGray
  if ($availMb -ge $requiredMb) { return $true }

  Write-Host "空き容量が不足（${availMb}MB < ${requiredMb}MB）。" -ForegroundColor Red
  Write-Host 'debug APK は230MB超あり、テストはファイルごとに入れ直す。' -ForegroundColor Red
  Write-Host '不要なアプリを消すか、AVDをwipe-dataして出直すこと:' -ForegroundColor Red
  Write-Host "  adb -s $Serial shell pm list packages -3" -ForegroundColor DarkGray
  Write-Host "  adb -s $Serial uninstall <package>" -ForegroundColor DarkGray
  return $false
}

if ($SkipAndroid) {
  foreach ($s in 'build:android', 'e2e:android') { Add-Result $s 'SKIP' 0 '-SkipAndroid' }
}
else {
  Invoke-Stage 'build:android' { flutter build apk --debug } 'build_android'

  if (Test-Wanted 'e2e:android') {
    $serial = Get-AndroidDeviceId
    if (-not $serial) { $serial = Start-AndroidEmulator -Id $Emulator }

    if (-not $serial) {
      Add-Result 'e2e:android' 'SKIP' 0 'Android端末もエミュも起動できず'
    }
    elseif (-not (Test-AndroidStorage -Serial $serial)) {
      Add-Result 'e2e:android' 'FAIL' 0 "$serial の空き容量不足"
    }
    else {
      Write-Host ''
      Write-Host "=== e2e:android ($serial) ===" -ForegroundColor Cyan
      $logPath = Join-Path $logDir 'e2e_android.log'
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      Invoke-IntegrationTests -DeviceId $serial 2>&1 | Tee-Object -FilePath $logPath
      $code = $LASTEXITCODE
      $sw.Stop()
      if ($code -eq 0) { Add-Result 'e2e:android' 'PASS' $sw.Elapsed.TotalSeconds $serial }
      else { Add-Result 'e2e:android' 'FAIL' $sw.Elapsed.TotalSeconds "exit=$code / $logPath" }
    }
  }
  else {
    Add-Result 'e2e:android' 'SKIP' 0 '-Only で対象外'
  }
}

# --- まとめ -------------------------------------------------------------------

Write-Host ''
Write-Host '================ test matrix ================' -ForegroundColor Cyan
$script:results | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "ログ: $logDir"

$failed = @($script:results | Where-Object Status -eq 'FAIL')
if ($failed.Count -gt 0) {
  Write-Host "FAIL: $($failed.Count) 段" -ForegroundColor Red
  exit 1
}
Write-Host 'すべて PASS / SKIP' -ForegroundColor Green
exit 0
