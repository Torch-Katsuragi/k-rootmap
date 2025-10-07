# K-MAPS 技術資料

## フォアグラウンドサービスとBluetooth通信の制約

### 外部GNSS機器との通信における技術的制約

#### 問題の背景
K-MAPSでは、SSP（Secure Simple Pairing）対応の外部GNSS機器（例：u-blox Geode）との通信を実装していますが、フォアグラウンドサービス（別isolate）での実装には重大な制約があります。

#### 技術的制約の詳細

##### 1. Flutter Isolateの制約
- **Flutterのisolateは独立したメモリ空間で動作**
  - メインisolateとフォアグラウンドサービスisolateは別々のDart VM上で実行
  - isolate間でオブジェクトを直接共有できない
  - プリミティブ型やJSONシリアライズ可能なデータのみ送受信可能

##### 2. Bluetooth通信の制約
- **Bluetoothプラグイン（flutter_bluetooth_serial）はMethodChannelを使用**
  - MethodChannelはメインisolateでのみ動作
  - フォアグラウンドサービス（別isolate）からはMethodChannelにアクセス不可
  - Bluetooth接続、データ受信、NMEAパース等の処理が実行できない

##### 3. プラットフォーム固有の制限
- **AndroidのBluetooth APIアクセス**
  - Bluetooth通信はUIスレッド（メインisolate）からのみ安全にアクセス可能
  - バックグラウンドサービスからのBluetooth操作は不安定
  - 接続状態の監視、データストリームの受信が困難

#### 実装上の結論

**外部GNSS機器はフォアグラウンドサービスで使用すべきではない**

理由：
1. MethodChannelがフォアグラウンドサービスisolateで動作しない
2. Bluetooth接続の確立・維持がメインisolateでのみ可能
3. NMEAデータの受信・パースがメインisolateでのみ実行可能
4. 実装が複雑化し、エラーハンドリングが困難

### K-MAPSでの実装方針

#### GPS追跡機能のアーキテクチャ

##### 内蔵GPS使用時
```
[フォアグラウンドサービス（別isolate）]
  ↓ 内蔵GPS位置取得（Geolocator）
  ↓ 1秒間隔でイベント送信
[メインisolate]
  ↓ イベント受信
  ↓ データ保存（時間・距離フィルタ適用）
```

##### 外部GNSS使用時（改善版）
```
[フォアグラウンドサービス（別isolate）]
  ↓ 内蔵GPS位置取得（トリガー用）
  ↓ 1秒間隔でイベント送信
[メインisolate]
  ↓ イベント受信（トリガー）
  ↓ 外部GNSSデータ取得（Bluetooth経由）
  ↓ データ保存（時間・距離フィルタ適用）
```

**重要なポイント:**
- フォアグラウンドサービスは常に内蔵GPSで動作
- 外部GNSS使用時は、フォアグラウンドサービスからのイベントをトリガーにして、メインisolateで外部GNSSデータを記録
- これにより、開始・停止処理が統一され、フォアグラウンドサービスの停止で全て止まる
- フォアグラウンドサービスが動作していない時は外部GNSS記録も発火しない

#### GPS測量機能との違い

**GPS測量モード（gps_tool）:**
- メインisolateで動作
- 外部GNSS機器を直接使用可能
- ユーザーの手動操作で位置を記録
- フォアグラウンドサービス不要

**GPS追跡機能:**
- フォアグラウンドサービスで継続的に動作
- 外部GNSS使用時はハイブリッド方式（トリガー + メインisolate処理）
- 自動的に位置を記録
- バックグラウンドでも動作継続

### 参考資料

#### 使用パッケージ
- `flutter_background_service`: ^5.0.10 - フォアグラウンドサービス実装
- `flutter_bluetooth_serial`: ^0.4.0 - Bluetooth通信（SSP対応）
- `geolocator`: ^13.0.2 - 内蔵GPS位置情報取得
- `location`: ^7.0.0 - Mock Location Provider連携

#### 関連ファイル
- `lib/services/foreground_service.dart` - フォアグラウンドサービス管理（内蔵GPS専用）
- `lib/services/gps_manager_service.dart` - 統合GPS管理サービス（メインisolate）
- `lib/models/bluetooth_gnss_service.dart` - 外部GNSS通信サービス（メインisolate）
- `lib/screens/map_page.dart` - GPS追跡機能実装（ハイブリッド方式）
- `lib/tools/gps_tool.dart` - GPS測量機能（メインisolate専用）

#### 技術的参考情報
- Flutter Isolateは独立したメモリ空間で動作し、MethodChannelはメインisolateでのみ利用可能
- Bluetooth通信はプラットフォームチャネル経由でネイティブコードを呼び出すため、メインisolateが必須
- フォアグラウンドサービスでの外部GNSS使用は技術的に不可能
- 代替案として、フォアグラウンドサービスをトリガーとして使用し、メインisolateで外部GNSSデータを処理

### 実装上の注意事項

1. **外部GNSS機器の接続はメインisolateで管理**
   - GPS設定画面でのスキャン・接続
   - 接続状態の監視
   - NMEAデータの受信・パース

2. **GPS追跡時の処理分離**
   - 内蔵GPS: フォアグラウンドサービスで完結
   - 外部GNSS: フォアグラウンドサービス（トリガー）+ メインisolate（データ取得）

3. **GPS測量時の処理**
   - 完全にメインisolateで動作
   - 外部GNSS機器を直接使用可能
   - ユーザー操作に応じて位置を記録

4. **ログ出力の最適化**
   - 定期的なログ出力は削減
   - エラー発生時のみ詳細ログを出力
   - デバッグ時の問題特定を容易にする

### デバッグ時の確認ポイント

- `source_type`カラムの値: `GPS`（内蔵GPS）または`GNSS`（外部GNSS）
- フォアグラウンドサービスのログ: 常に内蔵GPSのみを使用
- メインisolateのログ: 外部GNSS使用時のデータ取得状況
- 属性テーブルでの確認: 外部GNSS使用時は`source_type = 'GNSS'`になっているか
