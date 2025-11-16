# K-MAPS

GISアプリケーション（Flutter製）

## 最新の更新情報

### QGIS標準形式への移行（PRIMARY KEY: id → fid）+ フリーズ・クラッシュ対策 (2025-11-16 最新)

**改善内容**: K-MAPSをQGIS標準形式（`fid` PRIMARY KEY）に準拠させ、外部ファイルの互換性・安定性を大幅向上

**問題**: 
- 旧K-MAPSは独自に`id`カラムをPRIMARY KEYとして使用していた
- QGISは`fid`カラムをPRIMARY KEYとして標準的に使用する
- PRIMARY KEYの不一致により、QGIS作成ファイルが正しく読み込めない
- 特定のファイルを読み込むとフリーズやクラッシュが発生する

**解決策**:

**1. QGIS標準形式への準拠**
- ✅ **新規作成**: `fid INTEGER PRIMARY KEY AUTOINCREMENT`を使用（QGIS標準）
- ✅ **動的検出**: `PRAGMA table_info`でPRIMARY KEYカラムを自動検出（`fid`, `id`, `rowid`等）
- ✅ **内部正規化**: PRIMARY KEYの値を内部的に`id`として扱い、FeatureNodeとの互換性を維持

**2. フリーズ防止対策**
- ✅ **SQLエラー防止**: `ORDER BY id`を`ORDER BY "$pkColumn"`に修正（根本原因）
- ✅ **処理の統一**: PRIMARY KEYがない場合、テーブルサイズに関わらず`fid`を追加
- ✅ **進行状況表示**: 大容量テーブル（10,000行超）の場合は処理時間の警告を表示

**3. クラッシュ防止対策**
- ✅ **WKBバリデーション**: 座標値の妥当性チェック（緯度±90度、経度±180度）
- ✅ **異常値検出**: NaN、Infinite、範囲外の座標を検出
- ✅ **破損データスキップ**: 異常な座標を含むフィーチャをスキップしてクラッシュを防止

**4. ファイル形式検証**
- ✅ **GeoPackage構造チェック**: 必須テーブル・カラムの存在を検証
- ✅ **クリーンなログ**: 正常時（QGIS標準）はログなし、異常時のみ詳細ログ出力

**効果**:
- **QGIS標準準拠**: 新規作成ファイルは`fid`を使用し、QGISとの完全な相互運用を実現
- **QGIS互換性**: QGIS作成のGeoPackageファイルを正常に読み込める（警告なし）
- **後方互換性**: 旧K-MAPS作成ファイル（`id` PRIMARY KEY）も引き続き動作
- **処理の統一性**: PRIMARY KEYがないファイルは、テーブルサイズに関わらず`fid`を追加
- **フリーズ完全防止**: SQLエラー修正（`ORDER BY`動的化）で根本解決
- **クラッシュ防止**: WKB座標バリデーションで異常値を検出・スキップ
- **ファイル検証**: 破損ファイルや非標準形式を早期に検出
- **クリーンなログ**: 正常時（QGIS標準）は静か、異常時のみ詳細ログ

