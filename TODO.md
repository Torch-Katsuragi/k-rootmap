# TODO List

## 完了済み

- [x] Drive連携フォルダ機能MVP完了（2026/01/14-15）
  - [x] 認証: サイレント/明示的サインイン、トークンリフレッシュ
  - [x] フォルダ追加: 通常/Drive連携の選択ダイアログ
  - [x] URL入力: ペースト＋QRスキャン対応（mobile_scanner導入）
  - [x] クローン: 共有フォルダからの初回ダウンロード
  - [x] 永続化: .kmeta.jsonにDrive情報保存、再読み込み時にDriveFolderNodeとして復元
  - [x] 視覚的区別: 青いクラウドアイコン、同期状態オーバーレイ（↑↓）
  - [x] 手動同期: Push/Pull/状態確認/連携解除メニュー
  - [x] 自動チェック: プロジェクト読み込み時に同期状態を自動確認
  - [x] エラーハンドリング: 失敗時の適切なステータス表示、supportsAllDrives対応
  - [x] 設計書更新（google-drive.md, google-drive-setup.md）
  - 注: **モバイル専用機能**（PCでは無効化。Google Drive Desktopとの競合防止）

## 未完了

### Google Drive連携

- [ ] レイヤ単位での競合解決の実装
  - GeoPackage内のレイヤレベルでのマージ機能
  - ops.log操作ログによる細粒度な競合検出

- [x] ドキュメント構造の整理（2025/12/30）
  - [x] FEATURES.mdとDOCUMENT.mdをdocs/配下に分割
  - [x] docs/features/（機能設計8ファイル）、docs/technical/（技術資料5ファイル）
  - [x] docs/index.md（目次・ナビゲーション）作成
- [x] READMEの整理（更新履歴の削除と機能概要の統合）
- [x] 背景地図の機能改善
  - [x] 一括ダウンロード機能（範囲・ズーム指定）の実装
  - [x] ダウンロードの並列処理化（4スレッド）と進捗バー表示
  - [x] オフライン時のフォールバック処理の最適化（親タイル拡大表示の高速化）
  - [x] ネットワーク接続状態検知による無駄なリクエスト抑制（圏外対策）
  - [x] 航空写真（JPEG）タイルのダウンロード対応
- [x] 設定画面のUI統一（共通ウィジェットテンプレート作成）
- [x] 不要な型チェック・キャストの削除
  - [x] map_page.dart
  - [x] feature_converter.dart
  - [x] import_export_service.dart
- [x] 非推奨APIの更新（一部）
  - [x] withOpacity → withValues()
  - [x] onPopInvoked → onPopInvokedWithResult

## アーキテクチャ改善（2025/12/18実施）

### 完了

- [x] 型安全性の改善
  - [x] IMapStateインターフェースの作成（lib/interfaces/map_state_interface.dart）
  - [x] GlobalConfigのdynamic型を具体型に変更（mapState: IMapState, selectedFeatures: List<LayerTreeNode>）
  - [x] MapToolおよび各ツールクラスの型安全化（PanTool, PenTool, SelectTool, GpsTool）
- [x] 重複コードの削減
  - [x] geopackage_file.dartのバッチ処理メソッド共通化（_addGeometryBatch<T>）
  - [x] ダイアログヘルパークラスの作成（lib/widgets/dialogs/dialog_helpers.dart）
- [x] 定数の集約
  - [x] アプリケーション定数ファイルの作成（lib/core/constants.dart）
- [x] ファイル構造の整備
  - [x] map_page用mixinディレクトリ作成（lib/screens/map_page/）
  - [x] import_export用ディレクトリ作成（lib/services/import_export/）

### 将来の作業

- [x] map_page.dartへのmixin統合（2025/12/23完了）
  - MapPageStateBase（状態変数の定義）
  - MapInitializationMixin（初期化処理）
  - MapGpsTrackingMixin（GPS追跡サービス）
  - MapGpsSurveyMixin（GPS測量）
  - MapFeatureCacheMixin（フィーチャキャッシュ）
  - MapDrawingMixin（描画確定処理）
  - GpsInfoBar, GpsTrackingOverlay, GpsSurveyButtons（ウィジェット）
