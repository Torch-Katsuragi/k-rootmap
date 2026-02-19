---
name: gps-service
description: GPS追跡・測量機能の実装ガイド。InternalGpsLocationStore、GpsHistoryRecorder、フォアグラウンドサービス、外部GNSS機器連携を含む。GPS関連機能を実装・修正・デバッグする際に使用。
---

# GPS/GNSS サービス実装ガイド

## 核心コンセプト

### 常に1ストリーム

GPSハードウェアへのアクセスは常に1箇所だけ。

| プラットフォーム | GPSストリームの場所 | Storeのモード |
|-----------------|---------------------|---------------|
| Android | 別isolate (ForegroundService) | delegated（常時稼働） |
| Windows | メインisolate | direct |

### GPS軌跡は常時記録

GPSストリームは常時稼働し、`GpsHistoryRecorder` が全座標をGeoPackageに自動保存。
明示的な「追跡開始/停止」は不要。

## アーキテクチャ

```
InternalGpsLocationStore (常時稼働)
  └─→ positionStream
       ├─→ flutter_map マーカー (map_initialization_mixin)
       ├─→ GpsHistoryRecorder → gps_history.gpkg (日付別レイヤ)
       │    └─→ todayPoints → PolylineLayer (本日の軌跡をリアルタイム表示)
       └─→ GpsManagerService → GPS情報バー、測量

TrackExtractionDialog (ユーザー操作時)
  └─→ GpsHistoryRecorder から日付別ポイント読み取り
       └─→ 時間範囲選択 + Douglas-Peucker簡略化 → LineFeatureNode 保存
```

### GeoPackage構造

```
k_maps_global/gps_history.gpkg
  ├── gps_log_2026_02_04  (PointLayer, hidden)
  ├── gps_log_2026_02_05  (PointLayer, hidden)
  └── gps_log_2026_02_06  (PointLayer, hidden) ← 本日
```

## 重要な制約

### Bluetooth通信はメインisolateのみ

```
❌ フォアグラウンドサービス（別isolate）→ Bluetooth → NG
✅ メインisolate → Bluetooth → OK
```

## 使用パッケージ

| パッケージ | 用途 |
|-----------|------|
| `geolocator` | 内蔵GPS位置取得 |
| `flutter_background_service` | フォアグラウンドサービス（Android） |
| `flutter_bluetooth_serial` | Bluetooth通信（SSP対応） |

## 関連ファイル

```
lib/models/
├── gps_position_record.dart        # GPS座標レコード・レスポンスモデル
└── gps_track.dart                  # GpsTrackPoint（Recorder内部で使用）

lib/services/
├── internal_gps_location_store.dart # 内蔵GPS位置情報ストア（中核）
├── gps_history_recorder.dart        # GPS軌跡常時記録（GeoPackage日付別レイヤ）
├── foreground_service.dart          # フォアグラウンドサービス管理
├── gps_manager_service.dart         # 統合GPS管理（内蔵GPS+外部GNSS）
└── ...

lib/screens/map_page/
├── map_page.dart                    # PolylineLayer に本日軌跡表示
├── map_page_state_base.dart         # gpsHistoryRecorder 参照
└── mixins/
    ├── map_initialization_mixin.dart # Store+Recorder初期化
    ├── map_gps_tracking_mixin.dart   # 軌跡抽出ダイアログ呼び出し
    └── map_gps_survey_mixin.dart     # GPS測量

lib/widgets/
├── track_extraction_dialog.dart     # 軌跡切り取りUI（日付選択、時間範囲、簡略化）
└── gps_tracking_dialogs.dart        # SelectPointLayerDialog（測量用）

lib/tools/
└── gps_tool.dart                    # GPS測量ツール
```