**技術参照**: 
- [GeoPackage Specification](https://www.geopackage.org/spec/) - GeoPackageの標準仕様
- [SQLite ROWID](https://www.sqlite.org/rowidtable.html) - SQLiteの内部行ID仕様

### UI要素極小化 - Point Feature＆線の太さ最適化 (2024-12-19 最新)

**改善内容**: Point Feature マーカーと線/ポリゴンの線の太さを大幅に細くして、地図の視認性を大幅向上

**問題**: Point Feature が現在位置マーカーより大きく、線も太すぎて地図が見づらい

**解決策**:

#### 1. **Point Feature 超小型化**
- **サイズ**: 12px → **8px**マーカー
- **円サイズ**: 
  - 通常時: 6px → **3px**（現在位置マーカーの15%）
  - 選択時: 8px → **4px**（現在位置マーカーの20%）
- **枠線**: 1px → **0.5px**（より繊細に）

#### 2. **線・ポリゴン線の太さ半減**
- **Line Features**: 3.0px → **1.5px** / 5.0px → **2.5px**（選択時）
- **Polygon Borders**: 3.0px → **1.5px** / 6.0px → **3.0px**（選択時）
- **GPS/Pen Preview**: 3.0-4.0px → **1.5-2.0px**
- **GPS Tracking**: 4.0px → **2.0px**

```dart
// Before: 大きなマーカーと太い線
Container(width: 6-8, strokeWidth: 3.0-5.0)

// After: 極小マーカーと細い線
Container(width: 3-4, strokeWidth: 1.5-2.5)
```

#### 📊 改善効果
- **地図視認性の劇的改善**: 背景地図がはっきり見える
- **測量精度向上**: より正確な位置特定が可能
- **情報密度向上**: 密集したフィーチャでも重ならない
- **視覚的階層の最適化**: 現在位置 > GPS測量点 > フィーチャポイント の明確な優先度
- **作業効率向上**: 細い線で詳細な地形や道路が見やすい

**技術参照**: [GIS UI Design Principles](https://gis.stackexchange.com/questions/tagged/cartography) - 地図表示での視覚的階層設計

### Shapefileエクスポート出力修正 (2024-12-19 最新)

**問題**: 属性テーブルからのShapeファイル出力で等間隔に並んだ四角が表示される問題

**根本原因**:
1. **ジオメトリ変換の欠如**: `FeatureNode.geometry`（`List<LatLng>`形式）がGeoJSON形式に変換されていない
2. **Point cloudオプションの未実装**: フィーチャエクスポートダイアログにPoint cloudオプションが存在しない

**解決策**:

#### 1. **処理フローの統一**
```dart
// Before: FeatureNode経由の手動変換
final tableData = await _getTableData();
final features = tableData[1] as List<FeatureNode>;
final geoJsonFeature = await _convertFeatureNodeToGeoJson(feature);

// After: レイヤーエクスポートと同じ処理フロー
final features = await layerNode.geoPackageFile.getFeatures(layerName);
final geometryType = await layerNode.geoPackageFile.getGeometryType(layerName);
final geoJsonFeatures = await importExportService.convertFeaturesToGeoJson(features, geometryType);
```

#### 2. **Point cloudオプションのUI実装**
- フィーチャエクスポートダイアログに`Convert to Point Cloud`チェックボックスを追加
- Shapefile形式選択時のみ表示される条件付きUI
- ポリゴン/線を構成点に分解してPoint Shapefileを生成

#### 3. **デバッグログ強化**
- GeoJSON変換成功時の詳細ログ: `変換成功: Point/Polygon`
- Polygon座標の最初の数点をログ出力: `座標[0]: x=139.xxx, y=35.xxx`
- フィーチャ構造の詳細解析: ジオメトリタイプ、リング数、総点数

#### 📊 修正効果
**Before**: 
- FeatureNode経由 → 手動GeoJSON変換 → 処理の重複・不整合
- Point cloudオプション未実装

**After**: 
- DBから直接取得 → 統一されたGeoJSON変換 → レイヤーエクスポートと同じ品質
- Point cloudオプション選択可能 → 用途に応じた出力形式

#### 🔧 統一された処理フロー
1. **データ取得**: `geoPackageFile.getFeatures()` - DBから直接取得
2. **ジオメトリタイプ判定**: `geoPackageFile.getGeometryType()` - 正確な型情報
3. **GeoJSON変換**: `importExportService.convertFeaturesToGeoJson()` - テスト済みの変換ロジック
4. **Shapefileエクスポート**: `FeatureExportConverter` - レイヤーエクスポートと同じ処理

#### 💡 技術的利点
- **保守性向上**: レイヤーエクスポートとフィーチャエクスポートで同じコードを共有
- **品質向上**: テスト済みの変換ロジックを再利用
- **パフォーマンス**: FeatureNode作成をスキップしてDBから直接データ取得

**技術参照**: [GeoJSON Specification RFC 7946](https://tools.ietf.org/html/rfc7946) - 座標配列の標準形式

### Shapefileインポート機能修正 (2024-12-19)

**問題**: PolygonのShapefileを読み込む際、Pointレイヤーとして誤認識され、データが正しく追加されない問題

**根本原因**:
1. **ジオメトリタイプの誤った推定**: `_readShapefileInfo`メソッドがファイルサイズでジオメトリタイプを推定
2. **バッチ処理の不整合**: PolygonデータをPointとして処理しようとしてエラー発生

**解決策**:

#### 1. **正確なSHPヘッダー解析**
- ファイルサイズベース推定を削除
- SHPバイナリヘッダー（オフセット32）からシェープタイプを読み取り
- 全Shapefileタイプに対応:
  ```
  1: Point          8: MultiPoint      21: PointM
  3: PolyLine      11: PointZ         23: PolyLineM
  5: Polygon       13: PolyLineZ      25: PolygonM
                   15: PolygonZ
  ```

#### 2. **バッチデータ処理の改善**
- `_processBatchData`メソッドでデータ内容から実際のジオメトリタイプを判定
- 適切なバッチ処理メソッドを選択:
  ```
  Point: {'point': LatLng} → addPointsBatch
  Line: {'line': List<LatLng>} → addLinesBatch
  Polygon: {'rings': List<List<LatLng>>} → addPolygonsBatch
  ```

#### 3. **エラーハンドリング強化**
- データ形式不整合の詳細ログ出力
- フォールバック処理の改善

#### 📊 修正効果
**Before**: Polygonが常にPointとして認識 → データ追加失敗
**After**: 正確なジオメトリタイプ判定 → 適切なレイヤー作成

**技術参照**: [ESRI Knowledge Base - Shapefile Support Files](https://support.esri.com/en-us/knowledge-base/error-failed-to-add-data-unsupported-data-type-shapefil-000019952)

### ログ出力最適化 (2024-12-19)

**問題**: デバッグ時にGeoPackageFileの初期化ログが繰り返し出力され、重要な情報が埋もれてしまう問題

**解決策**: 
1. **冗長ログの削除**: GeoPackageFileクラスの不要なログを削除・最適化
   - `[GeoPackageFile] データベース初期化開始` → 削除
   - `[GeoPackageFile] 既に初期化済み` → 削除  
   - `[GeoPackageFile] pathList: [...]` → 削除
   - `[GeoPackageFile] 絶対パス: ...` → 削除
   - `[GeoPackageFile] ファイル: ...` → 削除
   - `[GeoPackageFile] 親ディレクトリ存在確認: OK` → 削除

2. **重要情報のみ保持**: エラー時と重要な成功時のみログ出力
   - `[GeoPackageFile] 初期化成功: ファイル名.gpkg` → 保持
   - `[GeoPackageFile] 初期化失敗: ...` → 保持
   - `[GeoPackageFile] 親ディレクトリを作成: パス` → 保持

3. **Impellerエンジン無効化**: 過度なレンダリングログを削減
   - `flutter run --no-enable-impeller`でアプリ起動
   - ログの見やすさを大幅改善

#### 📊 ログ最適化効果
**Before**: 毎回のデータベースアクセスで5-8行の冗長ログ出力
```
[GeoPackageFile] データベース初期化開始
[GeoPackageFile] pathList: [measurement.gpkg]
[GeoPackageFile] 既に初期化済み
(繰り返し)
```

**After**: 必要最小限の情報のみ
```
(冗長ログなし、エラー時のみ出力)
```

**参考**: [Managing Flutter Logs: Reducing Noise in Debug Console](https://medium.com/@punithsuppar7795/managing-flutter-logs-reducing-noise-in-debug-console-0229ff7a9235)

### FeatureExportConverter デバッグ出力整理 (2024-12-19 最新)

**作業内容**: 開発完了後の本番環境対応として、過剰なデバッグ出力を削除・整理

#### 🧹 削除されたデバッグ出力
1. **詳細な進行状況ログ**: 各変換ステップの詳細情報
2. **フィーチャサンプル表示**: フィーチャ内容の冗長な文字列出力
3. **WKB解析詳細ログ**: 座標解析の詳細情報
4. **Shapefile作成詳細**: ファイル書き込みの詳細進行状況
5. **バイナリデータ分析**: ファイルサイズ・構造の詳細ログ

#### ✅ 保持されたログ
- **重要なエラーログ**: 失敗時の原因特定に必要
- **進行状況表示**: `notifyProgress()`による視覚的フィードバック
- **基本的な成功・失敗通知**: ConversionResult

#### 📊 最適化効果
**Before**: 1つのエクスポートで50-100行のデバッグ出力
```
[FeatureExportConverter] 変換開始: 1個のフィーチャ
[FeatureExportConverter] フィーチャサンプル: ID=1, GeometryType=Polygon
[FeatureExportConverter] メタデータサンプル: {id: 1, geom: [71, 80, 0, 1...
[FeatureExportConverter] ポイントクラウド処理中のフィーチャ: {...
[FeatureExportConverter] WKB解析開始: 309バイト, タイプ: Polygon
（50-100行続く）
```

**After**: 必要最小限のログのみ
```
（エラー時のみログ出力、正常時は静寂）
```

#### 🚀 技術的利点
- **パフォーマンス向上**: ログ出力処理の削減
- **本番環境適合**: 過剰な情報露出を防止
- **デバッグ効率**: 重要なエラーが埋もれなくなる
- **コードの可読性**: 処理に集中できるコード構造

**参考**: [Flutter Debugging Tools](https://docs.flutter.dev/testing/debugging) - 効率的なデバッグ手法

### 属性テーブルからのFeature変換出力機能実装 (2024-12-19 最新)

**新機能**: 属性テーブルから直接、複数形式でのFeature変換出力が可能に

参考: [Flutter GIS Applications](https://github.com/timsneath/landmarks_flutter) および [ArcGIS Maps SDK for Flutter](https://www.esri.com/arcgis-blog/products/developers/developers/mapping-coffee-flutter-maps-sdk/) のようなモダンなGISアプリケーションでは、データ変換機能が重要な要素となっています。

#### 🚀 実装された機能

#### 1. **属性テーブル統合エクスポート**
- 属性テーブル画面に**Feature変換出力ボタン**（🔄アイコン）を追加
- 既存のTSVエクスポートに加えて、多様な形式に対応
- レイヤー内全フィーチャの一括変換出力

#### 2. **対応出力形式**
```
📄 GeoJSON (.geojson) - 標準的なGISデータ交換形式
📊 CSV (.csv) - 表形式での属性データ出力
🗺️ KML (.kml) - Google Earth等で表示可能
🔷 Shapefile (.shp) - 業界標準のGISファイル形式
```

#### 3. **Point Cloud変換オプション** ⭐
- **革新的な機能**: LineやPolygonを構成点に分解
- Point形式での出力で軽量化・高速処理が可能
- 大量データの可視化やAnalytics処理に最適

#### 4. **ユーザーフレンドリーなUI**
```dart
// 選択可能オプション
- 出力形式選択（ドロップダウン）
- Point Cloud変換（チェックボックス）
- フィーチャ数表示（リアルタイム）
- 進行状況表示（ローディング）
```

#### 5. **技術的実装詳細**

**データフロー**:
```
AttributeTable → FeatureNode → GeoJSON → FeatureExportConverter → 出力ファイル
```

**Point Cloud変換時**:
```
Polygon/Line → 構成点抽出 → Point配列 → Point Shapefile/GeoJSON
```

**ファイル命名規則**:
```
{GeoPackage名}_{レイヤー名}_features.{拡張子}
例: measurement_polygon_features.geojson
```

#### 📊 利用シーン

1. **研究・分析**: Point Cloud形式でのデータ分析
2. **データ交換**: 他のGISソフトウェアとの連携
3. **軽量化**: 複雑なPolygonをPointに変換してパフォーマンス向上
4. **可視化**: 異なる形式での地図表示・共有

#### 🛠️ 使用方法

1. **属性テーブルを開く**: レイヤーの属性テーブルボタンをクリック
2. **変換出力**: 🔄ボタンをクリック
3. **形式選択**: 出力形式とPoint Cloud変換オプションを選択
4. **エクスポート実行**: 指定パスにファイル出力

#### 技術参照
- [Flutter Landmarks Example](https://github.com/timsneath/landmarks_flutter): Flutterでのマップアプリケーション実装例
- [ArcGIS Maps SDK for Flutter](https://www.esri.com/arcgis-blog/products/developers/developers/mapping-coffee-flutter-maps-sdk/): 企業レベルのGISアプリケーション開発
- [Shapefile ProjectionFinder](https://www.egger-gis.at/automatic-projection-detection/shapefile-projectionfinder): 自動投影検出ツール（座標系の自動判定）

#### 🔧 技術修正メモ

**型キャストエラー修正**:
- `FeatureConversionParams.targetLayer`をオプショナルに変更
- エクスポート処理では`targetLayer: null`を指定
- インポート処理とエクスポート処理の明確な分離

**投影・座標系対応**:
- WKT形式での座標系情報保持
- PRJファイルの自動読み込み
- 将来的にはShapefile ProjectionFinderのような自動投影検出の実装を検討

## アーキテクチャ概要

### Polygon Shapefileエクスポート問題 - デバッグ強化版 (2024-12-19 最新)

**問題**: Polygonレイヤーをエクスポートした際に、564バイトの不正なShapefileが生成され、GISソフトで正しく読み込めない問題

**現在の修正状況**:

#### ✅ 完了した修正
1. **Shapefile仕様準拠の修正**: ファイル長・レコード長計算を16bit words単位で正確に実装
2. **SHXファイル完全修正**: オフセット計算とレコード長の正確な算出
3. **Polygon専用DBFファイル**: 適切な属性フィールド（FID、ID、NAME、DESC、AREA、PERIMETER、PARTS、POINTS）
4. **バイナリヘルパーメソッド**: 正しいエンディアン変換の実装確認済み
5. **ログ簡略化**: 長すぎるフィーチャサンプル出力を簡潔に改善

#### 🔧 現在のデバッグ強化
- **座標データ詳細ログ**: 最初のPolygonフィーチャの構造詳細出力
- **バウンディングボックス分析**: 計算結果と推定ファイルサイズの表示
- **ファイルサイズ検証**: 書き込み後の詳細なサイズ分析

#### 🔍 調査中の問題
現在564バイトという異常に小さなファイルサイズが生成される原因を特定中。
可能性：
1. 座標データの処理で問題が発生
2. レコード内容の書き込みエラー
3. GeoJSON→Shapefile変換時のデータ損失

#### 📝 技術詳細

**Shapefile構造（正常な場合）**:
- ヘッダー: 100バイト
- 各Polygonレコード: ヘッダー(8) + コンテンツ(可変)
- 最小期待サイズ: 200バイト以上（ポリゴン1個の場合）

**現在の実装**:
- ✅ ファイル長計算: 16bit words単位で正確に計算
- ✅ レコードヘッダー: ビッグエンディアンで正しく書き込み
- ✅ 座標データ: リトルエンディアンで正確に格納
- ✅ バウンディングボックス: 有効座標のみで正確に計算

**デバッグ出力例**:
```
[FeatureExportConverter] 最初のPolygonフィーチャ詳細:
[FeatureExportConverter]   ジオメトリタイプ: Polygon
[FeatureExportConverter]   リング数: 1
[FeatureExportConverter]   リング0: 18点
[FeatureExportConverter]     最初の点: [135.948096, 33.938995]
[FeatureExportConverter]     最後の点: [135.948096, 33.938995]
[FeatureExportConverter] バウンディングボックス: (135.947676, 33.938066) - (135.949051, 33.939049)
[FeatureExportConverter] 推定ファイルサイズ: XXXバイト
[FeatureExportConverter] ⚠️ 警告: ファイルサイズが異常に小さいです
```

#### 🎯 次のステップ
1. デバッグ出力でデータフローを詳細分析
2. 実際の座標データ書き込み処理の検証
3. バイナリファイル内容の16進ダンプ確認
4. GIS読み込みテストでの検証

**確認済み項目**:
- ✅ `_writeNativePolygonShapefile`メソッドが正しく呼ばれている
- ✅ バイナリヘルパーメソッドが正しく実装されている  
- ✅ Polygon処理パスが正しく選択されている
- ✅ フィーチャデータが存在している（2個のPolygonフィーチャ）

### Polygon形状保持Shapefileエクスポート機能実装完了 (2024-12-19)

**問題**: Polygonレイヤーをエクスポートした際に、強制的にポイントクラウド（点群）として出力される問題

**解決策**: `ImportExportService`と`FeatureExportConverter`を統合し、完全な元形状保持エクスポートを実装

#### 最終機能仕様
- ✅ **レイヤーエクスポート**: 常に元の形状を保持（Polygon → Polygon、LineString → PolyLine、Point → Point）
- ✅ **個別フィーチャエクスポート**: デフォルトで元の形状を保持
- ✅ **ポイントクラウド変換**: 属性テーブルからの個別出力でのみ利用可能
- ✅ **シンプルなUI**: レイヤーエクスポートから混乱を招くオプションを削除

#### 技術実装詳細

**1. ImportExportService統合**
- `_exportToShapefile`メソッドで`FeatureExportConverter`を活用
- GeoPackageからGeoJSON形式への中間変換
- 元の形状データの完全保持

**2. 明確な用途分離**
- **レイヤー全体エクスポート**: 常に元の形状保持（測量・GIS用途）
- **個別フィーチャエクスポート**: 分析用途でオプション選択可能

**3. ジオメトリタイプ別対応**
- Point → Point Shapefile（Shapeタイプ1）
- LineString → PolyLine Shapefile（Shapeタイプ3）
- Polygon → Polygon Shapefile（Shapeタイプ5）

### Windows環境でのFile Selector問題解決 (2024-12-19)

**問題**: Windowsで`file_selector`プラグインが`PlatformException(channel-error)`を発生させる問題
**解決策**: `DialogManager`にフォールバック機能を実装

- `file_selector`が失敗した場合、`file_picker`に自動フォールバック
- エラーハンドリングとデバッグ出力を強化
- クロスプラットフォーム対応でより安定した動作を実現

#### 対応済み機能
- ✅ レイヤーエクスポート（Shapefile、GeoJSON、KML、CSV対応）
- ✅ フィーチャエクスポート（個別フィーチャの選択エクスポート）  
- ✅ 属性テーブルからのコンテキストメニューエクスポート
- ✅ レイヤー右クリックメニューからのエクスポート
- ✅ **元の形状保持Shapefileエクスポート**（Polygon/LineString/Point）
- ✅ **シンプルなUI設計**（混乱を招くオプションを削除）
- ✅ 完全なShapefileサポート（.shp/.shx/.dbf/.prjファイル生成）
- ✅ Windows環境でのファイルダイアログ安定化

## 機能概要

### エクスポート機能

#### 用途別エクスポート方式
1. **レイヤー全体エクスポート**（測量・GIS用途）
   - レイヤー右クリック → "Export Layer"
   - **常に元の形状を保持**: Polygon → Polygon、LineString → PolyLine
   - シンプルなUI（オプション選択なし）

2. **個別フィーチャエクスポート**（分析用途）
   - 属性テーブル → 右クリック → "Export as Shapefile"
   - デフォルト: 元の形状保持
   - 必要に応じてポイントクラウド変換も可能

#### Shapefileエクスポート仕様
- **Point → Point Shapefile**: 座標データの正確な保持
- **LineString → PolyLine Shapefile**: 線形状の完全保持
- **Polygon → Polygon Shapefile**: 面形状の完全保持（複数リング・穴対応）
- **完全ファイルセット**: .shp/.shx/.dbf/.prj

### インポート機能
- **対応形式**: Shapefile, GeoJSON, KML, CSV, GPX
- **マルチプラットフォーム**: Windows、macOS、Linux対応
- **ドラッグ&ドロップ**: 直感的なファイル操作
- **進行状況表示**: リアルタイム処理状況確認

### GPS・測量機能
- **リアルタイムGPS追跡**: 
  - 位置情報の連続取得
  - **ポイント都度保存方式**: GPS軌跡を安全にポイントとして保存
  - フォアグラウンドサービスによるバックグラウンド動作
  - 保存先PointLayerNodeを選択可能
  - レイヤー消失時の自動停止機能
  - 後でpoint→line変換により軌跡を復元
- **GNSS NMEA対応**: 高精度測位データ対応
- **GPS測量ツール**: ポイント・ライン・ポリゴン描画
- **GPS測量メタデータ**: 精度、時刻、データソース等を各ポイントに記録

### データ管理
- **GeoPackage統合**: SQLiteベースの地理空間データベース
- **レイヤー管理**: 階層型レイヤー構造
- **属性テーブル**: 詳細なメタデータ管理
  - **Pointレイヤー専用機能**: 仮想`_coordinate`列で座標を直接編集可能
    - **座標系変換機能**: 15種類のEPSGコードから選択可能
      - WGS 84 (EPSG:4326) - GPS/Webマップ標準
      - Web Mercator (EPSG:3857) - Google Maps等
      - JGD2011 地理座標系 (EPSG:6668)
      - JGD2011 平面直角座標系 全系対応 (EPSG:6669~6683)
    - **検索可能なプルダウン**: EPSGコードや地域名で素早く検索
    - **自動座標変換**: 選択されたEPSGで座標を表示・編集
    - 配列形式`[x, y]`なのでデータのコピー&ペーストが容易
    - バリデーション付き（不正な入力は受け付けず元の値に戻す）
    - 編集内容はWGS84に変換されてgeomに即座に反映
    - 仮想カラムなので、GeoPackageの構造には影響しない
- **座標系対応**: WGS84、WebMercator、JGD2011、UTM、平面直角座標系

## システム要件

- **Flutter**: 3.0以降
- **Dart**: 2.18以降
- **OS**: Windows 10/11、macOS 10.15以降、Ubuntu 18.04以降
- **メモリ**: 4GB以上推奨
- **ストレージ**: 500MB以上の空き容量

## 開発・運用情報

### アーキテクチャ
- **MVVMパターン**: クリーンなコード構造
- **コンバーターパターン**: 柔軟なデータ変換
- **サービス指向**: 機能別モジュール分離
- **リアクティブ**: Streamベースの状態管理

### パフォーマンス最適化
- **バックグラウンド処理**: UI応答性の維持
- **メモリ効率**: 大容量データの段階的処理
- **キャッシュ機能**: 頻繁アクセスデータの高速化
- **プログレス表示**: ユーザーエクスペリエンス向上

### 品質保証
- **型安全性**: Dart強型チェック活用
- **エラーハンドリング**: 包括的例外処理
- **ログ出力**: デバッグ・トラブルシューティング対応
- **テスト**: ユニット・統合テスト実装

---

**現在の機能**: 完全なPolygon/LineString Shapefileエクスポート、GPS測量、GeoPackage管理、クロスプラットフォーム対応

**今後の予定**: GeoJSON/KML/CSV完全サポート、高度な座標変換、3D測量対応