- [x] import_export_service.dartのフォーマット別分割
- [x] geopackage_file.dartの機能別分割
- [x] 内蔵GPSリファクタリング（2026/02/06）
  - [x] InternalGpsLocationStore導入（常に1ストリーム原則）
  - [x] GpsPositionRecord / GpsPositionResponse 型安全モデル作成
  - [x] Android: ForegroundService常時稼働（delegatedモード）
  - [x] Windows: Geolocator直接実行（directモード）
  - [x] Geolocatorストリーム3重重複を1本に統一
  - [x] map_initialization_mixin / map_gps_tracking_mixin をStore経由に変更
  - [x] WindowsでのGPS追跡ボタン有効化
  - [x] requestPosition()にhasNewUpdateフラグ追加
- [x] GPS軌跡の常時記録と切り取りUI（2026/02/06）
  - [x] GpsHistoryRecorder: グローバルフォルダのGeoPackageに日付別レイヤで常時記録
  - [x] 本日のGPS軌跡をPolylineLayerでリアルタイム表示（緑ライン）
  - [x] TrackExtractionDialog: 日付選択、時間範囲スライダー、Douglas-Peucker簡略化、ライン保存
  - [x] 既存の「追跡開始/停止」フローを完全廃止
  - [x] GpsTrackingOverlay（回転光エフェクト）を廃止、実際の軌跡表示に置換
  - [x] GPS追跡ボタンを軌跡抽出ボタンに変更（全プラットフォーム対応）
- [x] Riverpod状態管理基盤の導入（ServiceLocator代替）（2026/02/20）
  - [x] flutter_riverpod導入、ProviderScope設定
  - [x] GlobalConfigをプロバイダーブリッジ化（内部的にRiverpodに委譲）
  - [x] 8つのプロバイダーファイル作成（project, selection, tool, ui_state, gps, drawing, service, app_container）
- [x] Riverpod正規化リファクタリング（2026/02/20）
  - [x] flutter_riverpod v3.0.3 + riverpod_generator v3.0.3 + riverpod_annotation v3.0.3導入
  - [x] 全プロバイダーを@riverpod コード生成に移行（StateProvider → Notifier）
  - [x] GlobalConfig（Godオブジェクト）完全削除（38ファイル190箇所の依存を解消）
  - [x] setStateCallbackパターン除去（LayerDrawer系9ファイル）
  - [x] 主要ウィジェットConsumerWidget/ConsumerStatefulWidget化（MapPage, HomeScreen, MapToolbar, FAB, LayerDrawer等）
  - [x] ツールへのRef注入（PenTool, SelectTool, GpsTool, PanTool）
  - [x] mapState/folderTreeをMapPageStateBaseのstaticフィールドに移行
  - [x] selectedFeaturesをSelectedFeaturesプロバイダーに完全移行
- [x] Riverpod完全正規化（2026/02/20-25）
  - [x] appContainer（グローバルProviderContainer）をlib/から完全除去
  - [x] MapPageStateBaseのstaticフィールド除去 → 専用プロバイダ化（folderTree, mapControllerHolder, featureRefreshTrigger）
  - [x] IMapStateインターフェース依存の縮小（refreshFeatures/setState/mapController → プロバイダ経由）
  - [x] BaseMapService/GpsManagerServiceのChangeNotifierProvider → @riverpod移行
  - [x] PathResolverからのRef直接依存除去（コールバック注入方式へ）
  - [x] GeoPackageFile/GeoPackageConnectionのappContainer依存除去（projectRootDir注入）
  - [x] FeatureNodeのappContainer依存除去（onDisposeコールバック方式へ）
  - [x] GlobalDrawingState.instance直接アクセス → drawingStateProvider経由に統一
  - [x] GpsManagerService()直接インスタンス化 → gpsManagerServiceProvider経由に統一
  - [x] GpsSettingsScreenのConsumerStatefulWidget化
