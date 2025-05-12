# K-MAPS

本リポジトリは、直感的なGeoPackage編集・作成モバイルアプリ「K-MAPS」の開発用です。

- 詳細な機能設計・仕様は[FEATURES.md](./FEATURES.md)を参照。

## プロジェクト初期化

Flutterでプロジェクトを初期化済み（`flutter create .`）。

### 主要なファイル・ディレクトリ
- `lib/main.dart`: Flutterアプリのエントリーポイント。K-MAPSのUI/ロジックを全て実装。
- `pubspec.yaml`: 依存パッケージ管理ファイル。
- `android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/`: 各プラットフォーム用のビルド設定・ネイティブコード。
- `test/`: テストコード配置ディレクトリ。
- `FEATURES.md`: 機能設計・仕様まとめ。
- `ailog.txt`: 変更履歴ログ。

### クラス構成（現状）
- `KMapsApp`: アプリ本体（MaterialAppラッパー）
- `KMapsHomeScreen`: ホーム画面（プロジェクト新規作成・既存プロジェクト/DriveインポートUI）
- `KMapsHomePage`: 地図・レイヤ・フィーチャ編集画面
- `LayerManager`: GeoPackage/レイヤ全体管理
- `GeoPackageGroup`: GeoPackage（レイヤグループ）情報
- `Layer`: レイヤ情報（名前・種別・点フィーチャリスト）
- `_PointFeature`: 点フィーチャ（座標＋属性）

### 主要UI・機能
- ホーム画面でプロジェクト新規作成・ローカル/Driveからインポート
- プロジェクトごとにGeoPackageファイルを新規作成・初期化
- 地図表示（OpenStreetMap, flutter_map使用）
- 地図上での点フィーチャ描画（タップで追加、属性テキスト入力）
- GPS現在地の取得・表示（ストリームで常時監視、地図上に反映）
- DrawerでGeoPackage/レイヤの2階層構造管理・追加・削除・切替
- レイヤ追加時に種別（点・線・ポリゴン）選択、GeoPackageに対応テーブル作成
- BottomNavigationBarでツール切替（地図/GPS/レイヤ）
- プロジェクトフォルダ選択時、.gpkgファイルが存在しない場合は警告ダイアログを表示し、画面遷移しない
- GeoPackageファイルが存在しない場合や空パスの場合は、LayerManagerで追加・参照・変更を行わない安全設計
- レイヤやGeoPackageが1つもない場合は「未選択」状態となり、地図上の点描画やレイヤUIは非表示。案内メッセージを表示
- Google Driveインポートは未実装。ボタン押下時は未実装ダイアログを表示し、空パスで画面遷移しない
- 新規プロジェクト作成時のみ「デフォルトレイヤ」が自動追加される。既存プロジェクトを開いた場合はDB内のレイヤのみ反映。

### GeoPackage/レイヤ管理
- 複数GeoPackage（.gpkgファイル）の追加・削除が可能
- 各GeoPackageごとに複数レイヤを追加・削除・切替可能
- DrawerからGeoPackage（グループ）→レイヤ（子）の2階層構造で管理・操作
- レイヤ追加時はどのGeoPackageに追加するか選択し、物理ファイルにテーブル作成
- GeoPackageファイル新規作成時は必須メタテーブル（gpkg_spatial_ref_sys, gpkg_contents, gpkg_geometry_columns）を初期化

### 今後の拡張方針
- 線・ポリゴンフィーチャの描画・属性編集
- GeoPackage属性テーブルの編集・表示
- Google Drive連携によるプロジェクト同期
- サブフォルダ・複数GeoPackageの階層的管理
- フリーハンド描画・Undo/Redo・高度な編集ツール

## ファイル・クラス構成
- `lib/main.dart`: アプリ本体・UI・DB操作の主要ロジック
  - `KMapsApp`: アプリエントリポイント
  - `KMapsHomeScreen`: プロジェクト新規作成・インポートUI
  - `KMapsHomePage`: 地図・レイヤ・フィーチャ編集画面
  - `LayerManager`: GeoPackage/レイヤ全体管理、DBとの同期
  - `GeoPackageGroup`: GeoPackage（レイヤグループ）情報
  - `Layer`: レイヤ情報（名前・種別・点フィーチャリスト）
  - `_PointFeature`: 点フィーチャ（座標＋属性）
- `pubspec.yaml`: 依存パッケージ管理
- `README.md`: 本ファイル
- `ailog.txt`: 変更履歴

## DB仕様（GeoPackage）
- 各レイヤはSQLiteテーブルとして管理
- 点フィーチャはWKB(Point)形式で`geom`カラム（BLOB）に格納
  - WKB: 1バイトエンディアン + 4バイト型 + 8バイトX + 8バイトY（リトルエンディアン）
- 属性は`attr`カラム（TEXT）
- レイヤ削除時はDBテーブル・メタ情報も削除
- プロジェクト・レイヤ読み込み時はDBから点データを復元

## 今後の拡張
- 線・ポリゴンフィーチャの描画・属性編集
- GeoPackage属性テーブルの編集・表示
- Google Drive連携によるプロジェクト同期
- サブフォルダ・複数GeoPackageの階層的管理
- フリーハンド描画・Undo/Redo・高度な編集ツール

## 主な機能
- GeoPackage新規作成・インポート・レイヤ管理
- 地図上でMultiPoint/MultiLineString/MultiPolygonフィーチャの描画・属性入力
- GPS現在地の取得・表示
- DrawerでGeoPackage/レイヤの2階層構造管理
- レイヤ追加時に種別（MultiPoint・MultiLineString・MultiPolygon）選択、GeoPackageに対応テーブル作成
- BottomNavigationBarでツール切替（地図/GPS/レイヤ）
- MultiPolygonレイヤの外環＋穴（hole）を正しく塗りつぶし描画（PolygonLayerのholePointsList対応）

## 主要ファイル・クラス構成
- `lib/main.dart`: アプリ本体・UI・ロジック全体
  - `KMapsApp`: アプリエントリポイント
  - `KMapsHomeScreen`: プロジェクト新規作成・インポート画面
  - `KMapsHomePage`: 地図・レイヤ・フィーチャ編集画面
  - `LayerManager`: GeoPackage/レイヤ全体管理
  - `GeoPackageGroup`: GeoPackage（レイヤグループ）情報
  - `Layer`: レイヤ情報（名前・種別・フィーチャリスト）
  - `MultiPointFeature`/`MultiLineStringFeature`/`MultiPolygonFeature`: 各種フィーチャ（属性・座標）
  - PolygonLayerのPolygon生成時、holePointsListプロパティで外環＋穴（hole）をサポート

## クラス構成詳細
- `LayerManager`:
  - GeoPackageの追加・削除・レイヤ追加・削除・選択・DB同期
  - MultiPolygonFeatureのpolygons（List<List<List<LatLng>>>）を展開し、PolygonLayerのholePointsListで穴も描画
- `MultiPolygonFeature`:
  - polygons: List<List<List<LatLng>>>（外環＋穴のリスト、GeoJSON準拠）

---