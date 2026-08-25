# TODO List

## ~~Windows版の復活~~ → 撤去（2026-08-25）

> [!IMPORTANT] デスクトップ版（Windows / macOS / Linux）は撤去した
> 2026-08-21〜 に Windows版を復活させたが、その後 web版が
> **起動 → フォルダを開く → GeoPackage読み書き**まで到達し、役割を引き継いだ。
> `windows/` `linux/` `macos/` と `maplibre_webview` を削除。
> 経緯と代償（オフラインで配れる実行ファイルが無くなる）は
> [[docs/features/concept#プラットフォームの役割分担]]。
>
> 復活させるなら `flutter create --platforms=windows .` からやり直す。
> 当時の作業内容は git 履歴（`a9da582` まで）に残っている。

- [x] Windows版のビルド復旧・地図バックエンド選定・契約テスト整備（→ 撤去により役目終了）
- [x] 撤去にあわせて `flutter_inappwebview` が Android APK から落ちた（`maplibre_webview` の推移的依存だった）
- [ ] 死んだ依存 `flutter_map` を pubspec から外す
- [ ] 上流に issue/PR（josxha/flutter-maplibre）は**出さない**（AIが人間のコミュニティに投稿しない方針）。
      踏んだバグは手元の回避策とコメントに残してある

## プロジェクト形式の設計（2026-08-21・設計のみ）

> 設計は [[docs/technical/project-format-design|プロジェクト形式の設計]] に集約。
> **web版が全ての前提**なので、下の web 版が終わるまで着手しない。

- [ ] **View の導入** — Layer の下に「フィルタ＋スタイルの集合体」を置く。QGISのレイヤと1:1対応
- [ ] **`.qgs` ライター** — dir/gpkg/layer をレイヤグループ、View をレイヤとして出力
- [ ] `.qgs` インポータ（root外参照を破棄・グループはdir構造に置換・捨てたものを必ず報告）
- [ ] web側のQR発行（受け側の `cloneFromDrive` と QRスキャンは実装済み）
- [ ] ~~`layer_styles`~~ → **優先度を下げた**。`.qgs` にレンダラを書けば冗長。gpkg単体を渡す場合の保険のみ

## web版（調査済み・2026-08-21）

> `flutter build web` は**エラー0件で通る**。落ちるのは実行時の `UnsupportedError`。
> Dart は `dart:io` を「コンパイルは通るが呼ぶと落ちるスタブ」として web に出しているため、
> 「webで到達する呼び出しを1つずつ塞ぐ」作業になる。詳細は [[docs/technical/testing|テスト構成]] ではなく
> Vault の案件md（Windows版復活_2026-08-21）を参照。
>
> **段1は 2026-08-24 に完了。** ブラウザで起動して背景地図（OSM）まで出る。
> プラットフォーム判定は `lib/core/platform_capabilities.dart` に集約したので、
> 以降 `Platform.is` を直に書かないこと。

- [x] **クリティカルパス: WASM SQLite の性能PoC** → **通過**。全件読み538ms / UPDATE 1件1ms /
      書き戻し14ms / deserialize 5ms。8.5MBなら全部メモリに載せる選択肢も取れる
- [x] **段1: 起動して地図が出るまで**（2026-08-24 完了）
  - [x] `Platform.isXxx` 30箇所を `lib/core/platform_capabilities.dart` の capability 経由に
  - [x] webではTileServerを起動しない（`HttpServer` が無く、かつ不要）
  - [x] `web/index.html` に maplibre-gl-js を追加（maplibre_web は script を注入しない）
  - [x] プロジェクトを開かずに地図だけ見る入口（web限定・段2までの暫定）
  - [x] `integration_test/support/harness.dart` の `hasMapBackend` に web を追加
- [ ] **web版の `map_contract_test` をまだ回せていない**（chromedriver 未インストール）
  - `flutter test -d chrome` は非対応。`flutter drive` + chromedriver が要る
  - ドライバ（`test_driver/integration_test.dart`）と手順は用意済み → [[docs/technical/testing]]
- [/] **`File(` / `Directory(` をファイルシステム抽象経由に**（本丸）
  - [x] **段2前半: 抽象を作ってツリー経路を載せ替え**（2026-08-25 完了・挙動不変）
        `lib/core/fs/` に `KFileSystem`（**同期メソッドは意図的に無し**）と io / web 実装。
        `path_resolver` / `kmeta` / `kmeta_service` / `folder_node` / `geopackage_node` /
        `image_node` / `global_folder_node` / `geopackage_connection` を移行。173 → 156箇所
  - [x] **段2後半: web実装（File System Access API）＋フォルダ選択**（2026-08-25 完了）
        Chrome/Edge でフォルダを選ぶとツリー（サブフォルダ・.gpkg・画像）が出るところまで到達。
        ⚠ Firefox/Safari は `showDirectoryPicker` が無いので「地図プレビュー」のまま
  - [ ] 残り156箇所（Drive同期・shapefile・GeoTIFF・TileServer 等）。
        web で通らない経路なので、必要になった段で個別に移す
- [x] **段3: GeoPackage を sqlite3 WASM へ**（2026-08-25 完了）
  - `sqflite_common_ffi_web` を採用。既存の `rawQuery` / `transaction` はそのまま動く
  - チェックアウト（元ファイル→WASM）／チェックイン（WASM→元ファイル）を
    `GeoPackageConnection` に実装。書き戻しは `total_changes()` の監視で自動
  - ⚠ OPFSは使っていない（sqflite_common_ffi_web が IndexedDB を使う）。
    ユーザーのフォルダとの受け渡しは File System Access API 側で行う
- [ ] PWA + Service Worker + タイルキャッシュ（オフライン対応）
- [ ] 公開ビューア（PMTiles/GeoJSONを静的ホスティング、URLで共有）
      ⚠ **自分のデータを自分のホストから配る初めての機能**。着手時に転送量を見積もる

### 公開・運用（2026-08-25 方針決定 → [[docs/features/concept#配布と運用コスト]]）

- [ ] Firebase Hosting へデプロイして**普通に公開**（ルーム機能が形になってから）
- [ ] 予算アラートを設定（同時接続数とダウンロード量）
- [ ] 寄付導線を置く（露骨にしない）
- [ ] セルフホスト手順を書く（既定にはしない。大口向けの選択肢）
- [ ] web版でルーム機能を使えるように（`flutterfire configure` に web を追加）

### 段1 の積み残し

- [ ] **webで背景地図を切り替えても即時反映されない**（再読み込みが要る）
  - 原因は上流。maplibre_web 0.3.5 の `StyleController.addSource()` が `RasterSource` の
    `tiles` と `url` を**両方**JSに書くため、片方が必ず null になり
    maplibre-gl のバリデータが `url: string expected, null found` で弾く。
    例外もリクエストも出ないので**無言で背景地図が消える**
  - 段1では初期スタイルJSONに焼き込んで回避（`lib/services/basemap_style_json.dart`）
  - 直すなら: 上流に報告 / `MapController.setStyle()` でスタイルごと差し替え
    （`MapSourceManager` に再初期化の口が無いので、そのままだとフィーチャが消える）
- [ ] **webで地図が右のレイヤドロワーに透けて見える**
  - Flutter web のプラットフォームビュー合成の問題。Android では出ない
- [ ] **web: 同じフォルダを3回列挙している**
  - `FolderNode` / `GeoPackageNode` / `ImageNode` の `loadNodes` がそれぞれ
    `fs.list()` を呼ぶため。native では syscall 3回で済むが、web はハンドル走査3回。
    フォルダあたり1回にまとめれば速くなる
- [ ] **web: 選んだフォルダがリロードで失われる**
  - ハンドルは IndexedDB に入れれば永続化できる（再許可のプロンプトは要る）

> [!NOTE] 方針
> - web版はWindows版を**置き換えた**（2026-08-25 に撤去済み）
> - サーバ権威型のWebGISは**自分ではやらない**。OSS なので利用者側で構築してもらう

---

## 🔥 直近のアクション

- [/] アプリ名を「RootMap GIS」に改名
  - [ ] J-PlatPat（日本特許庁）で「rootmap」の商標検索（Class 9/42）— メンテ明け後に実施
  - [ ] USPTO TESSで「rootmap」の商標検索
  - [x] 改名作業を実施（UI、Android/Windows/Web、changelog、Drive連携フォルダ名）
- [x] 内部テスト版でGoogle Sign-Inログイン動作確認
- [x] 連絡先メールアドレスを `k-root@googlegroups.com` に統一
  - [x] GCP ブランディング: サポートメール・デベロッパー連絡先 → 設定済み
  - [x] Play Console: アカウントの詳細・デベロッパープロフィール → 設定完了（2026/04/12）

---

## 未完了タスク

### Google Play リリース

#### 内部テスト（残り）

- [ ] ストア掲載情報（アプリ名、説明文、スクリーンショット等）
- [ ] 内部テスターリスト設定
- [ ] 内部テストとしてリリース

#### クローズドテスト

> 内部テスト完了後、より広い範囲のテスターに配布するためのステップ。

**Play Console「アプリのセットアップ」**

- [ ] アプリのアクセス権（Google Drive連携にはGoogleログインが必要である旨を記載）
- [ ] 広告の有無申告（「いいえ」）
- [ ] コンテンツのレーティング（IAQCレーティング質問票）
- [ ] ターゲットユーザー設定（18歳以上）
- [ ] ニュースアプリ申告（「いいえ」）
- [ ] データの安全性（開発者サーバーへの送信なし、端末内利用の説明）
- [ ] 行政機関のアプリ申告（「いいえ」）
- [ ] 財務機能申告（「提供していない」）

**デモ動画の作成**

> Play Console権限説明 + OAuth検証申請で兼用可能。1本にまとめてYouTubeタイムスタンプで各セクションに飛ばす。

- [ ] 撮影内容:
  - [ ] Google Sign-In → Drive同期の操作フロー（OAuth検証用）
  - [ ] 位置情報（バックグラウンド）: GPS軌跡記録がバックグラウンドで継続する様子
  - [ ] カメラ: 写真マーカー撮影、QRコードスキャン
  - [ ] Bluetooth: TruPulse測量機器との接続・データ取得
- [ ] YouTubeに限定公開でアップロード
- [ ] Play Console各権限セクション + GCPデータアクセスページにリンク登録

**ストア掲載情報**

- [ ] アプリ名・短い説明・詳しい説明
- [ ] スクリーンショット（スマートフォン用: 最低2枚）
- [ ] アプリアイコン（512x512 PNG）
- [ ] フィーチャーグラフィック（1024x500 PNG）
- [ ] カテゴリ設定（ツール or 地図＆ナビ）
- [ ] 連絡先情報（`k-root@googlegroups.com`）

**クローズドテストトラック**

- [ ] トラック作成・テスターリスト登録
- [ ] AABアップロード・リリースノート入力
- [ ] ロールアウト・参加リンク共有

---

### OAuth検証申請（一般公開向け）

> 内部テスト（100人以下）には不要。一般公開時に必要。

- [x] GCP ブランディング設定（HP・プライバシーポリシー・承認ドメイン）
- [x] GCP データアクセス（`drive` スコープ、用途チェック3種全選択）
- [ ] デモ動画のYouTubeリンクをGCPデータアクセスページに登録
- [ ] CASA対応（`drive`は制限付きスコープ。Googleから要求された場合のみ）
- [ ] 検証センターから申請

---

### 機能開発

#### Google Drive連携

- [ ] レイヤ単位での競合解決（GeoPackage内のレイヤレベルマージ、ops.logによる競合検出）

#### MapLibre

- [ ] 3D terrain有効化（RasterDemSource + setTerrain + pitch/tiltコントロール）
- [ ] 国土地理院DEMタイル → Terrain-RGB変換の実装・検証
- [ ] Flutter SDKアップグレード（3.10+）→ maplibre_webview導入（Windows対応）
  - **Windows対応一時中断**（2026/04/07）: maplibre_webviewのWebView2実装に起因する問題のため、当面Android特化。
- [ ] MapLibre GL JS/CSS/pmtiles.jsのローカルバンドル化（CDN依存排除、オフライン起動対応）
  - 注: バンドル版pmtiles.jsがNode.js用ビルドでブラウザ非互換のため保留

#### OverlayImageNode

- [x] OverlayTransformTool: ハンドルベースの移動・拡縮・回転UI
- [x] オーバーレイ設定ダイアログ: 不透明度・位置パラメータの調整UI
- [x] オーバーレイ変換ダイアログ: 紙地図スキャン画像の透明化処理（4モード）
- [x] オーバーレイ変形パフォーマンス改善（100msデバウンス）

#### その他機能

- [x] チェンジログ表示機能（CHANGELOG.md + アプリ内Markdown表示 + 未読通知バッジ）
- [x] UIサイズ7段階調整機能（0.75x〜1.30x、設定 → 一般、MediaQuery.textScaler + Riverpod）
- [x] フィードバックフォームにバージョン情報・端末モデルを事前入力（Google Forms URLパラメータ + PackageInfo + DeviceInfo）
- [ ] ポイント詳細情報からGoogle Mapリンクをコピーする機能
- [ ] 既存MapTool (PenTool/SelectTool/GpsTool) のChangeNotifier化統一
- [x] 水準器（Spirit Level）機能（v0.6.0 — 加速度計/コンパス/GPS統合、直角三角形計算付き）

### コード品質

`flutter analyze` 残存警告: **0件** ✅

- [x] `overridden_fields`: `FeatureNode` のフィールドオーバーライド警告 → ignoreコメント位置修正
- [x] `annotate_overrides`: `@override` アノテーション不足 → 2箇所追加（map_page_state_base.dart）
- [x] `unintended_html_in_doc_comment`: docコメント内のHTML解釈問題 → バッククォートエスケープ（tile_server.dart）
- [x] `avoid_print`: テストコード内の `print()` → `// ignore: avoid_print` 追加（15箇所）

---

## 完了済み

<details>
<summary>内部テスト・Google Play（2026/04）</summary>

- [x] リリース準備
  - [x] keystore統一、バージョン番号設定（0.5.1+6）、署名付きAABビルド
  - [x] ACCESS_MOCK_LOCATION をdebugマニフェストに移動
  - [x] keystoreをandroid/配下にコピー、key.propertiesのパス修正
- [x] Play Consoleアップロード・公開
  - [x] アップロード鍵リセット申請、内部テストトラックにAABアップロード（v0.5.1+6）
  - [x] プライバシーポリシー作成・GitHub公開・Play Console登録
  - [x] リリースノート作成（`docs/release_notes_v0.5.1.md`）
- [x] Google Sign-In修正（2026/04/10）
  - [x] Play App Signing の SHA-1 取得（deployment_cert.der）
  - [x] Google Cloud Console に Play App Signing 用 Android OAuthクライアントID 作成
  - [x] SHA-1 一覧をGoogle Drive保存（`開発用キー/SHA-1フィンガープリント.txt`）
  - [x] 不要な `email` スコープを削除
- [x] GPSゾンビプロセス対策（2026/04/11）
  - [x] AndroidManifest `stopWithTask="true"` 設定（OS レベルでのサービス自動停止）
  - [x] ハートビートベース自殺機構（foreground_service.dart: 5秒間隔ping/pong、30秒無応答で自動停止）
  - [x] メインisolate側の応答ハンドラ（internal_gps_location_store.dart）
- [x] アプリ名を「RootMap GIS」に改名（2026/04/12）
  - [x] UI、Android/Windows/Web、changelog、Drive連携フォルダ名を一括更新

</details>

<details>
<summary>Google Drive連携MVP（2026/01）</summary>

- [x] 認証基盤（google_sign_in, googleapis）、GoogleDriveService/DriveAuthState
- [x] フォルダ追加: 通常/Drive連携の選択、URL入力（ペースト＋QRスキャン）
- [x] クローン: 共有フォルダからの初回ダウンロード
- [x] 永続化: .kmeta.jsonにDrive情報保存、再読み込み時にDriveFolderNodeとして復元
- [x] 手動同期（Push/Pull/状態確認/連携解除）、自動チェック
- [x] 視覚的区別（青いクラウドアイコン、同期状態オーバーレイ）
- 注: モバイル専用機能（PCでは無効化）

</details>

<details>
<summary>MapLibre移行（2026/03）</summary>

- [x] FlutterMap → MapLibreMap ウィジェット置換（KMapController/KMapCameraラッパー）
- [x] レイヤ移植（Polygon/Polyline/Marker → maplibre StyleLayer）
- [x] タイルキャッシュ基盤の移行（TileServer、localhost経由配信）
- [x] フィーチャ描画パフォーマンス修正（MapSourceManager、GeoJsonSource+StyleLayer）
- [x] ポイントクラスタリング実装（supercluster）
- [x] ImageNode描画をSymbolStyleLayerに移行（GPU描画化）
- [x] Windows版パフォーマンス最適化（頂点マーカーGPU化、batchSetPaintProperties）
- [x] Windows版マップ表示不具合修正（WebSocketレースコンディション）

</details>

<details>
<summary>外部計測機器・測量機能（2026/03）</summary>

- [x] TruPulseService: BT SPP接続、プロトコルパーサー
- [x] ExternalDeviceService / DeviceTool 抽象レイヤ（プラグインパターン）
- [x] MapToolbar / map_page へのDeviceTool汎用統合
- [x] Point → Line/Polygon 変換（閉合補正: コンパス法則/トランシット法則）
- [x] 磁気偏角補正、器械高・目標高補正
- [x] 測量精度リアルタイム表示（閉合比警告）

</details>

<details>
<summary>アーキテクチャ改善・Riverpod移行（2025/12〜2026/03）</summary>

- [x] 型安全性改善（IMapState、MapTool型安全化）
- [x] 重複コード削減、定数集約、ファイル構造整備
- [x] map_page.dart mixin統合（6 mixin + 3 widget）
- [x] 内蔵GPSリファクタリング（InternalGpsLocationStore、ForegroundService）
- [x] GPS軌跡の常時記録と切り取りUI（GpsHistoryRecorder、TrackExtractionDialog）
- [x] Riverpod導入 → 正規化 → 完全正規化（GlobalConfig完全削除、38ファイル190箇所解消）
- [x] LayerDrawerリファクタリング（ConsumerWidget化、LayerDrawerService抽出）
- [x] 非同期競合状態防止（Completer使用、6箇所）
- [x] 巨大ファイル分割（feature_converter, layer_drawer_tiles, sync_engine, metadata_parser）

</details>

<details>
<summary>コード品質・パフォーマンス改善</summary>

- [x] BuildContextの非同期使用問題の修正（10ファイル）
- [x] 非推奨APIの更新（withOpacity→withValues、onPopInvoked→onPopInvokedWithResult等）
- [x] print()をAppLoggerに統一
- [x] GeoPackageロード高速化（N+1解消、並列化、Isolate化）
- [x] 地図操作パフォーマンス改善（レンダリングキャッシュ、selectedFeaturesのSet化）
- [x] 宣言的設定フレームワーク（SettingDef + SettingsStore）

</details>

<details>
<summary>その他完了済み機能</summary>

- [x] フォルダメタデータシステム（.kmeta.json）
- [x] グローバルフォルダ機能（PC版カスタムパス対応含む）
- [x] LayerTreeNode大規模リファクタリング（NodeType enum、PathResolver等）
- [x] 属性テーブルQGISフィルタ・複製機能
- [x] OverlayImageNode変換後の即時マップ反映
- [x] ドキュメント構造整理（docs/features + docs/technical分割）
- [x] 背景地図改善（一括DL、並列処理、オフラインフォールバック、航空写真対応）
- [x] 設定画面UI統一

</details>