- [ ] 非同期競合状態防止の改善（Completer使用）
- [x] フィーチャキャッシュの差分更新対応
- [x] LayerNodeサブクラスの個別ファイル分離（部分的完了：PathResolver、NodePresenter、ExifParser、LayerMigrationService分離済み）

## コード品質改善

### 優先度：高（安全性・正確性）

- [x] BuildContextの非同期使用問題の修正
  - [x] gps_settings_screen.dart
  - [x] map_page.dart
  - [x] layer_drawer.dart
  - [x] layer_drawer_tiles.dart
  - [x] dynamic_attribute_table_widget.dart
  - [x] camera_screen.dart
  - [x] dialog_manager.dart（元々修正済み）
  - [x] gps_tracking_dialogs.dart（元々修正済み）
  - [x] metadata_table_dialog.dart
  - [x] gps_manager_example.dart

### 優先度：中（非推奨API・未使用コード）

- [ ] 非推奨APIの更新（残り）
  - [ ] DropdownButtonFormField value → initialValue
  - [ ] Radio groupValue/onChanged → RadioGroup
- [ ] 未使用importの削除（主要ファイル）

### 優先度：低（スタイル改善）

- [ ] print()をロギングフレームワークに置換
- [ ] その他のスタイル問題修正

## 機能改善

- [x] フォルダメタデータシステム（.kmeta.json）の実装
  - [x] KMetaモデルクラス（JSON読み書き・継承マージロジック）
  - [x] KMetaService（継承チェーン解決・保存処理）
  - [x] FolderNode/GeoPackageNodeへのKMeta統合
  - [x] LayerStyleConfigとKMetaの連携

- [x] グローバルフォルダ機能の実装（2026/01/08）
  - [x] GlobalFolderNode/GlobalSubFolderNodeクラス作成
  - [x] GeoPackageFile/GeoPackageConnectionに絶対パスモード追加
  - [x] GlobalGeoPackageNode/GlobalImageNodeクラス作成
  - [x] ホーム画面でのグローバルフォルダ初期化処理
  - [x] レイヤードロワーでの青色アイコン表示対応

- [x] LayerTreeNode大規模リファクタリング（2026/01/09）
  - [x] NodeType enum作成（文字列からenumに移行）
  - [x] PathResolverインターフェース作成（Project/Global実装）
  - [x] NodePresenterクラス作成（UI責務分離）
  - [x] ExifParserユーティリティ作成（EXIF解析ロジック集約）
  - [x] LayerMigrationService作成（レイヤー移植処理分離）

- [x] Google Drive連携MVP実装（2026/01/14）
  - [x] 認証基盤（google_sign_in, googleapis, flutter_secure_storage）
  - [x] GoogleDriveService/DriveAuthState（OAuth認証フロー）
  - [x] KMetaSyncを拡張（driveFolderName, driveRevisionId, deviceId追加）
  - [x] SyncEngine（Push/Pull同期機能）
  - [x] DriveConnectDialog（Drive連携ダイアログ）
  - [x] OpenFromUrlDialog（URL入力ダイアログ）
  - [x] DriveFolderPicker（フォルダ選択ダイアログ）
  - [x] セットアップガイド（docs/technical/google-drive-setup.md）
  - 注: 設計書のproject_meta.jsonは.kmeta.jsonに統合

- [ ] フィードバックフォームにバージョン情報を事前入力
  - Google FormsのURLパラメータを使用して、アプリバージョンを埋め込む
  - フォームを開いたときにバージョン情報が入力済みの状態で表示される

- [ ] ポイント詳細情報からGoogle Mapリンクをコピーする機能を追加
  - ポイントの詳細情報画面に「Google Mapリンクをコピー」ボタンを設置
  - 座標からGoogle MapsのURLを生成してクリップボードにコピー

### パフォーマンス改善

- [x] 大量フィーチャのロード・通常動作の軽量化リファクタリング（2026/02/20）
  - [x] FeatureNodeの遅延初期化・キャッシュ改善（centroid, metadata, length, area）
  - [x] FeatureRepositoryのDRY化（updatePoint/Line/Polygon統一、エンベロープ計算共通化）
  - [x] constコンストラクタ追加による再構築最小化
