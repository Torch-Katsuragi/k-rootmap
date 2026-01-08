---
title: Import/Export Service アーキテクチャ
tags: [technical, architecture, import, export]
---

# Import/Export Service アーキテクチャ（リファクタリング完了）

2024年12月のリファクタリングにより、`import_export_service.dart`（約3,800行）を以下のモジュラー構造に分割しました。

## ディレクトリ構造

```
lib/services/
├── import_export/                    # 新規ディレクトリ
│   ├── import_export_service.dart    # ファサード（軽量なエントリポイント）
│   ├── import_export_models.dart     # FileFormat, ImportExportResult等
│   ├── coordinate_system_manager.dart # SmartCoordinateSystemManager
│   ├── importers/
│   │   ├── base_importer.dart        # 抽象インポーター
│   │   ├── shapefile_importer.dart   # Shapefileインポート
│   │   └── geojson_importer.dart     # GeoJSONインポート
│   ├── exporters/
│   │   ├── base_exporter.dart        # 抽象エクスポーター
│   │   ├── shapefile_exporter.dart   # Shapefileエクスポート
│   │   ├── geojson_exporter.dart     # GeoJSONエクスポート
│   │   ├── csv_exporter.dart         # CSVエクスポート
│   │   └── kml_exporter.dart         # KMLエクスポート
│   └── parsers/
│       ├── shapefile_binary_parser.dart  # SHP/SHXバイナリ解析
│       ├── dbf_reader.dart           # DBF読み込み
│       └── prj_reader.dart           # PRJ読み込み（座標系解析）
├── import_export_service.dart        # 後方互換性のためのre-export
lib/utils/
└── binary_utils.dart                 # バイト変換ヘルパー（共通化）
```

## 設計原則

1. **ファサードパターン**: `ImportExportService`は軽量なエントリポイントとして、各インポーター/エクスポーターを呼び出すのみ
2. **DRY原則**: バイナリ変換ヘルパーを`binary_utils.dart`に統合し、重複コードを排除
3. **疎結合**: 各モジュールは独立して動作可能で、依存関係を最小化
4. **後方互換性**: 元の`import_export_service.dart`はre-exportファイルとして残し、既存コードへの影響を最小化

## 各モジュールの想定行数

| ファイル | 行数 | 内容 |
|---------|------|------|
| import_export_models.dart | ~100 | enum, 結果クラス |
| coordinate_system_manager.dart | ~300 | 座標系解析・変換 |
| base_importer.dart | ~30 | 抽象クラス |
| shapefile_importer.dart | ~250 | SHPインポート |
| geojson_importer.dart | ~200 | GeoJSONインポート |
| base_exporter.dart | ~20 | 抽象クラス |
| shapefile_exporter.dart | ~400 | SHPエクスポート |
| geojson_exporter.dart | ~130 | GeoJSONエクスポート |
| csv_exporter.dart | ~100 | CSVエクスポート |
| kml_exporter.dart | ~120 | KMLエクスポート |
| shapefile_binary_parser.dart | ~350 | バイナリ解析 |
| dbf_reader.dart | ~180 | DBF読み込み |
| prj_reader.dart | ~50 | PRJ読み込み |
| binary_utils.dart | ~140 | バイト変換 |
| import_export_service.dart (facade) | ~180 | ファサード |

## GeoPackage 互換性に関する注意事項

### 仮想カラム（`_`で始まるカラム名）

K-MAPSでは、`_`で始まるカラム名を**仮想カラム**として扱います。

| カラム名 | 用途 | 備考 |
|---------|------|------|
| `_row_num` | 行番号表示 | 属性テーブルUIで自動生成 |
| `_lat`, `_lon` | WGS84座標表示 | Pointレイヤーで座標表示時 |
| `_x`, `_y` | 変換座標表示 | EPSG指定時の座標変換結果 |

**仕様:**
- 仮想カラムは**表示専用**であり、GeoPackageには保存されません
- 外部ツールで作成したGeoPackageに`_`で始まるカラムが存在する場合、K-MAPSでは**編集不可**となります

**外部互換性への影響:**
- QGISやArcGISなど他のGISソフトウェアで`_`で始まるカラム名を持つGeoPackageを作成した場合、K-MAPSではそのカラムの値を編集・保存できません
- これはデータ安全性（意図しない上書き防止）とのトレードオフです
- 必要に応じて、外部ツールでカラム名をリネームしてからインポートしてください

### PRIMARY KEY カラムの扱い

- 属性テーブルUIでは、PRIMARY KEYカラム（`fid`, `id`など）は非表示です
- 新規追加したフィーチャのPRIMARY KEY値は内部的に自動採番されますが、表示には行番号（`#`）を使用します

## 関連ドキュメント

- [[../features/geometry-types]] - レイヤジオメトリタイプ仕様
- [[tech-stack]] - 技術スタック

