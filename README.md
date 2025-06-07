# K-MAPS

## 概要
K-MAPSはGeoPackageベースの地理情報管理・編集アプリケーションです。地図上での点・線・面の描画・編集、GPS位置情報の取得、外部GNSS受信機との連携などの機能を提供します。

## 主要機能

### 1. フォアグラウンドサービス機能 **【NEW・外部GNSS対応】**
- **概要**: バックグラウンドでタスクを継続実行する機能（GPS + 外部GNSS対応）
- **実装**: `flutter_background_service` パッケージを使用
- **機能詳細**:
     - **外部GNSS優先システム**: 接続された外部GNSSを優先、未接続時は内蔵GPSを使用 **【NEW】**
   - **Bluetooth GNSS自動連携**: Bluetooth GNSS画面で設定されたデバイスを自動検出・接続 **【NEW】**
   - **NMEAデータリアルタイム解析**: GGA/RMC文の解析による高精度位置情報取得 **【NEW】**
   - **画面遷移時接続維持**: グローバルマネージャーによる接続の永続化管理 **【NEW】**
  - 1秒間隔でのGPS/GNSS情報付きログ出力（デバッグ・テスト・追跡用）
  - リアルタイム位置座標取得（緯度・経度・精度・受信数情報）
  - Android端末では通知バーでGPS/GNSS状態と座標を表示
  - UIからのサービス開始・停止制御
  - GPS権限・サービス状態の事前確認
  - エラーハンドリングとログ出力の最適化

### 2. 地図表示・ナビゲーション
- OpenStreetMapベースの地図表示
- レイヤ構造での地理情報管理（点・線・面）
- フリーハンド描画とタップによる図形作成
- フィーチャの選択・編集・削除
- 属性情報の表示・編集

### 3. GPS・GNSS機能  
- 内蔵GPS/GNSS受信機による現在位置取得
- SSP対応Bluetooth GNSS受信機との連携
- NMEA-0183フォーマットの位置データ解析
- リアルタイム位置情報表示
- 衛星情報・精度情報の詳細表示
- **GPS軌跡記録・保存機能**: 追跡開始から停止までの軌跡をLINESTRINGレイヤーとして任意のGeoPackageに保存 **【NEW】**

### 4. データ管理機能
- GeoPackage形式でのデータ保存・管理
- プロジェクト・フォルダ・レイヤの階層構造
- レイヤの可視性制御
- データのインポート・エクスポート

### 操作ツール
- **てのひらツール**: 地図のパン操作
- **ペンツール**: フリーハンド描画
- **選択ツール**: フィーチャの選択・編集
- **GPSツール**: GPS関連機能（パン操作と同じ挙動 + 専用GPS追跡ボタン表示 + 軌跡保存機能） **【NEW】**

## 技術構成

### フレームワーク・言語
- **Flutter**: クロスプラットフォーム対応（Android/iOS/Windows/macOS/Linux）
- **Dart**: プログラミング言語

### データベース・ストレージ
- **sqflite**: Flutter推奨のSQLiteデータベース（sqlite3から移行完了）
- **GeoPackage**: OGC標準の地理空間データフォーマット
- 非同期処理（async/await）による高パフォーマンス

### 主要パッケージ
```yaml
dependencies:
  flutter_map: ^7.0.2           # 地図表示
  latlong2: ^0.9.1              # 緯度経度計算
  sqflite: ^2.3.0               # データベース
  geolocator: ^12.0.0           # GPS位置情報
  flutter_bluetooth_serial: ^0.4.0  # Bluetooth接続
  nmea: ^2.0.0                  # NMEAデータ解析
  file_picker: ^10.1.9          # ファイル選択
  flutter_background_service: ^5.0.9  # フォアグラウンドサービス
  permission_handler: ^11.3.1  # Android権限管理
```

## 主要ファイル・クラス構成

### モデル層
- `lib/models/geopackage_file.dart`: GeoPackageファイル管理・DB操作
- `lib/models/layer_tree_node.dart`: レイヤツリー構造・ノード管理
- `lib/models/bluetooth_gnss_service.dart`: Bluetooth GNSS接続・NMEAデータ解析 **【NEW】**
- `lib/utils/global_config.dart`: アプリケーション全体の設定管理
- `lib/utils/global_gnss_manager.dart`: GNSS接続のグローバル管理・永続化 **【NEW】**

### 画面・UI層
- `lib/screens/map_page.dart`: 地図表示・編集のメイン画面
- `lib/screens/bluetooth_gnss_screen.dart`: Bluetooth GNSS管理画面
- `lib/widgets/layer_drawer.dart`: レイヤ管理ドロワーUI

### サービス層
- `lib/services/foreground_service.dart`: GPS/GNSS追跡フォアグラウンドサービス **【NEW】**