- [x] 巨大ファイル分割（2026/02/20）
  - [x] feature_converter.dart（2,070行）→ 7ファイル（Strategy pattern）
  - [x] layer_drawer_tiles.dart（2,073行）→ 7ファイル（機能別mixin）
  - [x] sync_engine.dart（1,895行）→ 5ファイル（handler/resolver分割）
  - [x] metadata_parser.dart（1,645行）→ 7ファイル（facade + 専門パーサー）
  - [x] map_page.dart FAB抽出 → DrawingActionButtons widget

- [x] トラッキング保存形式の変更（2026/02/20完了）
  - lineレイヤ方式に変更済み

- [x] GeoPackageロード高速化（2026/03/04）
  - [x] N+1クエリ解消: getFeaturesWithGeometry()で1クエリに統合（getFeatures+N回getFeature → 1回）
  - [x] ツリー構築の並列化: updateNodeRecursively()をFuture.waitで兄弟ノード並列初期化
  - [x] レイヤ読み込みの並列化: updateFeaturesImpl()でKMetaスタイル・DB読み込みを並列実行
  - [x] WKBパースのIsolate化: 500フィーチャ以上でcompute()による別Isolate実行

- [x] 地図操作パフォーマンス改善（2026/03/04）
  - [x] レンダリングキャッシュ: Polyline/Polygon/Markerをキャッシュし、データ変更時のみ再構築
  - [x] scheduleMarkerRefresh廃止: パン/ズーム時のsetState完全除去（300msデバウンスタイマー削除）
  - [x] ビューポートカリング廃止: Point/ImageNodeの手動カリングを削除、FlutterMap/Clusterに委譲
  - [x] selectedFeaturesのSet化: contains()をO(N)→O(1)に最適化
  - [x] flutter_map描画最適化: simplificationTolerance 0.3→1.0（Douglas-Peucker簡略化強化）
  - [x] PolygonLayer useAltRendering有効化: 三角形分割による高速Canvas描画
  - [x] パフォーマンス設定画面: simplificationTolerance/useAltRenderingをUI設定化

- [x] 宣言的設定フレームワーク導入（2026/03/04）
  - [x] SettingDef sealed class + SettingsStore: SharedPreferences/KMeta二層ストア（lib/core/settings_schema.dart）
  - [x] DataDrivenSettingsScreen: SettingDefからUI自動生成（Slider/Switch/ColorPicker/TextField）
  - [x] performance_settings_screen.dart 宣言的書き換え（265行→85行）
  - [x] layer_style_settings_screen.dart 宣言的書き換え（1424行→440行、LayerStyleConfig/LayerStyleDefaults廃止）
  - [x] map_page.dart: LayerStyleConfig参照 → SettingsStore.resolve*()に移行

## MapLibre移行（2026/03/05〜）

### 完了

- [x] maplibreパッケージのPoC（Android向けPoC画面作成済み）
- [x] FlutterMap → MapLibreMap ウィジェット置換
  - [x] KMapController/KMapCameraラッパー作成（lib/core/k_map_controller.dart）
  - [x] geo_converter.dart作成（LatLng↔Geographic変換ユーティリティ）
  - [x] map_page.dart: FlutterMap→MapLibreMap、レイヤ構成全面書き換え
  - [x] map_page_state_base.dart: キャッシュ型をmaplibre Feature型に変更
  - [x] map_state_interface.dart: MapController→KMapControllerに差替え
  - [x] ui_state_providers.dart: MapControllerHolder→KMapController対応
  - [x] feature_editor_screen.dart: MapLibreMap化
  - [x] layer_tile_builder.dart: fitCoordinates()対応
- [x] レイヤ移植（Polygon/Polyline/Marker → maplibre PolygonLayer/PolylineLayer/MarkerLayer/WidgetLayer）
- [x] MapTool系の移行（IMapState経由のKMapController差替え、ツール側変更不要）
- [x] タイルキャッシュ基盤の移行（2026/03/05）
  - [x] TileServerクラス作成（dart:io HttpServer、BaseMapService.getTile()をlocalhost経由で配信）
  - [x] map_page.dart / feature_editor_screen.dart: RasterSourceをlocalhost URLに変更
  - [x] ベースマップ切替対応（replaceBasemapSource: ソース削除→再追加）
  - [x] CachedTileLayer削除（flutter_map専用のため不要に）
  - GeoPackageキャッシュ・オフラインモード・親タイルフォールバック・一括DLは全て保持

