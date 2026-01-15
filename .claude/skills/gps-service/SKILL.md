---
name: gps-service
description: GPS追跡・測量機能の実装ガイド。フォアグラウンドサービス、外部GNSS機器連携、Bluetooth通信制約を含む。GPS関連機能を実装・修正・デバッグする際に使用。
---

# GPS/GNSS サービス実装ガイド

## 詳細資料

実装前に必ず参照：

| 資料 | パス |
|------|------|
| GPS追跡アーキテクチャ | `docs/technical/gps-architecture.md` |
| フォアグラウンドサービス制約 | `docs/technical/foreground-service.md` |
| GPS・地図機能設計 | `docs/features/gps-map.md` |

## アーキテクチャ概要

### 2つのGPSモード

| モード | 動作場所 | 用途 |
|--------|----------|------|
| GPS追跡 | フォアグラウンドサービス（別isolate） | 継続的なバックグラウンド記録 |
| GPS測量 | メインisolate | ユーザー手動操作での位置記録 |

### 内蔵GPS追跡フロー

```
[フォアグラウンドサービス]
  ↓ 内蔵GPS位置取得（Geolocator）
  ↓ 1秒間隔でイベント送信
[メインisolate]
  ↓ イベント受信
  ↓ データ保存（時間・距離フィルタ適用）
```

### 外部GNSS使用時

```
[フォアグラウンドサービス]
  ↓ 内蔵GPS（トリガー用）
[メインisolate]
  ↓ イベント受信（トリガー）
  ↓ Bluetooth経由で外部GNSSデータ取得
  ↓ データ保存
```

## ⚠️ 重要な制約

### Bluetooth通信はメインisolateのみ

```
❌ フォアグラウンドサービス（別isolate）→ Bluetooth → NG
✅ メインisolate → Bluetooth → OK
```

理由：
- `flutter_bluetooth_serial`はMethodChannelを使用
- MethodChannelはメインisolateでのみ動作
- isolate間でオブジェクト共有不可

### 正しい実装パターン

外部GNSSを使う場合：
1. フォアグラウンドサービスは内蔵GPSでトリガーを送るだけ
2. メインisolateでBluetoothデータを取得・記録
3. サービス停止で全て停止

## 使用パッケージ

| パッケージ | 用途 |
|-----------|------|
| `geolocator` | 内蔵GPS位置取得 |
| `flutter_background_service` | フォアグラウンドサービス |
| `flutter_bluetooth_serial` | Bluetooth通信（SSP対応） |

## 関連ファイル

```
lib/services/
├── gps_tracking_service.dart    # GPS追跡サービス
├── gnss_service.dart            # 外部GNSS連携
└── location_service.dart        # 位置情報管理

lib/tools/
└── gps_tool.dart                # GPS測量ツール
```
