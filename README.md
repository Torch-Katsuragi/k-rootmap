# K-MAPS

## 概要
K-MAPSはGeoPackageベースの地理情報管理・編集アプリケーションです。地図上での点・線・面の描画・編集、GPS位置情報の取得、外部GNSS受信機との連携などの機能を提供します。

## 主要機能

### 地図機能
- OpenStreetMapベースの地図表示
- レイヤ構造での地理情報管理（点・線・面）
- フリーハンド描画とタップによる図形作成
- フィーチャの選択・編集・削除
- 属性情報の表示・編集

### GPS・GNSS機能  
- 内蔵GPS/GNSS受信機による現在位置取得
- SSP対応Bluetooth GNSS受信機との連携
- NMEA-0183フォーマットの位置データ解析
- リアルタイム位置情報表示
- 衛星情報・精度情報の詳細表示

### データ管理機能
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

### flutter_bluetooth_serialのnamespaceエラー（Android）

Android環境でビルド時に「Namespace not specified」エラーが発生した場合：


}
```

**修正方法- .pub-cache編集**：
以下のファイルにnamespaceを追加してください：
```
<ユーザーフォルダ>/.pub-cache/hosted/pub.dev/flutter_bluetooth_serial-0.4.0/android/build.gradle
```

編集内容：
```gradle
android {
    namespace 'io.github.edufolly.flutterbluetoothserial'
    compileSdkVersion 33
    // ... 既存のコード ...
}
```

修正後：
```bash
flutter clean
flutter pub get
flutter build apk
```

**注意**: 代替案の修正は`flutter pub get`実行時に上書きされる可能性があります。

## 開発者向け情報
詳細な技術仕様・クラス構成・API仕様については、各ソースファイルのドキュメントコメントを参照してください。