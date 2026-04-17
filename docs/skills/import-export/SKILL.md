---
name: import-export
description: Import/Export機能の実装ガイド。Shapefile、GeoJSON、KML、CSVのインポート/エクスポート、座標系変換を含む。ファイル入出力機能を実装・修正する際に使用。
---

# Import/Export 実装ガイド

## 詳細資料

実装前に参照：

| 資料 | パス |
|------|------|
| Import/Exportアーキテクチャ | `docs/technical/import-export.md` |
| ジオメトリタイプ仕様 | `docs/features/geometry-types.md` |

## モジュール構造

```
lib/services/import_export/
├── import_export_service.dart      # ファサード（エントリポイント）
├── import_export_models.dart       # FileFormat, ImportExportResult
├── coordinate_system_manager.dart  # 座標系解析・変換
├── importers/
│   ├── base_importer.dart          # 抽象インポーター
│   ├── shapefile_importer.dart
│   └── geojson_importer.dart
├── exporters/
│   ├── base_exporter.dart          # 抽象エクスポーター
│   ├── shapefile_exporter.dart
│   ├── geojson_exporter.dart
│   ├── csv_exporter.dart
│   └── kml_exporter.dart
└── parsers/
    ├── shapefile_binary_parser.dart
    ├── dbf_reader.dart
    └── prj_reader.dart
```

## 設計原則

| 原則 | 説明 |
|------|------|
| ファサードパターン | `ImportExportService`は軽量なエントリポイント |
| DRY | バイナリ変換は`binary_utils.dart`に統合 |
| 疎結合 | 各モジュールは独立動作可能 |
| 後方互換性 | 元ファイルはre-exportとして維持 |

## サポート形式

### インポート

| 形式 | 拡張子 | 備考 |
|------|--------|------|
| Shapefile | .shp, .shx, .dbf, .prj | バイナリ解析 |
| GeoJSON | .geojson, .json | 標準JSON |

### エクスポート

| 形式 | 拡張子 | 備考 |
|------|--------|------|
| Shapefile | .shp, .shx, .dbf, .prj | バイナリ生成 |
| GeoJSON | .geojson | 標準JSON |
| KML | .kml | Google Earth互換 |
| CSV | .csv | 座標テキスト出力 |

## 新規フォーマット追加時

1. `base_importer.dart` または `base_exporter.dart` を継承
2. `importers/` または `exporters/` に新ファイル作成
3. `import_export_models.dart` の `FileFormat` enumに追加
4. `import_export_service.dart` のファサードから呼び出し

## 座標系変換

`SmartCoordinateSystemManager` が担当：
- PRJファイルからの座標系検出
- EPSG コード解析
- WGS84への変換

## 関連ユーティリティ

```
lib/utils/
└── binary_utils.dart    # バイト変換ヘルパー
```