### ツール・ユーティリティ
- `lib/tools/pan_tool.dart`: 地図パン操作ツール
- `lib/tools/pen_tool.dart`: フリーハンド描画ツール  
- `lib/tools/select_tool.dart`: フィーチャ選択ツール
- `lib/tools/gps_tool.dart`: GPS関連機能ツール（プロキシパターンによるパンツール機能継承） **【NEW】**
- `lib/tools/gps_utils.dart`: GPS・GNSS情報取得ユーティリティ
- `lib/utils/feature_calc_utils.dart`: 地理計算ユーティリティ（距離・面積・重心計算）

### 設計方針
- **非同期処理**: 全てのDB操作・ファイルアクセスはFuture/async-awaitで実装
- **ツリー構造管理**: プロジェクト→フォルダ→GeoPackage→レイヤの階層管理
- **グローバル状態管理**: 選択状態・現在ツール・設定をGlobalConfigで一元管理
- **プロキシパターン**: GPSツールによるパンツール機能の継承・委譲（将来拡張対応） **【NEW】**
- **プラットフォーム対応**: Windows/Android両対応、デスクトップ向けsqflite初期化

## 使用方法

### 基本操作
1. **プロジェクト作成**: ホーム画面でプロジェクトフォルダを選択
2. **レイヤ作成**: ドロワーの「+」ボタンでGeoPackageファイル・レイヤを作成
3. **描画**: ツールバーでペンツールを選択し、地図上で描画
4. **編集**: 選択ツールでフィーチャを選択し、属性編集・位置調整

### GPS・GNSS接続 **【外部GNSS強化】**
1. **内蔵GPS**: アプリ起動時に自動で位置情報取得を開始
2. **外部GNSS**: 
   - マップ画面のBluetoothアイコンから接続画面にアクセス
   - ペアリング済みBluetoothデバイスの一覧表示・接続
   - 接続成功時に自動でフォアグラウンドサービスに設定保存 **【NEW】**
   - NMEA-0183データの自動解析（GGA文対応） **【NEW】**
3. **位置表示**: 地図上に青色アイコンで現在位置を表示
4. **フォアグラウンドサービス連携**: 
   - 外部GNSS接続時は優先してGNSSデータを使用 **【NEW】**
   - 通知に「GNSS」または「GPS」の表示で情報源を明確化 **【NEW】**

### 基本使用方法 **【外部GNSS対応】**
1. ホーム画面で「フォルダを選択」ボタンをクリック
2. プロジェクトフォルダを選択
3. 自動的にマップ画面に遷移
4. **外部GNSS接続**（オプション）:
   - マップ画面上部のBluetoothアイコンをタップ **【NEW】**
   - ペアリング済みGNSSデバイスを選択・接続 **【NEW】**
   - 接続成功すると自動でフォアグラウンドサービスに設定 **【NEW】**
5. **位置追跡サービス制御** **【UI改善】**:
   - ツールバーでGPSツールを選択 **【NEW】**
   - 右下に表示される足跡アイコンのフローティングボタンで追跡開始・停止 **【NEW】**
   - 外部GNSS接続時は「外部GNSS追跡」、未接続時は「内蔵GPS追跡」として動作 **【NEW】**
6. **リアルタイム確認**:
   - デバッグコンソールで1秒間隔のGPS/GNSS情報ログ確認
   - Android端末では通知バーでリアルタイム座標・情報源表示 **【NEW】**
   - GPS情報バーでリアルタイム座標・衛星数・精度確認（追跡ボタンは削除済み） **【NEW】**

## インストール・セットアップ

### 開発環境
```bash
# 依存関係インストール
flutter pub get

# デバッグビルド
flutter run

# リリースビルド（Android）
flutter build apk --release
```

### 権限設定（Android）
以下の権限がAndroidManifest.xmlで設定済みです：
- `ACCESS_FINE_LOCATION`: 高精度GPS
- `ACCESS_COARSE_LOCATION`: 概算位置情報  
- `BLUETOOTH_CONNECT`: Bluetooth接続
- `INTERNET`: 地図タイル取得

## 対応プラットフォーム
- ✅ Android（実機テスト済み）
- ✅ Windows（開発・テスト済み）
- 🔄 iOS（基本実装済み・要テスト）
- 🔄 macOS（基本実装済み・要テスト）
- 🔄 Linux（基本実装済み・要テスト）

## データベース移行（2025年対応）
sqlite3からsqfliteへの段階的移行を完了しました：

### 移行内容
- **非同期処理**: 全メソッドがFuture<T>を返すように変更
- **自動初期化**: データベース接続の遅延初期化とライフサイクル管理
- **エラーハンドリング**: try-catch構文による堅牢なエラー処理
- **スキーマ管理**: onCreate/onUpgradeコールバックによるマイグレーション対応

