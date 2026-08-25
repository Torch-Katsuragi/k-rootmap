---
title: テスト構成（Windows / Android 両対応）
tags: [technical, testing, windows, android]
---

# テスト構成

Windows版の復活作業で一番怖いのは「Windowsを直したらAndroidが壊れた」である。
片方だけ緑になっても意味がないので、テストは常に両プラットフォームで同じものを回す。

## 一発で回す

```powershell
pwsh tool/test_matrix.ps1
```

段ごとの結果が表で出る。ログは `.temp/test_matrix/` に残る。

| 段 | 内容 | 端末 |
|---|---|---|
| `analyze` | `flutter analyze` | 不要 |
| `unit` | `test/` 配下（ホストVM） | 不要 |
| `build:windows` | Windowsのコンパイルゲート | 不要 |
| `e2e:windows` | `integration_test/` を Windows デスクトップで実行 | Windows本体 |
| `build:android` | debug APK のコンパイルゲート | 不要 |
| `e2e:android` | `integration_test/` を実機/エミュで実行 | Android |

よく使うオプション:

```powershell
pwsh tool/test_matrix.ps1 -Only analyze,unit   # 端末不要の段だけ
pwsh tool/test_matrix.ps1 -SkipAndroid         # Windowsだけ
pwsh tool/test_matrix.ps1 -Emulator Medium_Phone_API_36
```

`e2e:android` は **実機を優先**する。実機が繋がっていなければエミュレータを自動起動する。

> [!IMPORTANT] Androidの検証は実機で行う（2026-08-21 方針）
> エミュはCPU/GPUが実機と別物で、性能の数字も描画の挙動もあてにならない。
> `tool/test_matrix.ps1` は `adb devices` の結果から実機を先に選ぶ。
> エミュはあくまで実機が無いときのフォールバック。
> ⚠ベンチ（`integration_test/benchmark/`）の数字を比較するときは、
> **どちらで取ったかを必ず併記する**こと。

## 地図バックエンド契約テスト

[[map_contract_test|integration_test/map_contract_test.dart]] が本命。
Windows版の地図バックエンドを差し替えたとき、Androidと同じ振る舞いを保っているかを
機械的に検証する。2026-04にWindows版を凍結した理由が
「maplibre_webview と maplibre本体の挙動差が大きい」だったので、その差をここで数値に固定した。

検証している契約:

- `onStyleLoaded` が発火する
- `MapOptions` の初期カメラ（center / zoom / bearing / pitch）が反映される
- `move()` / `moveAndRotate()` が即時にカメラへ反映される
- カメラ中心のスクリーン座標がウィジェット中央になる（DPRの二重適用検出）
- スクリーン座標 ⇄ 地理座標の往復が2px以内で一致する
- `KMapCamera` のヘルパが `RMapController` と同じ値を返す
- `animateTo()` の Future が完了し、目標カメラに着地する
- `fitCoordinates()` が全座標を画面内に収める
- GeoJSONソース／レイヤの追加・更新・削除が `getLayerIds()` に反映される

> [!IMPORTANT]
> **このファイルが Windows と Android の両方で緑になることが、Windows版地図バックエンド採用の受け入れ条件。**
> 現状 Windows では [[harness|integration_test/support/harness.dart]] の `hasMapBackend` が false なので
> 理由つきスキップになる。バックエンドを入れたらこのフラグを立てるだけでテストが走り出す。

## プラットフォーム前提の宣言

`integration_test/support/harness.dart` に、プラットフォームごとの前提を集約している。
暗黙にテストを落とすのではなく、ここで明示的にスキップ理由を宣言する。

| フラグ | 意味 | 現状 |
|---|---|---|
| `hasMapBackend` | maplibre のプラットフォーム実装があるか | android / ios / windows / **web** |
| `hasFirebaseConfig` | `firebase_options.dart` に設定があるか | android / ios のみ |

Windows対応で前提が変わったら、このファイルの1行を直せば対象テストが走り出す。

> [!IMPORTANT] web では `Platform` を**先に**踏まないこと
> `dart:io` は web でも**コンパイルは通る**が、`Platform.isAndroid` などを
> 呼んだ瞬間に `UnsupportedError` を投げる。harness も `kIsWeb` を先に見る形にしてある。
> アプリ側の同じ規約は `lib/core/platform_capabilities.dart` に集約している。

`pumpUntil()` も同ファイル。地図はプラットフォームビューで常時アニメーションが走るため
`pumpAndSettle()` は永久に settle しない。地図まわりでは必ず `pumpUntil()` を使う。

## web版のテスト

`flutter test <file> -d chrome` は
**`Web devices are not supported for integration tests yet.` で断られる。**
web だけは `flutter drive` 経由になり、chromedriver（Chrome と同じメジャーバージョン）が要る。

```powershell
chromedriver --port=4444
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/map_contract_test.dart -d web-server --browser-name=chrome
```

> [!WARNING] 未検証（2026-08-24 時点）
> このマシンに chromedriver が入っていないため、**まだ一度も回せていない**。
> `integration_test/support/harness.dart` の `hasMapBackend` には web を足してあるので、
> chromedriver さえ入れれば9件が対象になる。