- [x] フィーチャ描画パフォーマンス修正（OOM/カクつき解消）（2026/03/05）
  - [x] MapSourceManagerクラス作成（StyleController直接管理、layersプロパティからの脱却）
  - [x] ポリゴン/ライン/ポイント/GPS軌跡をGeoJsonSource+StyleLayerで描画（FillStyleLayer/LineStyleLayer/CircleStyleLayer）
  - [x] データ変更時のみupdateGeoJsonSource呼び出し（前回データとの比較でスキップ）
  - [x] 大量フィーチャのGeoJSONシリアライズをIsolate化（500件以上で自動適用）
  - [x] GPS待機タイマーをGpsInfoBar内部に移動（毎秒のMapPage全体rebuild除去）
  - [x] コンパス方角をValueNotifier化（秒10回以上のMapPage全体rebuild除去）
  - [x] 未使用import/show整理、deprecated API修正
  - [x] ポリゴン輪郭線を専用LineStyleLayerで描画（fill-outline-color 1px制限の回避）
  - [x] ImageNode描画をWidgetLayerに復帰（カメラアイコン+撮影方向くちばし+タップ選択）

- [x] ポイントクラスタリング実装（2026/03/06）
  - [x] superclusterパッケージ導入（Dart側クラスタリング）
  - [x] MapSourceManagerにクラスタソース/レイヤ追加（kClusters + CircleStyleLayer + SymbolStyleLayer）
  - [x] ズーム変更時にクラスタ/個別ポイントを自動再分配
  - [x] 段階的な色・サイズ変化（step expression: 10/50/200ポイントで段階変化）
  - [x] 既存クラスタリング設定（有効/無効、半径、最大ズーム）をMapSourceManagerに接続
  - [x] flutter_map_marker_clusterパッケージ削除（デッド依存解消）

- [x] ImageNode描画をSymbolStyleLayerに移行（GPU描画化）（2026/03/06）
  - [x] MapIconGenerator作成（Canvas+PictureRecorderで4枚のアイコンPNG生成: 方向あり/なし × 通常/選択）
  - [x] MapSourceManagerにImageNodeソース/レイヤ/クラスタ追加（kImages/kImagesSel/kImageClusters）
  - [x] SymbolStyleLayerでicon-image/icon-rotate/text-field使用（case/coalesce式で方向有無を自動切替）
  - [x] ImageNode専用superclusterクラスタリング（Point系と独立）
  - [x] WidgetLayerの_buildPhotoMarkers削除、GeoJSON化でsyncFeatureSourcesに統合
  - [x] タップ選択をlatlong2距離検索に置換（ズーム連動閾値）

- [x] Windows版パフォーマンス最適化（2026/03/09）
  - [x] 頂点マーカーのGPU描画化（WidgetLayer→CircleStyleLayer、パン・ズーム時のWidget再生成を排除）
  - [x] didUpdateWidget内のlayers変更チェック追加（不要なGeoJSON再処理をスキップ）
  - [x] updateLayerStylesの一括更新化（remove/add 60+回→batchSetPaintProperties 1回、E_INVALIDARGエラー解消）
  - [x] moveCamera/animateCameraにmapReady前ガード追加（Null check例外防止）
  - [ ] MapLibre GL JS/CSS/pmtiles.jsのローカルバンドル化（CDN依存排除、オフライン起動対応）
    - 注: バンドル版pmtiles.jsがNode.js用ビルドでブラウザ非互換のため保留

### 未完了

- [ ] 3D terrain有効化（RasterDemSource + setTerrain + pitch/tiltコントロール）
- [ ] 国土地理院DEMタイル → Terrain-RGB変換の実装・検証
- [ ] Flutter SDKアップグレード（3.10+）→ maplibre_webview導入（Windows対応）