### 技術的改善点
```dart
// 旧方式（sqlite3・同期処理）
final layerNames = geoPackage.getLayerNames();

// 新方式（sqflite・非同期処理）  
final layerNames = await geoPackage.getLayerNames();
```

#### 5. UI要素の見切れ問題 **【修正済み】**
**問題内容**:
- ホーム画面で縦方向にコンテンツが見切れる
- GPS情報バーで横方向に情報が見切れる

**解決方法**:
1. **ホーム画面**: シンプルなフォルダ選択UIに刷新（`Center`配置で画面内に収まるように改善）
2. **GPS情報バー**: 横方向スクロール対応でGPS詳細情報を全て表示可能
3. 柔軟なレイアウト設計でさまざまな画面サイズに対応

#### 6. ホーム画面UI改善 **【完了】**
**改善内容**:
- 複雑なGPS設定・サービス制御UIを削除
- シンプルで分かりやすいフォルダ選択画面に刷新
- Material Designに準拠した美しいカードベースレイアウト
- 選択されたフォルダパスの確認表示機能

#### 7. GPS追跡マーカーのアニメーション化 **【NEW・完了】**
**改善内容**:
- 邪魔だった大きな赤い追跡マーカーを削除
- 現在位置の周りを光が軌跡を描きながら回転するエフェクトに変更
- 2つの光点が異なる速度と方向で回転（複雑で美しい動き）
- AnimationControllerとTweenを使用した滑らかな3秒間隔回転
- GPS追跡サービス開始時に自動でアニメーション開始、停止時に停止

## ライセンス
プロジェクトのライセンス情報は後日追加予定です。

## トラブルシューティング

### よくある問題

#### 1. サービスが開始しない
   - Android権限の確認
   - デバッグログの確認

#### 2. 通知が表示されない
   - 端末の通知設定確認
   - アプリの通知権限確認

#### 3. ログが出力されない
   - デバッグコンソールの確認
   - print文の出力先確認

#### 4. AndroidManifest.xml競合エラー **【重要】**
**エラー内容**:
```
Attribute service#id.flutter.flutter_background_service.BackgroundService@exported value=(false) from (unknown)
is also present at [:flutter_background_service_android] AndroidManifest.xml:15:13-36 value=(true).
```

**原因**: flutter_background_serviceプラグインが自動的にサービス定義を追加するため、手動で追加したサービス定義と競合

**解決方法**:
1. AndroidManifest.xmlから手動で追加したサービス定義を削除
2. プラグインが自動的に適切な設定を行う
3. 権限（FOREGROUND_SERVICE等）のみ手動で設定

```xml
<!-- ❌ 削除が必要（競合原因） -->
<service
    android:name="id.flutter.flutter_background_service.BackgroundService"
    android:exported="false"
    android:foregroundServiceType="dataSync" />

<!-- ✅ 権限のみ手動設定 -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
```

