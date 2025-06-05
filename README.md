# K-MAPS

## 概要
K-MAPSはGeoPackageベースの地理情報管理・編集アプリケーションです。地図上での点・線・面の描画・編集、GPS位置情報の取得、外部GNSS受信機との連携などの機能を提供します。

## 主要機能

### 1. フォアグラウンドサービス機能 **【NEW】**
- **概要**: バックグラウンドでタスクを継続実行する機能
- **実装**: `flutter_background_service` パッケージを使用
- **機能詳細**:
  - 1秒間隔でのログ出力（デバッグ・テスト用）
  - Android端末では通知バーでサービス状態を表示
  - UIからのサービス開始・停止制御
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

### 4. データ管理機能
- GeoPackage形式でのデータ保存・管理
- プロジェクト・フォルダ・レイヤの階層構造
- レイヤの可視性制御
- データのインポート・エクスポート

### 操作ツール
- **てのひらツール**: 地図のパン操作
- **ペンツール**: フリーハンド描画
- **選択ツール**: フィーチャの選択・編集

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
- `lib/utils/global_config.dart`: アプリケーション全体の設定管理

### 画面・UI層
- `lib/screens/map_page.dart`: 地図表示・編集のメイン画面
- `lib/screens/bluetooth_gnss_screen.dart`: Bluetooth GNSS管理画面
- `lib/widgets/layer_drawer.dart`: レイヤ管理ドロワーUI

### ツール・ユーティリティ
- `lib/tools/pan_tool.dart`: 地図パン操作ツール
- `lib/tools/pen_tool.dart`: フリーハンド描画ツール  
- `lib/tools/select_tool.dart`: フィーチャ選択ツール
- `lib/tools/gps_utils.dart`: GPS・GNSS情報取得ユーティリティ
- `lib/utils/feature_calc_utils.dart`: 地理計算ユーティリティ（距離・面積・重心計算）

### 設計方針
- **非同期処理**: 全てのDB操作・ファイルアクセスはFuture/async-awaitで実装
- **ツリー構造管理**: プロジェクト→フォルダ→GeoPackage→レイヤの階層管理
- **グローバル状態管理**: 選択状態・現在ツール・設定をGlobalConfigで一元管理
- **プラットフォーム対応**: Windows/Android両対応、デスクトップ向けsqflite初期化

## 使用方法

### 基本操作
1. **プロジェクト作成**: ホーム画面でプロジェクトフォルダを選択
2. **レイヤ作成**: ドロワーの「+」ボタンでGeoPackageファイル・レイヤを作成
3. **描画**: ツールバーでペンツールを選択し、地図上で描画
4. **編集**: 選択ツールでフィーチャを選択し、属性編集・位置調整

### GPS・GNSS接続
1. **内蔵GPS**: アプリ起動時に自動で位置情報取得を開始
2. **外部GNSS**: 設定画面でBluetooth GNSS受信機とペアリング・接続
3. **位置表示**: 地図上に青色アイコンで現在位置を表示

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

### v1.1.0 (最新)
- フォアグラウンドサービス機能追加
- デバッグログ最適化
- UI改善（サービス制御画面）

### v1.0.0
- 基本的な地図表示機能
- GPS位置情報取得
- Bluetooth GNSS対応

---

**開発者向けメモ**: 本プロジェクトは継続的な機能拡張を想定して設計されており、各機能は独立性と再利用性を重視した実装となっています。