`tool/test_matrix.ps1` にはまだ web の段を入れていない（段2以降で機能が乗ってから）。
地図バックエンドを触ったときは手で回す。

### 画面を目で見るとき

```powershell
flutter build web --release
python -m http.server 8110 --directory build\web --bind 127.0.0.1
```

> [!WARNING] `flutter run -d chrome` のデバッグサーバは別ブラウザから開くと不安定
> DWDS はクライアントを1つしか面倒を見ないので、`flutter run` が起動した Chrome とは
> 別のタブから同じポートを開くとモジュールの読み込みが止まることがある。
> 画面を機械的に確認したいときは `flutter build web --release` して
> `build/web` を静的配信するほうが速くて確実。

## 既知の落とし穴

- **integration_test はファイル単位で起動する。**
  `flutter test integration_test -d <device>` とディレクトリ指定すると2本目以降が
  `The log reader stopped unexpectedly, or never started.` で起動に失敗する。
  `tool/test_matrix.ps1` はファイルごとに `flutter test <file> -d <device>` を呼び直している。
- **`testWidgets` の `skip` は `bool` しか取れない。**
  理由つきスキップ（文字列）を使いたいときは `group` 側に置く。`test` は `Object?` を取るので問題ない。
- **ホストVMのテストで sqflite を使うなら FFI 初期化が要る。**
  `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;` を `setUpAll` で呼ぶ
  （`main.dart` のデスクトップ分岐と同じ）。
- **`addLayer()` は `fid` と `geom` しか作らない**（QGIS互換の最小スキーマ）。
  属性を扱うテストは `addAttributeColumns()` で明示的にカラムを足す。
- **`e2e:android` が無反応で固まったら、まず adb サーバを立て直す。**
  端末側ではなくPC側が詰まっていることがある（APKのインストールまでログが出て、
  そこから先が永久に進まない）。2026-08-24 に20分ハングした実例あり。
  ```powershell
  adb kill-server; adb start-server; adb devices
  ```
  残った `dart.exe` / `dartvm.exe` が掴んでいることもあるので、先に落としておく。
- ⚠ **Git Bash から `adb shell df -h /data` を打つと嘘をつく。**
  `/data` が `C:/Program Files/Git/data` に変換されて `No such file or directory` になり、
  端末のストレージが壊れているように見える。`MSYS_NO_PATHCONV=1` を付けるか
  PowerShell から叩くこと。
- **エミュレータの空き容量に注意**（実機を使えば回避できる）。
  debug APK は230MB超あり、テストはファイルごとに入れ直すので使い回したエミュはすぐ埋まる。
  `INSTALL_FAILED_INSUFFICIENT_STORAGE` だけでなく
  `adb: device 'emulator-XXXX' not found` や `VmServiceDisappearedException` という
  紛らわしい形でも出る。`tool/test_matrix.ps1` は実行前に空きを見て、
  1500MB を切っていたらその場で止める。
  詰まったら `adb shell pm list packages -3` で残骸を探して消す。

## Windows版の画面を撮る

```powershell
pwsh tool/capture_window.ps1                      # .temp/window_capture.png
pwsh tool/capture_window.ps1 -Out .temp/map.png
```

対象ウィンドウだけをPNGに落とす（デスクトップ全体は撮らない）。
既定は `PrintWindow(PW_RENDERFULLCONTENT)` で、**前面に出ていなくても撮れる**。
中身がほぼ単色なら画面切り出し（`-Mode Screen`）に自動で落ちる。

> [!IMPORTANT] Flutter側のスクショ手段は地図が写らない
> | 手段 | 結果 |
> |---|---|
> | `flutter screenshot --type=device` | `Screenshot not supported for Windows.`（Android/iOS専用） |
> | `flutter screenshot --type=skia` | 撮れるが `.skp`。Flutterのレイヤツリーだけ |
> | `RepaintBoundary.toImage()` / `takeScreenshot()` | 同上 |
>
> Windows版の地図は **WebView2 のネイティブサーフェス**で、Flutterのラスタライズ外で
> 合成されている。Flutter由来の手段では**一番見たい地図が空で写る**。
> 地図を確認したいならOSレベルのウィンドウキャプチャを使うこと。

## 起動時にプロジェクトを自動で開く

```bash
flutter run -d windows --dart-define=PROJECT_DIR=C:/Users/you/project
```

フォルダピッカーを手で操作しないと地図画面に入れないと、起動〜描画の検証が回せないので用意した
（`lib/core/launch_options.dart`）。指定が無い／パスが存在しない場合は通常どおり選択画面が出る。

> [!WARNING] パスはスラッシュ区切りで渡す
> バックスラッシュはシェルと `--dart-define` の間で食われて
> `C:UsersyouProject` のような別物になる。存在しないパスは黙って無視されるので気づきにくい。

## CI

`.github/workflows/ci.yml` で以下を回す。端末が要る段はCIでは扱わない。

- `analyze + unit`（ubuntu）
- `build (windows)` — Windows版が「コンパイルすら通らない」状態に戻るのを防ぐゲート
- `build (android)`

## 関連

- [[tech-stack|技術スタック]]
- [[../../TODO|TODO]]