**参考**: [GitHub Issue #1558](https://github.com/Baseflow/flutter-geolocator/issues/1558)での類似問題

#### 5. フォアグラウンドサービス通知エラー **【クリティカル】**
**エラー内容**:
```
android.app.RemoteServiceException$CannotPostForegroundServiceNotificationException: Bad notification for startForeground
```

**原因**: 
- 通知チャンネルが適切に設定されていない
- メインIsolateでのプラグイン競合
- Android 8.0以降の通知チャンネル要件に未対応

**解決方法**:
1. **MainActivityで通知チャンネルを明示的に作成**:
```kotlin
// MainActivity.kt
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
    val channelId = "k_maps_foreground_channel"
    val channelName = "K-MAPS フォアグラウンドサービス"
    val importance = NotificationManager.IMPORTANCE_LOW
    
    val channel = NotificationChannel(channelId, channelName, importance)
    val notificationManager = getSystemService(NotificationManager::class.java)
    notificationManager?.createNotificationChannel(channel)
}
```

2. **サービス初期化の遅延実行**:
```dart
// main.dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
    await ForegroundServiceManager.initializeService();
});
```

3. **Android 13以降の通知権限追加**:
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

**参考**: [GitHub Issue #406](https://github.com/ekasetiawans/flutter_background_service/issues/406)でのクラッシュ報告

### デバッグ方法
```bash
# Flutterログ確認
flutter logs

# Androidログ確認
adb logcat | grep flutter
```

## 更新履歴

### v1.2.0 (最新) **【NEW】**
- GPS軌跡記録・保存機能を追加
- フォアグラウンドサービスによるバックグラウンド追跡対応
- 軌跡統計情報表示（距離・ポイント数・GNSS/GPS比率）
- **ジオメトリタイプの表記を単一系（POINT, LINESTRING, POLYGON）に統一**
- **型安全性向上のためGeometryTypeエナムを導入**
- MULTI系表記（MULTIPOINT, MULTILINESTRING, MULTIPOLYGON）を削除し、単一系で統一
- 文字列リテラルによるジオメトリタイプ指定を廃止し、enum使用で型安全性を向上
- **属性テーブルの自動再読み込み問題を修正**
- GPS追跡サービス状態更新の最適化（1秒→5秒間隔、変化時のみ更新）
- 属性テーブルのスクロール位置保持機能を追加
- データキャッシュ機能により不必要な再読み込みを防止

### v1.1.0
- フォアグラウンドサービス機能追加
- デバッグログ最適化
- UI改善（サービス制御画面）

### v1.0.0
- 基本的な地図表示機能
- GPS位置情報取得
- Bluetooth GNSS対応

### ログ形式
```
[ForegroundService] フォアグラウンド実行中 - HH:MM:SS | GPS: 35.123456, 139.654321 (精度: 5.0m)
```

**GPS情報の詳細**: **【NEW】**
- **座標形式**: 緯度, 経度（小数点以下6桁）
- **精度情報**: メートル単位での位置精度
- **エラー処理**: GPS取得失敗時は前回値またはエラーメッセージを表示
- **権限チェック**: GPS無効・権限なしの場合は適切なメッセージを表示

---

**開発者向けメモ**: 本プロジェクトは継続的な機能拡張を想定して設計されており、各機能は独立性と再利用性を重視した実装となっています。

## 📍 GPS軌跡記録システム（バックグラウンド対応）

### 📊 主要コンポーネント

#### 🔧 修正内容：Isolate間通信の実装（2025-06-06）

**問題：** フォアグラウンドサービスが別Isolateで実行されるため、GPS位置情報を取得してもメインアプリの`GpsTrackManager`に記録されない（0ポイント問題）

**解決方法：** `flutter_background_service`のIsolate間通信機能を使用
- フォアグラウンドサービス → メインアプリへのポイントデータ送信
- `service.invoke('addTrackPoint', pointData)` でデータ送信
- メインアプリ側で `FlutterBackgroundService().on('addTrackPoint')` でデータ受信

#### 🐛 追加修正：GPS軌跡保存デバッグログ強化（2025-06-06）

**問題：** 軌跡ポイント数は正しく表示されるが、GeoPackageファイルへの保存でレイヤが追加されない

**対応：** 詳細なデバッグログを追加
- 地図画面の`_saveTrackToGeoPackage`メソッドにステップ毎のログ追加
- `GeoPackageFile.createGpsTrackLayer`メソッドの詳細ログ
- `GeoPackageFile.addLine`メソッドの詳細ログ
- `createWkbLineString`WKB作成処理の詳細ログ
- エラー発生時のスタックトレース出力

**デバッグログ例:**
```
[DEBUG] GPS軌跡保存開始: 軌跡名 -> GeoPackage名
[GeoPackage] GPS軌跡レイヤー作成開始: gps_tracks
[GeoPackage] LineString追加開始: gps_tracks
[WKB] LineString作成開始: 1ライン
```

#### 🔧 追加修正：GPS軌跡保存方式をpen_toolと同じ形式に変更（2025-06-06）

**問題：** 保存したフィーチャの座標がおかしくなっている

**原因：** GPS軌跡はMULTILINESTRING形式で保存していたが、pen_toolはLINESTRING形式で保存していた

**解決：** GPS軌跡保存方式をpen_toolと同じLINESTRING形式に変更
- `gpkgFile.createGpsTrackLayer()` → `gpkgFile.addLayer(layerName, GeometryType.linestring)`
- `gpkgFile.addMultiLineString()` → `gpkgFile.addLine()`
- MULTILINESTRING形式 → LINESTRING形式

**変更前（MULTILINESTRING）:**
```dart
await gpkgFile.createGpsTrackLayer(layerName);
await gpkgFile.addLine(layerName, coordinates, ...);
```

**変更後（LINESTRING - pen_toolと同じ）:**
```dart
await gpkgFile.addLayer(layerName, GeometryType.linestring);
await gpkgFile.addLine(layerName, coordinates, ...);
```

## バージョン履歴

### v1.2.0 (2024-12-19)
- **属性テーブル自動再読み込み問題の修正**
  - GPS追跡サービス状態更新の最適化（10秒間隔に変更）
  - 視覚的変化がある場合のみsetState()を実行
  - 座標の微細な変化（10m未満）は更新対象外
  - LayerDrawerの不要な再構築を防止
- **Windows環境での追跡ボタン非表示対応**
  - GPS追跡ボタンをWindows環境では表示しないように修正
  - `Platform.isWindows`条件チェックを追加
  - モバイル/GPSデバイス環境でのみ追跡機能を有効化
